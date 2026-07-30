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

# apt wrapper that stays installer-consistent: at install time hestia_apt (spinner +
# $LOG capture, func/helper.sh) is used unchanged; from the live switch (no $LOG) it
# falls back to a plain noninteractive apt-get, conffile-safe for re-installs. This keeps
# a fresh install's behaviour identical while letting configure_apache2 run standalone.
_web_apt_install() {
	if declare -F hestia_apt > /dev/null 2>&1 && [ -n "${LOG:-}" ]; then
		hestia_apt -y install "$@"
	else
		DEBIAN_FRONTEND=noninteractive apt-get -y \
			-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install "$@"
	fi
}
_web_apt_purge() {
	if declare -F hestia_apt > /dev/null 2>&1 && [ -n "${LOG:-}" ]; then
		hestia_apt -y purge "$@"
	else
		DEBIAN_FRONTEND=noninteractive apt-get -y purge "$@"
	fi
}

# apache2 = customer web server. ports.conf emptied on purpose: Listen comes per
# IP from h-add-sys-ip; the hestia-status 127.0.0.1:8081 listener keeps it startable
# until the first IP registers. Idempotent, so the switch can re-run it when a target
# uses apache regardless of whether the package is already present.
configure_apache2() {
	echo "[ * ] Installing apache2..."
	_web_apt_install apache2 apache2-suexec-custom libapache2-mod-fcgid

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

# rebuild_ip_web_config IP
# (Re)generate the per-IP unassigned web + proxy configs for the current model, read
# from the model globals. Extracted verbatim from h-add-sys-ip (144-181) so the IP add
# and the model switch share one copy (#120). The MEF/rpaf/remoteip proxy-registration
# appends stay in h-add-sys-ip (dormant unless those confs exist); the switch handles
# remoteip via apache_remoteip_enable. Needs process_http2_directive (func/domain.sh)
# and WEBTPL (func/main.sh) in the caller's scope.
rebuild_ip_web_config() {
	local ip="$1"
	if [ -n "$WEB_SYSTEM" ]; then
		local web_conf="/etc/$WEB_SYSTEM/conf.d/$ip.conf"
		rm -f "$web_conf"

		if [ "$WEB_SYSTEM" = 'httpd' ] || [ "$WEB_SYSTEM" = 'apache2' ]; then
			if ! /usr/sbin/apachectl -v 2> /dev/null | grep -q "Apache/2.4"; then
				echo "NameVirtualHost $ip:$WEB_PORT" > "$web_conf"
			fi
			echo "Listen $ip:$WEB_PORT" >> "$web_conf"
			cat "$HESTIA/share/apache2/unassigned.conf" >> "$web_conf"
			sed -i "s/directIP/$ip/g" "$web_conf"
			sed -i "s/directPORT/$WEB_PORT/g" "$web_conf"

		elif [ "$WEB_SYSTEM" = 'nginx' ]; then
			cp -f "$HESTIA/share/nginx/unassigned.inc" "$web_conf"
			sed -i "s/directIP/$ip/g" "$web_conf"
			process_http2_directive "$web_conf"
		fi

		if [ "$WEB_SSL" = 'mod_ssl' ]; then
			if ! /usr/sbin/apachectl -v 2> /dev/null | grep -q "Apache/2.4"; then
				sed -i "1s/^/NameVirtualHost $ip:$WEB_SSL_PORT\n/" "$web_conf"
			fi
			sed -i "1s/^/Listen $ip:$WEB_SSL_PORT\n/" "$web_conf"
			sed -i "s/directSSLPORT/$WEB_SSL_PORT/g" "$web_conf"
		fi
	fi

	if [ -n "$PROXY_SYSTEM" ]; then
		sed -e "s/%ip%/$ip/g" \
			-e "s/%web_port%/$WEB_PORT/g" \
			-e "s/%proxy_port%/$PROXY_PORT/g" \
			-e "s/%proxy_ssl_port%/$PROXY_SSL_PORT/g" \
			"$WEBTPL/$PROXY_SYSTEM/proxy_ip.tpl" > "/etc/$PROXY_SYSTEM/conf.d/$ip.conf"

		process_http2_directive "/etc/$PROXY_SYSTEM/conf.d/$ip.conf"
	fi
}

# ════════════════════════════════════════════════════════════════════════════
# Live model switch core (#120) - one implementation behind the four thin
# commands (h-add-sys-nginx/-apache2, h-delete-sys-nginx/-apache2). Order:
# lock -> snapshot -> (apache setup) -> flip keyset -> rebuild -> validate ->
# restart -> clean, wrapped in a rollback trap + crash sentinel.
# ════════════════════════════════════════════════════════════════════════════

WEB_MODEL_SNAP_DIR="/var/lib/hestia/web-model-switch"

# Derive the configured model from the live keyset (NOT dpkg): the switch reads
# WEB_SYSTEM/PROXY_SYSTEM, so a stopped-but-installed server never masks the model.
web_current_model() {
	if [ "$WEB_SYSTEM" = "nginx" ]; then
		echo "nginx"
	elif [ "$WEB_SYSTEM" = "apache2" ] && [ "$PROXY_SYSTEM" = "nginx" ]; then
		echo "both"
	elif [ "$WEB_SYSTEM" = "apache2" ]; then
		echo "apache"
	else
		echo "unknown"
	fi
}

web_model_uses_apache() { case "$1" in both | apache) return 0 ;; *) return 1 ;; esac; }
web_model_uses_nginx() { case "$1" in both | nginx) return 0 ;; *) return 1 ;; esac; }

