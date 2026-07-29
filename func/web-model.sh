#!/bin/bash

#===========================================================================#
#                                                                           #
# HestiaRE - Web-model shared library (#120)                                #
#                                                                           #
# One source of truth for the web-serving model (nginx-only / both /        #
# apache-only) so the installer and the live model switch cannot drift.     #
# Callers: bin/h-install-hestia (install time) and the switch commands      #
# (h-add-sys-nginx / -apache2, h-delete-sys-nginx / -apache2).              #
#                                                                           #
#===========================================================================#

# web_model_keyset MODEL
# Emits the hestia.conf web keyset for a model as KEY=VALUE lines, in the exact
# order and set the installer historically wrote, so a fresh install stays
# byte-identical. nginx omits WEB_RGROUPS/PROXY_PORT/PROXY_SSL_PORT; apache omits
# the proxy ports. PROXY_SYSTEM is always emitted (empty for the proxyless models).
# The installer feeds each pair to wcv; the switch to change_sys_value, and clears
# any of the eight model keys NOT emitted here for the target model.
web_model_keyset() {
	case "$1" in
		apache | APACHE)
			printf '%s\n' \
				"WEB_SYSTEM=apache2" \
				"WEB_RGROUPS=www-data" \
				"WEB_PORT=80" \
				"WEB_SSL_PORT=443" \
				"WEB_SSL=mod_ssl" \
				"PROXY_SYSTEM="
			;;
		both | BOTH)
			printf '%s\n' \
				"WEB_SYSTEM=apache2" \
				"WEB_RGROUPS=www-data" \
				"WEB_PORT=8080" \
				"WEB_SSL_PORT=8443" \
				"WEB_SSL=mod_ssl" \
				"PROXY_SYSTEM=nginx" \
				"PROXY_PORT=80" \
				"PROXY_SSL_PORT=443"
			;;
		nginx | NGINX | *)
			printf '%s\n' \
				"WEB_SYSTEM=nginx" \
				"WEB_PORT=80" \
				"WEB_SSL_PORT=443" \
				"WEB_SSL=openssl" \
				"PROXY_SYSTEM="
			;;
	esac
}

# apache2 = customer web server. ports.conf emptied on purpose: Listen comes per
# IP from h-add-sys-ip; the hestia-status 127.0.0.1:8081 listener keeps it startable
# until the first IP registers. Idempotent, so the switch can re-run it when a target
# uses apache regardless of whether the package is already present.
configure_apache2() {
	echo "[ * ] Installing apache2..."
	hestia_apt -y install apache2 apache2-suexec-custom libapache2-mod-fcgid

	echo "[ * ] Configuring apache2..."
	mkdir -p /etc/apache2/conf.d/domains
	cp -f "$HESTIA/share/apache2/apache2.conf" /etc/apache2/
	cp -f "$HESTIA/share/apache2/status.conf" /etc/apache2/mods-available/hestia-status.conf
	cp -f /etc/apache2/mods-available/status.load /etc/apache2/mods-available/hestia-status.load
	cp -f "$HESTIA/share/apache2/logrotate" /etc/logrotate.d/apache2

	local m
	for m in rewrite suexec ssl actions headers; do
		a2enmod -q "$m" > /dev/null 2>&1 || true
	done
	a2dismod -q status > /dev/null 2>&1 || true
	a2enmod -q hestia-status > /dev/null 2>&1 || true

	# php-fpm backend: event MPM + proxy_fcgi for the FastCGI SetHandler directives
	a2dismod -q mpm_prefork > /dev/null 2>&1 || true
	a2enmod -q mpm_event > /dev/null 2>&1 || true
	a2enmod -q proxy_fcgi setenvif > /dev/null 2>&1 || true
	# proxy_http: apache webmail vhosts reverse-proxy to the Caddy webmail listeners
	a2enmod -q proxy_http > /dev/null 2>&1 || true
	cp -f "$HESTIA/share/apache2/hestia-event.conf" /etc/apache2/conf.d/

	# no distro default site, no global Listen ports
	a2dissite -q 000-default > /dev/null 2>&1 || true
	echo "# Powered by hestia" > /etc/apache2/ports.conf

	echo -e "/home\npublic_html/cgi-bin" > /etc/apache2/suexec/www-data
	touch /var/log/apache2/access.log /var/log/apache2/error.log
	mkdir -p /var/log/apache2/domains
	chmod a+x /var/log/apache2
	chmod 640 /var/log/apache2/access.log /var/log/apache2/error.log
	chmod 751 /var/log/apache2/domains

	update-rc.d apache2 defaults > /dev/null 2>&1
	# restart, not start: replace the distro config the package start brought up
	systemctl restart apache2
}

# apache_remoteip_enable [IP...]
# Trust nginx as the front proxy so apache logs/fail2ban see the real client IP.
# Only correct in the "both" model. Trusted proxies = loopback + every passed IP
# (deduped): the installer passes the primary + public IP, the switch passes all
# system IPs. Idempotent (conf is rewritten wholesale). Does NOT reload - the caller
# owns the restart.
apache_remoteip_enable() {
	local ip seen=""
	{
		echo "<IfModule mod_remoteip.c>"
		echo "  RemoteIPHeader X-Real-IP"
		echo "  RemoteIPInternalProxy 127.0.0.1"
		for ip in "$@"; do
			[ -n "$ip" ] || continue
			case " $seen " in *" $ip "*) continue ;; esac
			seen="$seen $ip"
			echo "  RemoteIPInternalProxy $ip"
		done
		echo "</IfModule>"
	} > /etc/apache2/mods-available/remoteip.conf
	# Log the translated client address (%a) instead of the peer (%h)
	sed -i 's/LogFormat "%h/LogFormat "%a/g' /etc/apache2/apache2.conf
	a2enmod -q remoteip > /dev/null 2>&1 || true
}

# apache_remoteip_disable
# Undo the toggle when a target no longer fronts apache with nginx (any non-both).
# Without this an X-Real-IP header would be trusted with no proxy in front - a real
# client-IP spoofing regression. Does NOT reload - the caller owns the restart.
apache_remoteip_disable() {
	a2dismod -q remoteip > /dev/null 2>&1 || true
	rm -f /etc/apache2/mods-available/remoteip.conf
	# Revert the client-IP log format back to the peer address
	sed -i 's/LogFormat "%a/LogFormat "%h/g' /etc/apache2/apache2.conf
}
