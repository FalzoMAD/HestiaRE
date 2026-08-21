#!/bin/bash
# Engine + nginx Layer-A bouncer for the current web model. Idempotent; no-op when nginx is not the front.

# Declared here rather than in each of the six callers. Guarded: re-sourcing would reset an in-flight batch.
# shellcheck source=/usr/local/hestia/include/firewall.sh
declare -F fw_set_chain_destroy > /dev/null 2>&1 || source "$HESTIA/include/firewall.sh"

# The EXPOSED web server (PROXY_SYSTEM fronts in 'both'), not "is nginx installed".
crowdsec_public_web() {
	if [ -n "$PROXY_SYSTEM" ]; then
		echo "$PROXY_SYSTEM"
	else
		echo "$WEB_SYSTEM"
	fi
}

# Local-only engine: comment out the CAPI online_client (no central pull / signal sharing). Idempotent.
crowdsec_disable_capi() {
	local cfg="/etc/crowdsec/config.yaml"
	[ -f "$cfg" ] || return 0
	grep -qE '^[[:space:]]*credentials_path:.*online_api_credentials' "$cfg" || return 0
	sed -i -E \
		-e 's|^([[:space:]]*)(online_client:.*)|\1# \2 (local-only, #186)|' \
		-e 's|^([[:space:]]*)(credentials_path:[[:space:]]*/etc/crowdsec/online_api_credentials.*)|\1# \2|' \
		"$cfg"
}

# The packages leave both credential files 0644 while they hold machine passwords, and customers have shell
# access here. Everything reading them runs as root, so 0600 costs nothing.
crowdsec_secure_credentials() {
	chmod 600 /etc/crowdsec/local_api_credentials.yaml /etc/crowdsec/online_api_credentials.yaml 2> /dev/null || true
}

# Inverse of crowdsec_disable_capi, for a runtime switch back to the community blocklist.
crowdsec_enable_capi() {
	local cfg="/etc/crowdsec/config.yaml" creds="/etc/crowdsec/online_api_credentials.yaml"
	[ -f "$cfg" ] || return 0
	local uncommented=0
	if ! grep -qE '^[[:space:]]*credentials_path:.*online_api_credentials' "$cfg"; then
		# Anchored on disable_capi's own marker, so a hand-commented config is not silently rewritten.
		sed -i -E \
			-e 's|^([[:space:]]*)# (online_client:.*) \(local-only, #186\)$|\1\2|' \
			-e 's|^([[:space:]]*)# (credentials_path:[[:space:]]*/etc/crowdsec/online_api_credentials.*)$|\1\2|' \
			"$cfg"
		grep -qE '^[[:space:]]*credentials_path:.*online_api_credentials' "$cfg" || {
			echo "CrowdSec: could not re-enable the CAPI online_client in $cfg - edit it by hand." >&2
			return 1
		}
		uncommented=1
	fi
	# `cscli capi register` (1.4.x) LOADS the credentials file before writing it: an empty one is enough, an
	# absent one is a hard failure. The OS packages register at postinst, so this only covers a wiped file.
	if [ ! -f "$creds" ]; then
		: > "$creds"
		chmod 600 "$creds"
		if ! cscli capi register -f "$creds" > /dev/null 2>&1 || ! grep -q '^login:' "$creds" 2> /dev/null; then
			# Config pointing at absent credentials keeps the engine running but never reaching the CAPI.
			rm -f "$creds"
			[ "$uncommented" = 1 ] && crowdsec_disable_capi
			echo "CrowdSec: CAPI registration failed - left in local mode. Check egress and 'cscli capi status'." >&2
			return 1
		fi
	elif ! grep -q '^login:' "$creds" 2> /dev/null; then
		[ "$uncommented" = 1 ] && crowdsec_disable_capi
		echo "CrowdSec: $creds carries no CAPI login - fix or delete it, then retry." >&2
		return 1
	fi
	crowdsec_secure_credentials
}