web_model_label() {
	case "$1" in
		nginx) echo "nginx-only" ;;
		both) echo "both - nginx front, apache2 backend" ;;
		apache) echo "apache-only" ;;
		*) echo "$1" ;;
	esac
}

# The 8 keys the model owns; flip = change each emitted key, clear the rest.
WEB_MODEL_KEYS="WEB_SYSTEM WEB_RGROUPS WEB_PORT WEB_SSL_PORT WEB_SSL PROXY_SYSTEM PROXY_PORT PROXY_SSL_PORT"

web_model_flip_keyset() {
	local target="$1" kv key emitted=""
	while IFS= read -r kv; do
		key="${kv%%=*}"
		change_sys_value "$key" "${kv#*=}"
		emitted="$emitted $key"
	done < <(web_model_keyset "$target")
	local k
	for k in $WEB_MODEL_KEYS; do
		case " $emitted " in *" $k "*) ;; *) clear_sys_value "$k" ;; esac
	done
}

# ── crash sentinel ──────────────────────────────────────────────────────────
web_model_sentinel() { echo "$WEB_MODEL_SNAP_DIR/IN_PROGRESS"; }

web_model_sentinel_check() {
	local s op; s="$(web_model_sentinel)"
	[ -f "$s" ] || return 0
	op=$(sed -n 's/^op=//p' "$s")
	echo "Error: a previous web-model switch did not finish:" >&2
	sed 's/^/       /' "$s" >&2
	echo "       Recover from its snapshot with:  ${op:-h-<that-command>} --recover" >&2
	return 1
}

