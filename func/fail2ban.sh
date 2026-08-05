#!/bin/bash

#===========================================================================#
#                                                                           #
# Hestia Control Panel - fail2ban Function Library                          #
#                                                                           #
#===========================================================================#

# Shared by the installer and the addon commands, so one implementation decides what a configured
# fail2ban looks like. Mirrors func/crowdsec.sh. Idempotent throughout.
#
# fail2ban is a CLIENT of the hestia firewall: action.d/hestia.conf maps its actions onto h-*-firewall-*
# commands, so a ban lands in banlist.conf and in the live ruleset, and survives a rebuild. That is why we
# keep owning the ban action instead of using fail2ban's native nftables one, which would bypass the
# banlist, the panel and the replay.

F2B_DIR="/etc/fail2ban"
F2B_OURS="$F2B_DIR/jail.d/hestia.local"
# The whitelist gets its OWN file rather than a delimited block inside hestia.local. A generated block in a
# shared file has to be found again to be replaced, and every way of delimiting it ends badly when an admin
# edits around it: a sed range whose end address has been removed deletes to end of file. A whole file we
# own outright cannot take admin content with it. Sorts after hestia.local, so its [DEFAULT] wins.
F2B_WHITELIST="$F2B_DIR/jail.d/hestia-zz-whitelist.local"

# Our jails live in jail.d/hestia.local, NOT in jail.local. fail2ban reads jail.conf -> jail.d/*.conf ->
# jail.local -> jail.d/*.local, so ours is read last and wins, while /etc/fail2ban/jail.local is left for
# the admin and never written by us. It also means the addon has nothing to preserve as saved state:
# everything we install is re-renderable from share/.
fail2ban_install_config() {
	local stage
	mkdir -p "$F2B_DIR/filter.d" "$F2B_DIR/action.d" "$F2B_DIR/jail.d"
	# Copied as a whole tree, never as a list of files: leaving action.d out of such a list is what made
	# every jail using `action = hestia[...]` unstartable, and a list cannot notice a directory added later.
	#
	# It goes through a staging dir so that share/'s jail.local never lands in /etc at all. Copying it there
	# and moving it afterwards only works on the first run - on later runs the "do not clobber admin edits"
	# guard skips the move and the fresh copy just stays. That matters because jail.local is read BEFORE
	# jail.d/*.local: a jail block an admin deleted outright from hestia.local would come back from the
	# stray file, silently undoing the one edit our own comment promises to respect. Deleting
	# /etc/fail2ban/jail.local unconditionally would fix the stray but could also delete a file the admin
	# wrote; not creating it is the only option that does neither.
	stage="$(mktemp -d)"
	cp -rf "$HESTIA/share/fail2ban/." "$stage/"
	[ -f "$F2B_OURS" ] || cp -f "$stage/jail.local" "$F2B_OURS"
	rm -f "$stage/jail.local"
	cp -rf "$stage/." "$F2B_DIR/"
	rm -rf "$stage"
	chmod 644 "$F2B_OURS" 2> /dev/null
}

# The distro ships jail.d/defaults-debian.conf enabling its own [sshd] jail with its own banaction, which
# bans into a ruleset we do not manage - a second, uncoordinated firewall writer. Upstream deletes that
# file; we must not, because it is a dpkg conffile and a reinstall or package revision would silently
# bring it back. Disabling the jail from our own config wins on load order and survives both.
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

# install.conf writes its booleans as "true", while the installer's own locals read "yes". Accept both
# rather than depending on which caller passed which: comparing against a single spelling is what silently
# disabled the proftpd jail on every box that actually had proftpd.
fail2ban_flag_on() {
	case "${1:-}" in
		true | yes | 1) return 0 ;;
		*) return 1 ;;
	esac
}