# DERIVED from artefacts, not stored: install.conf holds the recipe, not the current state. mesh implies
# local so it wins; mesh+capi is the legacy combination the two-flag wizard allowed, and gets re-normalised.
crowdsec_current_mode() {
	local mesh=0 capi=0
	# No engine at all is not "local", or a caller would report a model for a box that has none.
	[ -f /etc/crowdsec/config.yaml ] || {
		echo "none"
		return 0
	}
	[ -f "$CONF_DIR/crowdsec/mesh.conf" ] && mesh=1
	grep -qE '^[[:space:]]*credentials_path:.*online_api_credentials' /etc/crowdsec/config.yaml 2> /dev/null && capi=1
	if [ "$mesh" = 1 ] && [ "$capi" = 1 ]; then
		echo "mesh+capi"
	elif [ "$mesh" = 1 ]; then
		echo "mesh"
	elif [ "$capi" = 1 ]; then
		echo "capi"
	else
		echo "local"
	fi
}

# SSH detection only when fail2ban is ABSENT, or the two double up. Scenario-level, not collection:
# crowdsecurity/linux bundles sshd and would re-pull it, while dropping the two scenarios keeps its parsers.
# fail2ban presence read from the FILE - the installer shell never sees the key it just wrote.
CS_BF_SCENARIOS="crowdsecurity/ssh-bf crowdsecurity/ssh-slow-bf"
crowdsec_gate_bruteforce() {
	command -v cscli > /dev/null 2>&1 || return 0
	local f2b changed='no' s f
	f2b="$(sed -n "s/^FIREWALL_EXTENSION='\([^']*\)'.*/\1/p" "$HESTIA/conf/hestia.conf" 2> /dev/null)"
	for s in $CS_BF_SCENARIOS; do
		f="/etc/crowdsec/scenarios/${s##*/}.yaml"
		if [ "$f2b" = 'fail2ban' ]; then
			[ -e "$f" ] && {
				cscli scenarios remove "$s" > /dev/null 2>&1
				changed='yes'
			}
		else
			[ -e "$f" ] || {
				cscli scenarios install "$s" > /dev/null 2>&1
				changed='yes'
			}
		fi
	done
	[ "$changed" = 'yes' ] && systemctl reload crowdsec > /dev/null 2>&1
	return 0
}

