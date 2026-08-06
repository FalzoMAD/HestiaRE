#!/bin/bash

#===========================================================================#
#                                                                           #
# Hestia Control Panel - fail2ban Function Library                          #
#                                                                           #
#===========================================================================#

# One implementation of "a configured fail2ban", shared by the installer and the addon commands. fail2ban
# is a CLIENT of the hestia firewall: action.d/hestia.conf maps its actions onto h-*-firewall-*, so bans
# land in banlist.conf + the live ruleset and survive a rebuild. Idempotent throughout.

F2B_DIR="/etc/fail2ban"
F2B_OURS="$F2B_DIR/jail.d/hestia.local"
# Own file, not a block inside hestia.local: a delimited block is unsafe to rewrite around admin edits (a
# broken sed range deletes to EOF). Sorts after hestia.local, so its [DEFAULT] wins.
F2B_WHITELIST="$F2B_DIR/jail.d/hestia-zz-whitelist.local"

# The L7 jails that read the per-domain web access log: gated on the web system, logpath repointed at the
# configured web system, and told about each domain's log on add/del. One list so all of them are handled
# uniformly (a new signature jail is added here and nowhere else).
F2B_WEB_JAILS="web-botsearch web-badactor web-exploit web-authprobe"

# Our jails live in jail.d/hestia.local (read last, wins); jail.local is left to the admin. Nothing needs
# preserving as addon state - it all re-renders from share/.
fail2ban_install_config() {
	local stage
	mkdir -p "$F2B_DIR/filter.d" "$F2B_DIR/action.d" "$F2B_DIR/jail.d"
	# Copy the WHOLE tree (a file list once omitted action.d/hestia.conf and broke every jail). Via a staging
	# dir so share/'s jail.local never reaches /etc: it is read before jail.d/*.local, so a stray copy would
	# resurrect a jail block an admin deleted. Never overwrite an existing hestia.local.
	stage="$(mktemp -d)"
	cp -rf "$HESTIA/share/fail2ban/." "$stage/"
	[ -f "$F2B_OURS" ] || cp -f "$stage/jail.local" "$F2B_OURS"
	rm -f "$stage/jail.local"
	cp -rf "$stage/." "$F2B_DIR/"
	rm -rf "$stage"
	chmod 644 "$F2B_OURS" 2> /dev/null
}

# Disable the distro [sshd] jail (its banaction writes a ruleset we do not manage) from our own config,
# not by deleting jail.d/defaults-debian.conf - a dpkg conffile a package update would restore.
fail2ban_disable_distro_jails() {
	grep -q '^\[sshd\]' "$F2B_OURS" 2> /dev/null && return 0
	{
		echo ""
		echo "# The distro's own sshd jail, disabled here rather than by deleting"
		echo "# jail.d/defaults-debian.conf: that is a dpkg conffile, so removing it is undone by the next"
		echo "# package update. Its banaction writes to a ruleset HestiaRE does not manage."
		echo "[sshd]"
		echo "enabled = false"
	} >> "$F2B_OURS"
}

# install.conf writes "true", the installer's locals write "yes" - accept both (one spelling once silently
# disabled the proftpd jail on boxes that had proftpd).
fail2ban_flag_on() {
	case "${1:-}" in
		true | yes | 1) return 0 ;;
		*) return 1 ;;
	esac
}

# Disable jails whose service is absent: a jail on a missing logpath never fires, silently.
fail2ban_gate_jails() {
	local mail="${1:-no}" ftp="${2:-no}"
	[ -f "$F2B_OURS" ] || return 0
	if ! fail2ban_flag_on "$mail"; then
		fail2ban_set_enabled 'exim-iptables' 'false'
		fail2ban_set_enabled 'dovecot-iptables' 'false'
	fi
	fail2ban_flag_on "$ftp" || fail2ban_set_enabled 'proftpd-iptables' 'false'
}