# ── snapshot / rollback ─────────────────────────────────────────────────────
web_model_snapshot() {
	local snap="$1" u
	mkdir -p "$snap"
	cp -a "$HESTIA/conf/hestia.conf" "$snap/hestia.conf"
	local -a paths=()
	[ -d /etc/nginx/conf.d ] && paths+=("etc/nginx/conf.d")
	[ -d /etc/apache2/conf.d ] && paths+=("etc/apache2/conf.d")
	# configure_apache2 rewrites these from share/, and a2enmod/a2dismod flips the
	# mods-enabled symlinks - snapshot them so a rollback restores apache faithfully,
	# not just its per-domain vhosts.
	[ -f /etc/apache2/apache2.conf ] && paths+=("etc/apache2/apache2.conf")
	[ -d /etc/apache2/mods-available ] && paths+=("etc/apache2/mods-available")
	[ -d /etc/apache2/mods-enabled ] && paths+=("etc/apache2/mods-enabled")
	[ -f /etc/apache2/ports.conf ] && paths+=("etc/apache2/ports.conf")
	[ -d /etc/apache2/suexec ] && paths+=("etc/apache2/suexec")
	[ -f /etc/logrotate.d/apache2 ] && paths+=("etc/logrotate.d/apache2")
	[ -f /etc/logrotate.d/nginx ] && paths+=("etc/logrotate.d/nginx")
	while IFS= read -r u; do
		[ -n "$u" ] || continue
		[ -d "$HOMEDIR/$u/conf/web" ] && paths+=("home/$u/conf/web")
		[ -d "$HOMEDIR/$u/conf/mail" ] && paths+=("home/$u/conf/mail")
	done < <(web_users)
	# The snapshot IS the rollback - a swallowed tar failure leaves an empty archive that
	# only surfaces when a rollback is needed. Hard-fail, then verify the archive is real.
	if ! tar czf "$snap/state.tar.gz" -C / "${paths[@]}" 2> /dev/null; then
		echo "Error: snapshot tar failed (disk full? permissions? a path vanished mid-run?)." >&2
		return 1
	fi
	if [ ! -s "$snap/state.tar.gz" ] || ! tar tzf "$snap/state.tar.gz" > /dev/null 2>&1; then
		echo "Error: snapshot archive is empty or unreadable; refusing to switch." >&2
		return 1
	fi
	printf '%s\n' "${paths[@]}" > "$snap/paths.list"
}

web_model_rollback() {
	local snap="$1" restored pfx u dir ip
	[ -d "$snap" ] || return 1
	cp -a "$snap/hestia.conf" "$HESTIA/conf/hestia.conf"
	tar xzf "$snap/state.tar.gz" -C / 2> /dev/null || true
	source_conf "$HESTIA/conf/hestia.conf"
	restored="$(web_current_model)"
	# tar extract restores the old files but does NOT delete the target-model files a
	# failed apply already created (e.g. apache2.* after rolling back to nginx-only) -
	# without this the rollback itself leaves the mixed tree the inventory guards against.
	local keep=" $WEB_SYSTEM $PROXY_SYSTEM "
	for pfx in nginx apache2; do
		case "$keep" in *" $pfx "*) continue ;; esac
		while IFS=$'\t' read -r u dir; do
			rm -f "$dir/$pfx.conf" "$dir/$pfx.ssl.conf"
		done < <(web_domain_dirs)
		rm -f "/etc/$pfx/conf.d/domains/"*.conf 2> /dev/null
		while IFS= read -r ip; do
			[ -n "$ip" ] || continue
			rm -f "/etc/$pfx/conf.d/$ip.conf"
		done < <(web_sys_ips)
	done
	# Bring the restored model's servers up+enabled (a bare reload of a stopped unit is
	# not enough); stop+disable the one it does NOT use so no stray server survives a
	# reboot or grabs :80 at the next package update.
	if web_model_uses_apache "$restored"; then
		systemctl enable --now apache2 > /dev/null 2>&1
		systemctl restart apache2 > /dev/null 2>&1
	else
		systemctl disable --now apache2 > /dev/null 2>&1 || true
	fi
	if web_model_uses_nginx "$restored"; then
		systemctl enable --now nginx > /dev/null 2>&1
		systemctl restart nginx > /dev/null 2>&1
	else
		systemctl disable --now nginx > /dev/null 2>&1 || true
	fi
}

