# CrowdSec integration helpers (#186). Apply/refresh the detection + nginx Layer-A
# wiring for the current web model. Sourced by the installer (install_security), the
# #120 web-model switch, and (later, #123) h-add-sys-crowdsec - one shared path so every
# caller stays consistent. Idempotent; a no-op unless nginx is the public front.

# Public-facing web system: PROXY_SYSTEM if set ('both' fronts with nginx), else
# WEB_SYSTEM. Deliberately not "is nginx installed" - only the exposed server matters.
crowdsec_public_web() {
	if [ -n "$PROXY_SYSTEM" ]; then
		echo "$PROXY_SYSTEM"
	else
		echo "$WEB_SYSTEM"
	fi
}

# Run the engine fully local: comment out the CAPI online_client so there is no
# central-blocklist pull or signal sharing (the wizard's local-only choice). Idempotent.
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

	# Engine + nginx lua module (both OS-repo). The module auto-loads via
	# modules-enabled and pulls lua-resty-core itself; our bouncer needs no lua-resty-*.
	DEBIAN_FRONTEND=noninteractive apt-get -y -qq install crowdsec libnginx-mod-http-lua > /dev/null 2>&1 \
		|| { echo "CrowdSec: package install failed" >&2; return 1; }

	# Curated web collections + acquisition on the nginx front logs. LAPI already on
	# :8054 (h-install-hestia). Collection failures are non-fatal (hub/network hiccup).
	cscli hub update > /dev/null 2>&1 || true
	local col
	while read -r col; do
		case "$col" in '' | \#*) continue ;; esac
		cscli collections install "$col" > /dev/null 2>&1 || true
	done < "$share/collections.list"
	# The nginx front logs to /var/log/$WEB_SYSTEM/domains (the vhost template uses the
	# web_system token, so 'both' resolves to /var/log/apache2/domains - still nginx's
	# own front log with the real client IP).
	mkdir -p /etc/crowdsec/acquis.d
	sed "s|%WEB_SYSTEM%|$WEB_SYSTEM|g" "$share/acquis.d/hestia-nginx.yaml" \
		> /etc/crowdsec/acquis.d/hestia-nginx.yaml

	# Bouncer key is shown only at creation, so persist it in the lua config and only
	# (re)create when the registration or that file is missing.
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
		chmod 640 "$keyfile"
	fi

	# Bouncer runtime + http-block init glue (conf.d is included in http{} before the
	# domain vhosts). Enforcement itself stays per-vhost (per-domain opt-out).
	mkdir -p /usr/local/hestia/lua
	cp -f "$share/lua/hestia_bouncer.lua" /usr/local/hestia/lua/hestia_bouncer.lua
	cp -f "$share/nginx/crowdsec_init.conf" /etc/nginx/conf.d/crowdsec_init.conf
	# Layer-B rate-limit zones + bot map (http context, referenced by per-domain fragments).
	cp -f "$share/nginx/ratelimit.conf" /etc/nginx/conf.d/crowdsec_ratelimit.conf

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
	echo "CrowdSec: applied (nginx front, bouncer hestia-nginx)."
}

# Render the per-domain fragment (Layer-A access_by_lua + Layer-B rate-limit/bot policy)
# into the public nginx vhost dir, at server scope. Reads the domain's own flags; called
# by the h-*-web-domain-crowdsec commands and by the web rebuild. Removed when empty, so
# the `include ...*;` glob is simply a no-op for unprotected domains.
crowdsec_render_domain_fragment() {
	local user="$1" domain="$2" sys
	if [ -n "$PROXY_SYSTEM" ]; then sys="$PROXY_SYSTEM"; else sys="$WEB_SYSTEM"; fi
	[ "$sys" = "nginx" ] || return 0

	local rec
	rec=$(grep -m1 "DOMAIN='$domain'" "$CONF_DIR/users/$user/web.conf" 2> /dev/null)
	[ -n "$rec" ] || return 0
	local cs rl bp z
	cs=$(sed -n "s/.*CROWDSEC='\([^']*\)'.*/\1/p" <<< "$rec")
	rl=$(sed -n "s/.*RATE_LIMIT='\([^']*\)'.*/\1/p" <<< "$rec")
	bp=$(sed -n "s/.*BOT_POLICY='\([^']*\)'.*/\1/p" <<< "$rec")
	[ -n "$bp" ] || bp="pass"

	local frag="$HOMEDIR/$user/conf/web/$domain/nginx.crowdsec.conf" tmp
	tmp=$(mktemp)

	# Layer A: CrowdSec ban check. rewrite phase (not access): runs before auth_basic
	# (401), the forcessl `return 301`, and limit_req - a banned IP is refused first.
	if [ "$cs" = "yes" ]; then
		echo 'rewrite_by_lua_block { require("hestia_bouncer").allow() }' >> "$tmp"
	fi

	# Layer B: bot policy + rate-limit (429). The zone encodes throttle-vs-pass, chosen
	# here; $cs_good_bot (a global map) is the only part evaluated at request time.
	[ "$bp" = "block" ] && echo 'if ($cs_good_bot) { return 403; }' >> "$tmp"
	case "$rl" in
		lenient) [ "$bp" = "pass" ] && z="cs_lenient_pass" || z="cs_lenient"
			echo "limit_req zone=$z burst=60 nodelay;" >> "$tmp" ;;
		strict) [ "$bp" = "pass" ] && z="cs_strict_pass" || z="cs_strict"
			echo "limit_req zone=$z burst=20 nodelay;" >> "$tmp" ;;
	esac

	if [ -s "$tmp" ]; then
		mv -f "$tmp" "$frag"
		chown root:"$user" "$frag"
		chmod 640 "$frag"
	else
		rm -f "$tmp" "$frag"
	fi
}

# Remove the nginx-side wiring (the #120 switch away from nginx, later h-delete-sys-crowdsec).
# Leaves the engine + /etc/crowdsec state in place (saved state).
crowdsec_remove_nginx() {
	rm -f /etc/nginx/conf.d/crowdsec_init.conf /usr/local/hestia/lua/hestia_bouncer.lua
	nginx -t > /dev/null 2>&1 && { systemctl reload nginx > /dev/null 2>&1 || true; }
}