# Per-domain web logs live under /var/log/<web system>/domains (nginx-in-front-of-apache uses the apache
# path too). Read WEB_SYSTEM from the FILE: the installer's own shell never saw the key it just wrote.
fail2ban_web_logdir() {
	local ws
	ws="$(sed -n "s/^WEB_SYSTEM='\([^']*\)'.*/\1/p" "$HESTIA/conf/hestia.conf" 2> /dev/null)"
	[ -n "$ws" ] || return 1
	echo "/var/log/$ws/domains"
}

fail2ban_gate_web_jail() {
	local dir jail
	[ -f "$F2B_OURS" ] || return 0
	# CrowdSec owns Layer-7 when present, so our web jails would double its http scenarios. Disable them in
	# any crowdsec-present model - they belong to the fail2ban-only model. Re-enabled below once the
	# marker is gone.
	if [ -f "$CONF_DIR/firewall/crowdsec.conf" ]; then
		for jail in $F2B_WEB_JAILS; do fail2ban_set_enabled "$jail" 'false'; done
		return 0
	fi
	if ! dir="$(fail2ban_web_logdir)"; then
		for jail in $F2B_WEB_JAILS; do fail2ban_set_enabled "$jail" 'false'; done
		return 0
	fi
	for jail in $F2B_WEB_JAILS; do
		# Enable (a prior crowdsec-present state may have disabled them); prune_empty_jails later turns off
		# any whose log glob is still empty (no domains yet), and watch_domain re-arms on the first domain.
		fail2ban_set_enabled "$jail" 'true'
		awk -v jail="[$jail]" -v path="$dir/*.log" '
			$0 == jail { inj = 1; print; next }
			/^\[/ { inj = 0 }
			inj && /^logpath[[:space:]]*=/ { print "logpath  = " path; next }
			{ print }
		' "$F2B_OURS" > "$F2B_OURS.tmp" && mv -f "$F2B_OURS.tmp" "$F2B_OURS"
	done
}

# fail2ban globs a logpath once at jail start, so a later domain goes unwatched - tell it on every add/del.
# Never fails its caller: a domain add must not break because fail2ban is unhappy.
fail2ban_watch_domain() {
	local verb="$1" domain="$2" dir jail
	[ -n "${FIREWALL_EXTENSION:-}" ] || return 0
	systemctl -q is-active fail2ban 2> /dev/null || return 0
	# CrowdSec owns L7 while present - our web jails are disabled then, so never arm them (rearm would flip
	# a deliberately-off jail back on).
	[ -f "$CONF_DIR/firewall/crowdsec.conf" ] && return 0
	dir="$(fail2ban_web_logdir)" || return 0
	for jail in $F2B_WEB_JAILS; do
		case "$verb" in
			add)
				# First domain re-arms a jail pruned at install (reload re-globs); later domains just
				# addlogpath the one new file.
				if fail2ban_jail_enabled "$jail"; then
					fail2ban-client set "$jail" addlogpath "$dir/$domain.log" tail > /dev/null 2>&1
				else
					fail2ban_rearm_jail "$jail"
				fi
				;;
			del) fail2ban-client set "$jail" dellogpath "$dir/$domain.log" > /dev/null 2>&1 ;;
		esac
	done
	return 0
}