# List helpers
web_sys_ips() { "$BIN/h-list-sys-ips" plain 2> /dev/null | cut -f1; }
web_users() { "$BIN/h-list-users" list 2> /dev/null; }
# Each sys IP followed by its NAT/public IP (field 9), matching the installer's remoteip
# trusted-proxy set of IP + PUB_IP so a switched box is byte-identical to a fresh one.
web_sys_proxy_ips() {
	"$BIN/h-list-sys-ips" plain 2> /dev/null | awk -F'\t' '{print $1; if ($9 != "" && $9 != $1) print $9}'
}
# Emit "USER<TAB>DOMAINDIR" for every web-domain conf dir. Consume with
# `while IFS=$'\t' read -r u dir`. The quoted-prefix glob is space-safe and a no-match
# glob is skipped, so odd characters in a home path do not break iteration.
web_domain_dirs() {
	local u dir
	while IFS= read -r u; do
		[ -n "$u" ] || continue
		for dir in "$HOMEDIR/$u/conf/web/"*/; do
			[ -d "$dir" ] || continue
			printf '%s\t%s\n' "$u" "${dir%/}"
		done
	done < <(web_users)
}

# web_model_run CURRENT TARGET MODE OPLABEL PURGE
# The shared apply/preview path. MODE=yes applies; anything else previews.
web_model_run() {
	local current="$1" target="$2" mode="$3" oplabel="$4" purge="$5"

	if [ "$current" = "$target" ]; then
		echo "Already $(web_model_label "$current"); nothing to do."
		return 0
	fi

	echo "Web model: $(web_model_label "$current")  ->  $(web_model_label "$target")"
	web_model_uses_apache "$target" && ! web_model_uses_apache "$current" \
		&& echo "  - apache2 will be installed/configured"
	web_model_uses_apache "$current" && ! web_model_uses_apache "$target" \
		&& { [ "$purge" = "yes" ] && echo "  - apache2 will be PURGED (/etc/apache2 incl. custom includes + fm-listen.conf)" || echo "  - apache2 will be stopped+disabled (package kept)"; }
	web_model_uses_apache "$current" && web_model_uses_apache "$target" \
		&& echo "  - apache2.conf + module config are rewritten from share/ (existing customizations are snapshotted, not merged)"
	web_model_uses_nginx "$current" && ! web_model_uses_nginx "$target" \
		&& echo "  - nginx will be stopped+disabled"
	[ "$target" = "both" ] && echo "  - mod_remoteip enabled (apache trusts nginx X-Real-IP)"
	web_model_uses_apache "$current" && [ "$target" != "both" ] \
		&& echo "  - mod_remoteip disabled"
	echo "  - every web + webmail vhost is regenerated; brief downtime; domain ops are frozen during the switch"

	if [ "$mode" != "yes" ]; then
		echo "Preview only. Re-run with 'yes' to apply."
		return 0
	fi

	# ── apply (explicit error handling; no ERR trap - it does not abort without set -e) ─
	web_lock_acquire 300 || return 1

	local snap OLD_WEB OLD_PROXY
	snap="$WEB_MODEL_SNAP_DIR/$(date +%Y%m%d-%H%M%S)-$$"
	OLD_WEB="$WEB_SYSTEM"
	OLD_PROXY="$PROXY_SYSTEM"

	_wm_fail() {
		echo "ERROR: $1 - rolling back to $(web_model_label "$current")..." >&2
		web_model_rollback "$snap"
		rm -f "$(web_model_sentinel)"
		web_lock_release
		echo "       Rolled back (site kept serving the old config). Snapshot: $snap" >&2
		echo "       Manual restore if needed: cp -a $snap/hestia.conf $HESTIA/conf/hestia.conf; tar xzf $snap/state.tar.gz -C /; systemctl restart nginx apache2" >&2
	}

	echo "[ * ] Snapshotting current state..."
	web_model_snapshot "$snap" || { web_lock_release; return 1; }
	mkdir -p "$(dirname "$(web_model_sentinel)")"
	printf 'op=%s\nfrom=%s\nto=%s\nsnapshot=%s\nstarted=%s\n' \
		"$oplabel" "$current" "$target" "$snap" "$(date '+%F %T')" > "$(web_model_sentinel)"

	if web_model_uses_apache "$target"; then
		echo "[ * ] Setting up apache2..."
		configure_apache2
		command -v apache2ctl > /dev/null 2>&1 || { _wm_fail "apache2 install failed"; return 1; }
	fi

	# rotate-before-switch (plan step 4): seal the current domain logs so the target
	# $WEB_SYSTEM log dir starts clean with the old logs kept beside as history. Only bites
	# when the dir moves (nginx-only <-> apache); harmless otherwise.
	if [ -f "/etc/logrotate.d/$OLD_WEB" ]; then
		logrotate -f "/etc/logrotate.d/$OLD_WEB" > /dev/null 2>&1 || true
	fi

	echo "[ * ] Flipping web model keyset..."
	web_model_flip_keyset "$target"
	source_conf "$HESTIA/conf/hestia.conf" # reload globals to the target model

	if [ "$target" = "both" ]; then
		local ips; ips=$(web_sys_proxy_ips | tr '\n' ' ')
		# shellcheck disable=SC2086
		apache_remoteip_enable $ips
	elif [ -d /etc/apache2/mods-available ]; then
		# any non-both target: remoteip must be OFF - with no nginx front to set the
		# trusted X-Real-IP, leaving it on is a client-IP spoofing surface (Decision #4).
		apache_remoteip_disable
	fi

	echo "[ * ] Rebuilding per-IP + per-domain + webmail configs for $target..."
	local ip u
	while IFS= read -r ip; do
		[ -n "$ip" ] || continue
		rebuild_ip_web_config "$ip"
	done < <(web_sys_ips)
	# Rebuild exit codes matter: a failed web rebuild would only be caught downstream by
	# the inventory assert, and a failed mail/webmail rebuild has NO assert at all - so
	# check both here. Mail rebuild only when a mail stack is configured (web-only boxes).
	while IFS= read -r u; do
		[ -n "$u" ] || continue
		"$BIN/h-rebuild-web-domains" "$u" no > /dev/null 2>&1 \
			|| { _wm_fail "web rebuild failed for $u"; return 1; }
		if [ -n "$MAIL_SYSTEM" ]; then
			"$BIN/h-rebuild-mail-domains" "$u" > /dev/null 2>&1 \
				|| { _wm_fail "mail/webmail rebuild failed for $u"; return 1; }
		fi
	done < <(web_users)
	if [ -s /etc/hestia/conf/.filemanager.key ]; then
		while IFS= read -r u; do
			[ -n "$u" ] || continue
			if grep -q "^FILE_MANAGER='yes'" "$CONF_DIR/users/$u/user.conf" 2> /dev/null; then
				"$BIN/h-add-user-filemanager" "$u" > /dev/null 2>&1 || true
			fi
		done < <(web_users)
	fi

	echo "[ * ] Validating..."
	if web_model_uses_nginx "$target"; then
		nginx -t > /dev/null 2>&1 || { _wm_fail "nginx configtest failed"; return 1; }
	fi
	if web_model_uses_apache "$target"; then
		apache2ctl configtest > /dev/null 2>&1 || { _wm_fail "apache2 configtest failed"; return 1; }
	fi
	# Old-model files are still present here (cleanup runs only after a proven restart,
	# below) so the assert tolerates the departing OLD_WEB/OLD_PROXY prefixes and flags
	# only a genuinely foreign one - the strict half (target vhost must exist) still bites.
	web_model_inventory_assert "$target" "$OLD_WEB" "$OLD_PROXY" || { _wm_fail "inventory assertion failed (mixed tree)"; return 1; }

	echo "[ * ] Restarting web services..."
	# Stop the DEPARTING server FIRST so it frees any port the target server reclaims
	# (both -> apache-only: apache takes :80 back from nginx - nginx must stop first).
	if ! web_model_uses_apache "$target"; then
		if [ "$purge" = "yes" ]; then
			systemctl stop apache2 > /dev/null 2>&1 || true
			_web_apt_purge apache2 apache2-suexec-custom libapache2-mod-fcgid > /dev/null 2>&1 || true
			rm -f /etc/logrotate.d/apache2
		else
			systemctl disable --now apache2 > /dev/null 2>&1 || true
		fi
	fi
	if ! web_model_uses_nginx "$target"; then
		systemctl disable --now nginx > /dev/null 2>&1 || true
	fi

	# Now enable + (re)start the servers the target uses; ports are free. An arriving
	# server may have been disabled by a prior switch, so enable it explicitly.
	if web_model_uses_apache "$target"; then systemctl enable apache2 > /dev/null 2>&1 || true; fi
	if web_model_uses_nginx "$target"; then systemctl enable nginx > /dev/null 2>&1 || true; fi
	"$BIN/h-restart-web" > /dev/null 2>&1
	"$BIN/h-restart-proxy" > /dev/null 2>&1
	"$BIN/h-restart-web-backend" > /dev/null 2>&1

	# Clean only now - after the target model is proven and serving. Never delete the
	# old artifacts before the new ones work (a validate/restart failure rolls back onto
	# the still-present old tree).
	echo "[ * ] Cleaning old-model artifacts..."
	web_model_cleanup "$OLD_WEB" "$OLD_PROXY" "$target"

	rm -f "$(web_model_sentinel)"
	web_lock_release
	echo "[ ok ] Web model is now $(web_model_label "$target"). Snapshot kept at: $snap"
	return 0
}
# Assert every domain carries only the target model's per-domain files (catches a
# mixed tree that syntax tests pass).
web_model_inventory_assert() {
	local target="$1" old_web="$2" old_proxy="$3" u d dir pfx bad=""
	local keep=" $WEB_SYSTEM $PROXY_SYSTEM "     # prefixes the target legitimately uses
	local tolerate=" $old_web $old_proxy "       # departing prefixes, cleaned right after
	while IFS=$'\t' read -r u dir; do
		d=$(basename "$dir")
		# strict: the target web system's main vhost MUST exist (catches a broken rebuild)
		[ -f "$dir/$WEB_SYSTEM.conf" ] || bad="$bad $u/$d:missing-$WEB_SYSTEM.conf"
		# any .conf/.ssl.conf of a prefix that is neither kept nor the departing one =
		# a genuine mixed tree from an unexpected source (the departing files are removed
		# by the cleanup step immediately after this passes)
		for pfx in nginx apache2; do
			case "$keep" in *" $pfx "*) continue ;; esac
			case "$tolerate" in *" $pfx "*) continue ;; esac
			{ [ -f "$dir/$pfx.conf" ] || [ -f "$dir/$pfx.ssl.conf" ]; } && bad="$bad $u/$d:foreign-$pfx"
		done
	done < <(web_domain_dirs)
	[ -z "$bad" ] && return 0
	echo "  mixed-tree files:$bad" >&2
	return 1
}