# A jail whose logpath does not exist never matches anything and says so only in fail2ban's own log, so
# the jails are gated on the services actually present rather than shipped on and left to fail quietly.
fail2ban_gate_jails() {
	local mail="${1:-no}" ftp="${2:-no}"
	[ -f "$F2B_OURS" ] || return 0
	if ! fail2ban_flag_on "$mail"; then
		fail2ban_set_enabled 'exim-iptables' 'false'
		fail2ban_set_enabled 'dovecot-iptables' 'false'
	fi
	fail2ban_flag_on "$ftp" || fail2ban_set_enabled 'proftpd-iptables' 'false'
}

# The web jail follows the per-domain logs, and those live under /var/log/<web system>/domains regardless of
# which server writes them - in the nginx-in-front-of-apache model the vhost template hands nginx the apache
# path too. Read from the config FILE, not the variable: during the install run the key is already written
# but the installer's own shell has never seen it.
fail2ban_web_logdir() {
	local ws
	ws="$(sed -n "s/^WEB_SYSTEM='\([^']*\)'.*/\1/p" "$HESTIA/conf/hestia.conf" 2> /dev/null)"
	[ -n "$ws" ] || return 1
	echo "/var/log/$ws/domains"
}

fail2ban_gate_web_jail() {
	local dir
	[ -f "$F2B_OURS" ] || return 0
	if ! dir="$(fail2ban_web_logdir)"; then
		fail2ban_set_enabled 'web-botsearch' 'false'
		return 0
	fi
	awk -v jail='[web-botsearch]' -v path="$dir/*.log" '
		$0 == jail { inj = 1; print; next }
		/^\[/ { inj = 0 }
		inj && /^logpath[[:space:]]*=/ { print "logpath  = " path; next }
		{ print }
	' "$F2B_OURS" > "$F2B_OURS.tmp" && mv -f "$F2B_OURS.tmp" "$F2B_OURS"
}

# fail2ban expands a logpath glob once, when the jail starts, and never again - a domain added afterwards is
# simply not watched, silently, until the daemon next restarts. So every place that creates or removes a
# domain log has to say so. addlogpath/dellogpath touch only that jail's file list: no reload, no action
# churn, no effect on live bans. Never fails its caller; this must not be able to break a domain add.
fail2ban_watch_domain() {
	local verb="$1" domain="$2" dir
	[ -n "${FIREWALL_EXTENSION:-}" ] || return 0
	systemctl -q is-active fail2ban 2> /dev/null || return 0
	dir="$(fail2ban_web_logdir)" || return 0
	case "$verb" in
		add)
			# web-botsearch may have been pruned at install (no domains then). The first domain re-arms it -
			# reload re-globs and catches this log. Once enabled, later domains just addlogpath.
			if fail2ban_jail_enabled web-botsearch; then
				fail2ban-client set web-botsearch addlogpath "$dir/$domain.log" tail > /dev/null 2>&1
			else
				fail2ban_rearm_jail web-botsearch
			fi
			;;
		del) fail2ban-client set web-botsearch dellogpath "$dir/$domain.log" > /dev/null 2>&1 ;;
	esac
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

# fail2ban aborts startup on ANY enabled jail whose logpath matches zero files - a concrete missing path or
# an empty glob. On a fresh install that would abort the installer: proftpd installs in the addon stage
# AFTER fail2ban, so its log does not exist yet, and web-botsearch's per-domain glob matches nothing until
# the first web domain. Disable such jails as the last step before start so the daemon always comes up; the
# events that create the log re-arm them (h-add-sys-proftpd, fail2ban_watch_domain on a domain add). Runs
# after every specific gate so it only ever prunes what genuinely has nothing to watch.
fail2ban_prune_empty_jails() {
	[ -f "$F2B_OURS" ] || return 0
	local j lp
	for j in $(fail2ban_enabled_jails); do
		lp="$(fail2ban_jail_logpath "$j")"
		[ -n "$lp" ] || continue
		compgen -G "$lp" > /dev/null 2>&1 || fail2ban_set_enabled "$j" 'false'
	done
}

