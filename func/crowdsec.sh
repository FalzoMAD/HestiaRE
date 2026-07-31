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

	systemctl restart crowdsec > /dev/null 2>&1 || true
	if nginx -t > /dev/null 2>&1; then
		systemctl reload nginx > /dev/null 2>&1 || systemctl restart nginx > /dev/null 2>&1
	else
		echo "CrowdSec: nginx config test failed after wiring - not reloading" >&2
		return 1
	fi
	echo "CrowdSec: applied (nginx front, bouncer hestia-nginx)."
}

# Remove the nginx-side wiring (the #120 switch away from nginx, later h-delete-sys-crowdsec).
# Leaves the engine + /etc/crowdsec state in place (saved state).
crowdsec_remove_nginx() {
	rm -f /etc/nginx/conf.d/crowdsec_init.conf /usr/local/hestia/lua/hestia_bouncer.lua
	nginx -t > /dev/null 2>&1 && { systemctl reload nginx > /dev/null 2>&1 || true; }
}