# Remove the departing model's per-domain + per-IP artifacts (only after success).
web_model_cleanup() {
	local old_web="$1" old_proxy="$2" target="$3" u dir ip pfx
	# which prefixes does the target legitimately keep?
	local keep=" $WEB_SYSTEM $PROXY_SYSTEM "
	for pfx in "$old_web" "$old_proxy"; do
		[ -n "$pfx" ] || continue
		case "$keep" in *" $pfx "*) continue ;; esac
		# departing prefix: drop its per-domain files + symlinks + per-IP configs
		while IFS=$'\t' read -r u dir; do
			rm -f "$dir/$pfx.conf" "$dir/$pfx.ssl.conf"
		done < <(web_domain_dirs)
		rm -f "/etc/$pfx/conf.d/domains/"*.conf 2> /dev/null
		while IFS= read -r ip; do
			[ -n "$ip" ] || continue
			rm -f "/etc/$pfx/conf.d/$ip.conf"
		done < <(web_sys_ips)
	done
}

# ── recovery (from a crash sentinel) ────────────────────────────────────────
web_model_recover() {
	local s; s="$(web_model_sentinel)"
	if [ ! -f "$s" ]; then
		echo "No interrupted web-model switch to recover."
		return 0
	fi
	local snap; snap=$(sed -n 's/^snapshot=//p' "$s")
	echo "Recovering from interrupted switch:"; sed 's/^/  /' "$s"
	[ -d "$snap" ] || { echo "Error: snapshot dir $snap missing; recover by hand." >&2; return 1; }
	web_lock_acquire 300 || return 1
	web_model_rollback "$snap"
	rm -f "$s"
	web_lock_release
	echo "[ ok ] Restored to the pre-switch model from $snap."
}