# Re-enable a jail that fail2ban_prune_empty_jails switched off, once its log exists. Called by the events
# that create the log. reload re-globs, so a freshly-created file is picked up without addlogpath. No-op
# unless fail2ban is our extension and running.
fail2ban_rearm_jail() {
	[ "${FIREWALL_EXTENSION:-}" = 'fail2ban' ] || return 0
	systemctl -q is-active fail2ban 2> /dev/null || return 0
	fail2ban_jail_enabled "$1" && return 0
	fail2ban_set_enabled "$1" 'true'
	systemctl reload-or-restart fail2ban > /dev/null 2>&1
}

# Debian moved auth logging to the journal, and a jail reading a file that is never created is a jail that
# silently never fires. Create it so the sshd and phpmyadmin filters have something to follow.
fail2ban_ensure_authlog() {
	[ -e /var/log/auth.log ] && return 0
	touch /var/log/auth.log
	chmod 640 /var/log/auth.log
	chown root:adm /var/log/auth.log 2> /dev/null
}

# Webmail auth jails, gated on the configured client(s). Read from the FILE, not the variable: during the
# install run the key is already written but the installer's own shell has never seen it. WEBMAIL_SYSTEM
# can name both (roundcube,snappymail), so each jail is gated independently. A jail whose logpath does not
# exist never fires and says so only in fail2ban's own log, so the log file is created here (owned by the
# webmail FPM pool, caddy, which is what writes it) rather than shipped on and left to fail quietly.
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

# Re-gate the webmail jails after a webmail client is added or removed at runtime. A no-op unless fail2ban
# is the active extension, so the webmail commands can call it unconditionally. WEBMAIL_SYSTEM must already
# be written before this runs (the add/delete-sys-* command updates it first).
fail2ban_refresh_webmail() {
	[ "${FIREWALL_EXTENSION:-}" = 'fail2ban' ] || return 0
	systemctl -q is-active fail2ban 2> /dev/null || return 0
	fail2ban_gate_webmail_jails
	systemctl reload-or-restart fail2ban > /dev/null 2>&1
}

# Touch a webmail auth log so its jail has a file to watch before the first failed login. caddy is the
# webmail FPM pool and the process that appends to it, so it must own it.
fail2ban_ensure_webmail_log() {
	local f="$1"
	[ -e "$f" ] && return 0
	mkdir -p "$(dirname "$f")"
	touch "$f"
	chown -R caddy:caddy "$(dirname "$f")" 2> /dev/null
	chmod 640 "$f" 2> /dev/null
}

# Every jail we enable, by name. The single source of truth for "what should be running", which is what
# lets a smoke guard compare intent against reality instead of hardcoding a list.
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

# Mirror the firewall whitelist into fail2ban's ignoreip, so a whitelisted address is not merely unbannable
# at the ruleset level but never counted in the first place - otherwise the jail keeps matching and logging
# an address it can never act on. Rewritten whole, never edited in place.
fail2ban_sync_ignoreip() {
	local excludes="$CONF_DIR/firewall/excludes.conf" ips
	[ -d "$F2B_DIR/jail.d" ] || return 0
	# Needed only here, so it is sourced here: this file is also read by h-add-web-domain, where pulling in
	# the renderer would be dead weight and could reset an in-flight batch.
	# shellcheck source=/usr/local/hestia/func/firewall.sh
	declare -F fw_is_addr > /dev/null 2>&1 || source "$HESTIA/func/firewall.sh"
	# `|| true`: a missing or entry-less excludes.conf makes grep exit non-zero, which under the installer's
	# `set -eo pipefail` aborted the whole run at this step on a fresh box (no whitelist yet). The empty
	# result is the correct outcome, not an error.
	ips="$(grep -oE "$FW_ADDR_RE|^[0-9A-Fa-f:]+(/[0-9]{1,3})?$" "$excludes" 2> /dev/null | paste -sd' ' - || true)"
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
}