# Flip one jail's `enabled` without disturbing the rest of its block.
fail2ban_set_enabled() {
	awk -v jail="[$1]" -v val="$2" '
		$0 == jail { inj = 1; print; next }
		/^\[/ { inj = 0 }
		inj && /^enabled[[:space:]]*=/ { print "enabled  = " val; next }
		{ print }
	' "$F2B_OURS" > "$F2B_OURS.tmp" && mv -f "$F2B_OURS.tmp" "$F2B_OURS"
}

# Is a jail currently enabled in our config?
fail2ban_jail_enabled() {
	[ "$(sed -n "/^\[$1\]/,/^\[/{/^enabled[[:space:]]*=/p}" "$F2B_OURS" 2> /dev/null | head -1 | tr -d ' ')" = 'enabled=true' ]
}

# fail2ban aborts startup on an enabled jail whose logpath matches zero files. On a fresh box proftpd
# (installs later) and web-botsearch (no domains yet) hit that and aborted the installer. Disable such jails
# last so the daemon always starts; h-add-sys-proftpd / fail2ban_watch_domain re-arm them once the log exists.
fail2ban_prune_empty_jails() {
	[ -f "$F2B_OURS" ] || return 0
	local j lp
	for j in $(fail2ban_enabled_jails); do
		lp="$(fail2ban_jail_logpath "$j")"
		[ -n "$lp" ] || continue
		compgen -G "$lp" > /dev/null 2>&1 || fail2ban_set_enabled "$j" 'false'
	done
}

# Re-enable a jail prune switched off, once its log exists; reload re-globs. No-op unless fail2ban is ours
# and running.
fail2ban_rearm_jail() {
	[ "${FIREWALL_EXTENSION:-}" = 'fail2ban' ] || return 0
	systemctl -q is-active fail2ban 2> /dev/null || return 0
	fail2ban_jail_enabled "$1" && return 0
	fail2ban_set_enabled "$1" 'true'
	systemctl reload-or-restart fail2ban > /dev/null 2>&1
}

# Debian logs auth to the journal; create /var/log/auth.log so the sshd/phpmyadmin filters have a file.
fail2ban_ensure_authlog() {
	[ -e /var/log/auth.log ] && return 0
	touch /var/log/auth.log
	chmod 640 /var/log/auth.log
	chown root:adm /var/log/auth.log 2> /dev/null
}

# Enable each webmail jail whose client is in WEBMAIL_SYSTEM (read from the FILE - installer-shell trap;
# both clients gated independently) and create the log it watches, caddy-owned (the webmail FPM pool).
fail2ban_gate_webmail_jails() {
	local wm
	[ -f "$F2B_OURS" ] || return 0
	wm="$(sed -n "s/^WEBMAIL_SYSTEM='\([^']*\)'.*/\1/p" "$HESTIA/conf/hestia.conf" 2> /dev/null)"
	case ",$wm," in
		*,roundcube,*)
			fail2ban_set_enabled 'roundcube-auth' 'true'
			fail2ban_ensure_webmail_log /var/log/roundcube/userlogins.log
			;;
		*) fail2ban_set_enabled 'roundcube-auth' 'false' ;;
	esac
	case ",$wm," in
		*,snappymail,*)
			fail2ban_set_enabled 'snappymail-auth' 'true'
			fail2ban_ensure_webmail_log /var/log/snappymail/fail2ban/auth.txt
			;;
		*) fail2ban_set_enabled 'snappymail-auth' 'false' ;;
	esac
}

# Re-gate the webmail jails after a client is added/removed at runtime (WEBMAIL_SYSTEM already updated).
# No-op unless fail2ban is ours and running, so callers invoke it unconditionally.
fail2ban_refresh_webmail() {
	[ "${FIREWALL_EXTENSION:-}" = 'fail2ban' ] || return 0
	systemctl -q is-active fail2ban 2> /dev/null || return 0
	fail2ban_gate_webmail_jails
	systemctl reload-or-restart fail2ban > /dev/null 2>&1
}

# Create a webmail auth log (caddy-owned - caddy is the pool that writes it) so its jail has a file to watch.
fail2ban_ensure_webmail_log() {
	local f="$1"
	[ -e "$f" ] && return 0
	mkdir -p "$(dirname "$f")"
	touch "$f"
	chown -R caddy:caddy "$(dirname "$f")" 2> /dev/null
	chmod 640 "$f" 2> /dev/null
}

# The jails our config enables, by name - the source of truth a smoke guard compares against reality.
fail2ban_enabled_jails() {
	[ -f "$F2B_OURS" ] || return 0
	awk '/^\[/ { j = substr($0, 2, length($0) - 2) }
	     /^enabled[[:space:]]*=[[:space:]]*true/ { if (j != "") print j }' "$F2B_OURS"
}

