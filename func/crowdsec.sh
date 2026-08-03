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

	# CAPI: 'local' runs the engine self-hosted (no central blocklist/telemetry); default enrolls.
	[ -f "$CONF_DIR/install.conf" ] && source "$CONF_DIR/install.conf" 2> /dev/null
	[ "${COMPONENT_CROWDSEC_CAPI:-enroll}" = "local" ] && crowdsec_disable_capi

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