# ── component-command dispatch + per-command pre-checks ─────────────────────
# web_component_op ACTION COMPONENT MODE PURGE FORCE
#   ACTION=add|delete  COMPONENT=nginx|apache2
web_component_op() {
	local action="$1" comp="$2" mode="$3" purge="$4" force="$5"
	local current; current=$(web_current_model)
	[ "$current" = "unknown" ] && { echo "Refused: no web stack is configured (empty WEB_SYSTEM); this is not the axis a web-model command changes." >&2; return 1; }

	local has_nginx=no has_apache=no
	web_model_uses_nginx "$current" && has_nginx=yes
	web_model_uses_apache "$current" && has_apache=yes
	case "$action:$comp" in
		add:nginx) has_nginx=yes ;;
		add:apache2) has_apache=yes ;;
		delete:nginx) has_nginx=no ;;
		delete:apache2) has_apache=no ;;
	esac

	if [ "$has_nginx" = no ] && [ "$has_apache" = no ]; then
		echo "Refused: that would remove the last web server. A host must serve web with nginx and/or apache2 (not --force-able)." >&2
		return 1
	fi

	local target
	if [ "$has_nginx" = yes ] && [ "$has_apache" = yes ]; then
		target="both"
	elif [ "$has_nginx" = yes ]; then
		target="nginx"
	else
		target="apache"
	fi

	# Pre-checks run in BOTH modes - their findings (.htaccess, custom includes, affected
	# domains) are the point of a preview. Only apply aborts on them; preview shows them
	# and forces force=no so it never logs a phantom override.
	if [ "$current" != "$target" ]; then
		if [ "$mode" = "yes" ]; then
			"web_precheck_${action}_${comp}" "$current" "$target" "$force" || return 1
		else
			"web_precheck_${action}_${comp}" "$current" "$target" "no" || true
		fi
	fi

	web_model_run "$current" "$target" "$mode" "h-$action-sys-$comp" "$purge"
}