# The logpath our config gives a jail, before fail2ban expands any glob in it.
fail2ban_jail_logpath() {
	awk -v jail="[$1]" '
		$0 == jail { inj = 1; next }
		/^\[/ { inj = 0 }
		inj && /^logpath[[:space:]]*=/ { sub(/^logpath[[:space:]]*=[[:space:]]*/, ""); print; exit }
	' "$F2B_OURS" 2> /dev/null
}

# Mirror the whitelist into ignoreip so a whitelisted address is never even counted. Own file, whole rewrite.
fail2ban_sync_ignoreip() {
	local excludes="$CONF_DIR/firewall/excludes.conf" ips='' rc=0
	[ -d "$F2B_DIR/jail.d" ] || return 0
	# shellcheck source=/usr/local/hestia/func/firewall.sh
	declare -F fw_is_addr > /dev/null 2>&1 || source "$HESTIA/func/firewall.sh"
	# An absent or entry-less whitelist is the normal empty case (grep rc 0/1); a real read failure (rc>=2)
	# must still surface, not be swallowed like a blanket `|| true`, which once let a genuine error vanish.
	if [ -f "$excludes" ]; then
		ips="$(grep -oE "$FW_ADDR_RE|^[0-9A-Fa-f:]+(/[0-9]{1,3})?$" "$excludes")" || rc=$?
		[ "$rc" -le 1 ] || check_result "$E_PARSING" "fail2ban_sync_ignoreip: cannot read $excludes (grep rc=$rc)"
		ips="$(printf '%s' "$ips" | paste -sd' ' -)"
	fi
	# Written even when the whitelist is empty: loopback belongs in ignoreip regardless.
	{
		echo "# Generated by fail2ban_sync_ignoreip from firewall/excludes.conf - do not edit."
		echo "# Manage entries with h-add-firewall-exclude / h-delete-firewall-exclude."
		echo "[DEFAULT]"
		echo "ignoreip = 127.0.0.1/8 ::1 $ips"
	} > "$F2B_WHITELIST"
	chmod 644 "$F2B_WHITELIST" 2> /dev/null
}

fail2ban_apply() {
	local mail="${1:-no}" ftp="${2:-no}"
	fail2ban_install_config
	fail2ban_disable_distro_jails
	fail2ban_gate_jails "$mail" "$ftp"
	fail2ban_gate_web_jail
	fail2ban_gate_webmail_jails
	fail2ban_ensure_authlog
	fail2ban_sync_ignoreip
	fail2ban_prune_empty_jails
	systemctl -q enable fail2ban 2> /dev/null
	systemctl restart fail2ban 2> /dev/null
	# Non-overlap with CrowdSec: fail2ban now owns brute force, so CrowdSec must drop its SSH
	# scenarios. No-op at install time (crowdsec stage runs later); fires when fail2ban is added to a box
	# that already has crowdsec.
	if [ -f "$CONF_DIR/firewall/crowdsec.conf" ]; then
		# shellcheck source=/usr/local/hestia/func/crowdsec.sh
		declare -F crowdsec_gate_bruteforce > /dev/null 2>&1 || source "$HESTIA/func/crowdsec.sh"
		crowdsec_gate_bruteforce
	fi
}

# Tear down the live wiring (h-delete-sys-fail2ban): stop the daemon, then drop every chain it created.
# Chain names are captured before the loop, since h-delete-firewall-chain rewrites chains.conf as it goes.
# KEEP defaults to no here, so the banlist records go too - a human removing the addon wants the bans gone.
# The caller re-renders the ruleset afterwards. Our config files re-render from share/, so nothing is saved;
# the admin's own jail.local is never touched.
fail2ban_teardown() {
	local chains="$CONF_DIR/firewall/chains.conf" chain
	systemctl -q disable --now fail2ban 2> /dev/null
	if [ -f "$chains" ]; then
		for chain in $(sed -n "s/.*CHAIN='\([^']*\)'.*/\1/p" "$chains"); do
			"$BIN/h-delete-firewall-chain" "$chain" > /dev/null 2>&1
		done
	fi
	rm -f "$F2B_OURS" "$F2B_WHITELIST"
}