# Install + wire CrowdSec detection and the nginx Layer-A bouncer. Safe to re-run.
crowdsec_apply() {
	local share="$HESTIA/share/crowdsec"

	if [ "$(crowdsec_public_web)" != "nginx" ]; then
		echo "CrowdSec: nginx is not the public front - nothing to apply."
		return 0
	fi

	# Engine + nginx lua module (OS-repo; the module auto-loads + pulls lua-resty-core itself).
	DEBIAN_FRONTEND=noninteractive apt-get -y -qq install crowdsec libnginx-mod-http-lua > /dev/null 2>&1 \
		|| {
			echo "CrowdSec: package install failed" >&2
			return 1
		}

	# Curated web collections (LAPI already on :8054); failures non-fatal (hub/network hiccup).
	cscli hub update > /dev/null 2>&1 || true
	local col
	while read -r col; do
		case "$col" in '' | \#*) continue ;; esac
		cscli collections install "$col" > /dev/null 2>&1 || true
	done < "$share/collections.list"
	# nginx-req-limit-exceeded fires on OUR Layer-B 429 and turns throttling into a ban. Removing taints the
	# collection, so cscli keeps it removed on re-runs.
	cscli scenarios remove crowdsecurity/nginx-req-limit-exceeded > /dev/null 2>&1 || true
	# nginx front logs to /var/log/$WEB_SYSTEM/domains (real client IP; 'both' -> apache2 path, still nginx's).
	mkdir -p /etc/crowdsec/acquis.d
	sed "s|%WEB_SYSTEM%|$WEB_SYSTEM|g" "$share/acquis.d/hestia-nginx.yaml" \
		> /etc/crowdsec/acquis.d/hestia-nginx.yaml

	# Key is shown only at creation -> persist it in the lua config; (re)create only when missing.
	mkdir -p /etc/crowdsec/bouncers
	local keyfile="/etc/crowdsec/bouncers/hestia-nginx.lua"
	if ! cscli bouncers list -o raw 2> /dev/null | grep -q '^hestia-nginx,' || [ ! -s "$keyfile" ]; then
		cscli bouncers delete hestia-nginx > /dev/null 2>&1 || true
		local key
		key=$(cscli bouncers add hestia-nginx -o raw 2> /dev/null)
		[ -n "$key" ] || {
			echo "CrowdSec: bouncer registration failed" >&2
			return 1
		}
		cat > "$keyfile" <<- EOF
			-- CrowdSec nginx bouncer config. Generated - do not edit.
			return {
				host = "127.0.0.1", port = 8054,
				api_key = "$key",
				cache_ttl = 30, ban_ttl = 60, timeout = 1000, fail_open = true,
				dict = "crowdsec_cache",
			}
		EOF
		# 600: holds the LAPI key, read only by nginx's master (root) at (re)load, before workers fork.
		chmod 600 "$keyfile"
	fi

	# Bouncer runtime + http-block init glue (conf.d loads in http{} before vhosts); enforcement per-vhost.
	# The bouncer CODE lives next to its config under /etc/crowdsec/bouncers, not in a lua dir of its
	# own under the install root: share/ is a template source that setup copies FROM, never a runtime
	# include path. cp -f so a Hestia update refreshes the code; the config there is seed-if-absent.
	cp -f "$share/lua/hestia_bouncer.lua" /etc/crowdsec/bouncers/hestia_bouncer.lua
	cp -f "$share/nginx/crowdsec_init.conf" /etc/nginx/conf.d/crowdsec_init.conf
	# Layer B (bot rate limiting) is include/botpolicy.sh, wired at web install. CrowdSec owns Layer A only.

	# Only 'capi' keeps the central blocklist. mesh is local plus peer exchange, so it must not enrol either.
	[ -f "$CONF_DIR/install.conf" ] && source "$CONF_DIR/install.conf" 2> /dev/null
	[ "${COMPONENT_CROWDSEC_MODE:-capi}" = "capi" ] || crowdsec_disable_capi

	crowdsec_secure_credentials

	systemctl restart crowdsec > /dev/null 2>&1 || true
	if nginx -t > /dev/null 2>&1; then
		systemctl reload nginx > /dev/null 2>&1 || systemctl restart nginx > /dev/null 2>&1
	else
		echo "CrowdSec: nginx config test failed after wiring - not reloading" >&2
		return 1
	fi

	# L3: SYN-level ban of the same decisions; non-fatal so L7 stays up if L3 wiring hiccups.
	crowdsec_l3_setup || echo "CrowdSec: L3 feeder setup reported an issue" >&2

	# fail2ban owns brute force when present, CrowdSec owns Layer-7 - so each side drops the other's jobs.
	crowdsec_gate_bruteforce
	if [ "$(sed -n "s/^FIREWALL_EXTENSION='\([^']*\)'.*/\1/p" "$HESTIA/conf/hestia.conf" 2> /dev/null)" = 'fail2ban' ] \
		&& [ -f /etc/fail2ban/jail.d/hestia.local ]; then
		# shellcheck source=/usr/local/hestia/include/fail2ban.sh
		declare -F fail2ban_gate_web_jail > /dev/null 2>&1 || source "$HESTIA/include/fail2ban.sh"
		fail2ban_gate_web_jail
		systemctl reload-or-restart fail2ban > /dev/null 2>&1
	fi

	echo "CrowdSec: applied (nginx front, L7 bouncer hestia-nginx + L3 set feeder)."
}

# Own feeder fills the set, h-update-firewall owns the DROP. Not the OS bouncer: 0.0.25 nil-panics (fleet).
crowdsec_l3_setup() {
	local share="$HESTIA/share/crowdsec"
	local marker="$CONF_DIR/firewall/crowdsec.conf"

	command -v cscli > /dev/null 2>&1 || {
		echo "CrowdSec: cscli missing, L3 skipped" >&2
		return 1
	}
	# jq drives the feeder's decision filter.
	command -v jq > /dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get -y -qq install jq > /dev/null 2>&1

	# Marker: presence gates the set + DROP chain and the feed.
	mkdir -p "$CONF_DIR/firewall"
	if [ ! -f "$marker" ]; then
		cat > "$marker" <<- EOF
			# HestiaRE CrowdSec L3 marker: presence enables the set, the DROP chain and the feeder timer.
			# Managed by include/crowdsec.sh; do not edit.
			SET='crowdsec-blacklists'
		EOF
		chmod 640 "$marker"
	fi

	# h-update-firewall self-guards mid-install: no rules.conf yet, the configure stage rebuilds later.
	cp -f "$share/systemd/hestia-crowdsec-l3.service" /etc/systemd/system/hestia-crowdsec-l3.service
	cp -f "$share/systemd/hestia-crowdsec-l3.timer" /etc/systemd/system/hestia-crowdsec-l3.timer
	systemctl daemon-reload
	systemctl enable --now hestia-crowdsec-l3.timer > /dev/null 2>&1 || true
	"$BIN/h-update-firewall-crowdsec" > /dev/null 2>&1 || true
	"$BIN/h-update-firewall" > /dev/null 2>&1 || true
}