# helper: list every customer .htaccess under the web roots. NO -maxdepth: the ones that
# matter most (wp-admin/, uploads/, any subdir rule) live deep, and a check that only sees
# the docroot .htaccess falsely reassures - worse than no check.
_web_htaccess_files() {
	local u
	while IFS= read -r u; do
		[ -n "$u" ] || continue
		find "$HOMEDIR/$u/web" -name .htaccess 2> /dev/null
	done < <(web_users)
}

# add-apache2 (nginx-only -> both): ports must be free. Hard blocker (not force-able).
web_precheck_add_apache2() {
	local p occupied=""
	for p in 8080 8443; do
		ss -H -tln 2> /dev/null | awk '{print $4}' | grep -qE "[:.]$p\$" && occupied="$occupied $p"
	done
	if [ -n "$occupied" ]; then
		echo "Refused: apache backend port(s) already in use:$occupied (free them first)." >&2
		return 1
	fi
	return 0
}

# add-nginx (apache-only -> both): nginx serves static assets directly, so .htaccess
# directives on assets go inert. Warn (routing change, not a loss); never blocks.
web_precheck_add_nginx() {
	local f hits=""
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		grep -qiE 'Header|ExpiresBy|deny from|Rewrite' "$f" 2> /dev/null && hits="$hits ${f#"$HOMEDIR/"}"
	done < <(_web_htaccess_files)
	if [ -n "$hits" ]; then
		echo "Note: in 'both', nginx serves static assets directly - .htaccess asset rules go inert in:" >&2
		local h; for h in $hits; do echo "        $h" >&2; done
		echo "      (routing change, not a capability loss)" >&2
	fi
	return 0
}

