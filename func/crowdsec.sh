#!/bin/bash
# CrowdSec helpers: install + wire the engine + nginx Layer-A bouncer for the current web model.
# Shared by the installer, the web-model switch and h-add-sys-crowdsec. Idempotent; no-op off-nginx.

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

# The packages generate both credential files 0644, but they hold the LAPI and CAPI machine passwords
# and customers have shell access on these boxes. The engine and cscli run as root, so 0600 costs
# nothing. Called from every entry point that touches the model, not just at install.
crowdsec_secure_credentials() {
	chmod 600 /etc/crowdsec/local_api_credentials.yaml /etc/crowdsec/online_api_credentials.yaml 2> /dev/null || true
}

# Inverse of crowdsec_disable_capi, for a runtime switch back to the community blocklist (#494).
crowdsec_enable_capi() {
	local cfg="/etc/crowdsec/config.yaml" creds="/etc/crowdsec/online_api_credentials.yaml"
	[ -f "$cfg" ] || return 0
	local uncommented=0
	if ! grep -qE '^[[:space:]]*credentials_path:.*online_api_credentials' "$cfg"; then
		# Anchored on the marker disable_capi leaves behind, so a config commented out by hand
		# (or by a future CrowdSec default) is not silently rewritten.
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
	# `cscli capi register` (1.4.x) LOADS the credentials file before writing it, so it needs both an
	# uncommented online_client AND the file to exist - an empty one is enough, an absent one is a hard
	# failure either way round. The OS packages register at postinst, so this only covers a wiped file.
	if [ ! -f "$creds" ]; then
		: > "$creds"
		chmod 600 "$creds"
		if ! cscli capi register -f "$creds" > /dev/null 2>&1 || ! grep -q '^login:' "$creds" 2> /dev/null; then
			# Never leave the config pointing at credentials that are not there - the engine would
			# keep running but silently never reach the CAPI. Back to a consistent local box.
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

# The live model, DERIVED from artefacts rather than stored: install.conf holds the install recipe,
# not the current state (#494). mesh wins because it implies local; a box carrying both mesh and an
# active CAPI is the inconsistent legacy combination the two-flag wizard (<= v0.13.2) allowed, so it
# reports mesh+capi and the mode command re-normalises it.
crowdsec_current_mode() {
	local mesh=0 capi=0
	# No engine at all (apache-only, or CrowdSec removed) is not "local" - say so, or a caller that
	# only prints the answer would report a model for a box that has none.
	[ -f /etc/crowdsec/config.yaml ] || { echo "none"; return 0; }
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

# Install + wire CrowdSec detection and the nginx Layer-A bouncer. Safe to re-run.
crowdsec_apply() {
	local share="$HESTIA/share/crowdsec"

	if [ "$(crowdsec_public_web)" != "nginx" ]; then
		echo "CrowdSec: nginx is not the public front - nothing to apply."
		return 0
	fi

	# Engine + nginx lua module (OS-repo; the module auto-loads + pulls lua-resty-core itself).
	DEBIAN_FRONTEND=noninteractive apt-get -y -qq install crowdsec libnginx-mod-http-lua > /dev/null 2>&1 \
		|| { echo "CrowdSec: package install failed" >&2; return 1; }

	# Curated web collections (LAPI already on :8054); failures non-fatal (hub/network hiccup).
	cscli hub update > /dev/null 2>&1 || true
	local col
	while read -r col; do
		case "$col" in '' | \#*) continue ;; esac
		cscli collections install "$col" > /dev/null 2>&1 || true
	done < "$share/collections.list"
	# Drop nginx-req-limit-exceeded: it fires on OUR Layer-B 429 and (leaky bucket) turns throttling
	# into a ban. Removing it taints the collection, so cscli keeps it removed on re-runs; Layer B stays 429.
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
		[ -n "$key" ] || { echo "CrowdSec: bouncer registration failed" >&2; return 1; }
		cat > "$keyfile" <<-EOF
			-- CrowdSec nginx bouncer config (#186). Generated - do not edit.
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
	mkdir -p /usr/local/hestia/lua
	cp -f "$share/lua/hestia_bouncer.lua" /usr/local/hestia/lua/hestia_bouncer.lua
	cp -f "$share/nginx/crowdsec_init.conf" /etc/nginx/conf.d/crowdsec_init.conf
	# NB: web bot rate-limiting (Layer B) is a separate, server-native subsystem (func/botpolicy.sh,
	# wired at web install) - NOT rendered here; CrowdSec only owns Layer A (the ban -> 403 bouncer).

	# Model: only 'capi' keeps the central blocklist/telemetry. 'local' and 'mesh' both run the engine
	# self-hosted - mesh is local plus peer exchange, so it must not enrol either.
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

	echo "CrowdSec: applied (nginx front, L7 bouncer hestia-nginx + L3 ipset feeder)."
}

# L3: an own feeder (h-update-firewall-crowdsec, systemd timer) fills the crowdsec-blacklists ipset;
# h-update-firewall owns the DROP. Not the OS firewall-bouncer (0.0.25 nil-panics in ipset - fleet).
crowdsec_l3_setup() {
	local share="$HESTIA/share/crowdsec"
	local marker="$CONF_DIR/firewall/crowdsec.conf"

	command -v cscli > /dev/null 2>&1 || { echo "CrowdSec: cscli missing, L3 skipped" >&2; return 1; }
	# jq drives the feeder's decision filter.
	command -v jq > /dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get -y -qq install jq > /dev/null 2>&1

	# Marker: presence gates the set + DROP chain and the feed.
	mkdir -p "$CONF_DIR/firewall"
	if [ ! -f "$marker" ]; then
		cat > "$marker" <<-EOF
			# HestiaRE CrowdSec L3 marker. Presence enables the crowdsec-blacklists ipset +
			# the hestia-crowdsec DROP chain and the feeder timer. Managed by func/crowdsec.sh; do not edit.
			SET='crowdsec-blacklists'
		EOF
		chmod 640 "$marker"
	fi

	ipset create -exist crowdsec-blacklists hash:net timeout 0 maxelem 131072 2> /dev/null

	# Timer + initial fill, then build the chain. h-update-firewall self-guards mid-install
	# (no rules.conf yet -> the configure stage rebuilds later).
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
	# Tear the iptables side down directly (h-update-firewall now skips it - marker gone).
	iptables -D INPUT -m set --match-set crowdsec-blacklists src -j hestia-crowdsec 2> /dev/null || true
	iptables -F hestia-crowdsec 2> /dev/null || true
	iptables -X hestia-crowdsec 2> /dev/null || true
	ipset destroy crowdsec-blacklists 2> /dev/null || true
	"$BIN/h-update-firewall" > /dev/null 2>&1 || true
}

# Render the per-domain CrowdSec Layer-A fragment (the ban-check rewrite_by_lua) into the public
# nginx vhost dir. Layer A is nginx-only; apache-only has no CrowdSec. Layer-B rate-limiting is a
# separate subsystem (func/botpolicy.sh -> nginx.botlimit.conf). Removed when off, so the vhost's
# `include ...nginx.crowdsec.conf*;` glob is a no-op for unprotected domains.
crowdsec_render_domain_fragment() {
	local user="$1" domain="$2" sys
	if [ -n "$PROXY_SYSTEM" ]; then sys="$PROXY_SYSTEM"; else sys="$WEB_SYSTEM"; fi

	local frag="$HOMEDIR/$user/conf/web/$domain/nginx.crowdsec.conf"
	# apache-only never runs CrowdSec; make sure no stale Layer-A fragment lingers.
	if [ "$sys" != "nginx" ]; then
		rm -f "$frag"
		return 0
	fi

	local rec cs
	rec=$(grep -m1 "DOMAIN='$domain'" "$CONF_DIR/users/$user/web.conf" 2> /dev/null)
	[ -n "$rec" ] || return 0
	cs=$(sed -n "s/.*CROWDSEC='\([^']*\)'.*/\1/p" <<< "$rec")

	# Ban check in the rewrite phase (before auth_basic 401, the forcessl 301 and limit_req) -
	# a banned IP is refused first, everywhere.
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
	rm -f /etc/nginx/conf.d/crowdsec_init.conf /usr/local/hestia/lua/hestia_bouncer.lua
	nginx -t > /dev/null 2>&1 && { systemctl reload nginx > /dev/null 2>&1 || true; }
}