# Remove the L3 wiring (timer + marker + chain/jump + set); leaves the engine + /etc/crowdsec.
crowdsec_l3_teardown() {
	systemctl disable --now hestia-crowdsec-l3.timer > /dev/null 2>&1 || true
	systemctl stop hestia-crowdsec-l3.service > /dev/null 2>&1 || true
	rm -f /etc/systemd/system/hestia-crowdsec-l3.service /etc/systemd/system/hestia-crowdsec-l3.timer
	systemctl daemon-reload
	rm -f "$CONF_DIR/firewall/crowdsec.conf"
	# Tear the firewall side down directly (h-update-firewall now skips it - marker gone).
	fw_set_chain_destroy hestia-crowdsec crowdsec-blacklists
	rm -f "$CONF_DIR/firewall/crowdsec.iplist"
	"$BIN/h-update-firewall" > /dev/null 2>&1 || true
}

# The per-domain Layer-A ban check, into the public nginx vhost dir - nginx-only, apache has no CrowdSec.
# Removed when off, so the vhost's `include ...nginx.crowdsec.conf*;` glob is a no-op for that domain.
# crowdsec_domain_capable - can a per-domain fragment do anything here?
#
# The field is intent, this is capability: an nginx without the bouncer either fails to parse the
# directive, invalidating the whole config, or answers 500 per request. Keyed on the artefact the
# apply step installs, and asked from here by both the renderer and the restore's report.
crowdsec_domain_capable() {
	local sys
	if [ -n "$PROXY_SYSTEM" ]; then sys="$PROXY_SYSTEM"; else sys="$WEB_SYSTEM"; fi
	[ "$sys" = "nginx" ] && [ -f /etc/nginx/conf.d/crowdsec_init.conf ]
}

crowdsec_render_domain_fragment() {
	local user="$1" domain="$2"

	local frag="$HOMEDIR/$user/conf/web/$domain/nginx.crowdsec.conf"
	# Leftovers of a removal go at the next rebuild.
	if ! crowdsec_domain_capable; then
		rm -f "$frag"
		return 0
	fi

	local rec cs
	rec=$(grep -m1 -F "DOMAIN='$domain'" "$CONF_DIR/users/$user/web.conf" 2> /dev/null)
	[ -n "$rec" ] || return 0
	cs=$(sed -n "s/.*CROWDSEC='\([^']*\)'.*/\1/p" <<< "$rec")

	# Rewrite phase, i.e. ahead of auth_basic 401, the forcessl 301 and limit_req: banned is refused first.
	if [ "$cs" = "yes" ]; then
		echo 'rewrite_by_lua_block { require("hestia_bouncer").allow() }' > "$frag"
		chown root:"$user" "$frag"
		chmod 640 "$frag"
	else
		rm -f "$frag"
	fi
}

# Remove the nginx-side wiring (leaves the engine + /etc/crowdsec saved state).
crowdsec_remove_nginx() {
	rm -f /etc/nginx/conf.d/crowdsec_init.conf /etc/crowdsec/bouncers/hestia_bouncer.lua
	# The per-domain fragments call require("hestia_bouncer"), the file just removed. Left behind they
	# answer 500 on every request, and the reload below would put that live immediately - nginx -t
	# still passes, because the directive parses as long as the lua module is installed. Found from
	# the tree rather than from the records: a fragment can outlive the record that asked for it.
	find "${HOMEDIR:-/home}" -mindepth 5 -maxdepth 5 -path '*/conf/web/*' -name 'nginx.crowdsec.conf' \
		-delete 2> /dev/null
	nginx -t > /dev/null 2>&1 && { systemctl reload nginx > /dev/null 2>&1 || true; }
}