# delete-apache2 (both -> nginx-only): highest risk. Refuse on any apache-only feature
# unless --force (which still prints + logs the overridden findings).
web_precheck_delete_apache2() {
	local force="$3" f u d dir findings=""
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		grep -qiE 'RewriteRule|php_value|php_flag|AuthType|Require |Options |ErrorDocument|Header ' "$f" 2> /dev/null \
			&& findings="$findings htaccess:${f#"$HOMEDIR/"}"
	done < <(_web_htaccess_files)
	while IFS=$'\t' read -r u dir; do
		d=$(basename "$dir")
		ls "$dir"/apache2.conf_* > /dev/null 2>&1 && findings="$findings apache-include:$u/$d"
	done < <(web_domain_dirs)
	if [ -n "$findings" ]; then
		echo "Removing apache2 would drop apache-only config for:" >&2
		local x; for x in $findings; do echo "        $x" >&2; done
		if [ "$force" = "yes" ]; then
			echo "  --force: proceeding anyway (recorded in the action log)." >&2
			"$BIN/h-log-action" "${ROOT_USER:-admin}" "Warning" "Web" "h-delete-sys-apache2 --force overrode:$findings" > /dev/null 2>&1 || true
			return 0
		fi
		echo "  Refused. Re-run with --force to override (its findings will be logged)." >&2
		return 1
	fi
	return 0
}

# delete-nginx (both -> apache-only): custom nginx includes + fastcgi-cache go away.
web_precheck_delete_nginx() {
	local force="$3" u d dir findings=""
	while IFS=$'\t' read -r u dir; do
		d=$(basename "$dir")
		ls "$dir"/nginx.conf_* > /dev/null 2>&1 && findings="$findings nginx-include:$u/$d"
		grep -q "^FASTCGI_CACHE='yes'" "$CONF_DIR/users/$u/web.conf" 2> /dev/null \
			&& findings="$findings fastcgi-cache(inert)"
	done < <(web_domain_dirs)
	echo "Note: removing nginx also disables mod_remoteip (apache serves :80 directly)." >&2
	if [ -n "$findings" ]; then
		echo "Removing nginx would drop nginx-only config for:" >&2
		local x; for x in $findings; do echo "        $x" >&2; done
		if [ "$force" = "yes" ]; then
			echo "  --force: proceeding anyway (recorded in the action log)." >&2
			"$BIN/h-log-action" "${ROOT_USER:-admin}" "Warning" "Web" "h-delete-sys-nginx --force overrode:$findings" > /dev/null 2>&1 || true
			return 0
		fi
		echo "  Refused. Re-run with --force to override." >&2
		return 1
	fi
	return 0
}

# web_component_main ACTION COMPONENT "$@"  - the body every thin command runs.
web_component_main() {
	local action="$1" comp="$2"; shift 2
	local mode="" purge="no" force="no" recover="no" a
	for a in "$@"; do
		case "$a" in
			--purge) purge="yes" ;;
			--force) force="yes" ;;
			--recover) recover="yes" ;;
			yes) mode="yes" ;;
			# reject unknown args: a typo'd --forse / --yes must not silently become a
			# preview someone reads as an apply (this is a destructive command)
			*) echo "Error: unknown argument '$a'. Use: [yes] [--force] [--purge] [--recover]." >&2; return 1 ;;
		esac
	done
	check_hestia_demo_mode
	if [ "$recover" = "yes" ]; then
		web_model_recover
		return $?
	fi
	web_model_sentinel_check || return 1
	web_component_op "$action" "$comp" "$mode" "$purge" "$force"
}
