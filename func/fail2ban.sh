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

# Flip one jail's `enabled` without disturbing the rest of its block.
fail2ban_set_enabled() {
	awk -v jail="[$1]" -v val="$2" '
		$0 == jail { inj = 1; print; next }
		/^\[/ { inj = 0 }
		inj && /^enabled[[:space:]]*=/ { print "enabled  = " val; next }
		{ print }
	' "$F2B_OURS" > "$F2B_OURS.tmp" && mv -f "$F2B_OURS.tmp" "$F2B_OURS"
}

# Debian moved auth logging to the journal, and a jail reading a file that is never created is a jail that
# silently never fires. Create it so the sshd and phpmyadmin filters have something to follow.
fail2ban_ensure_authlog() {
	[ -e /var/log/auth.log ] && return 0
	touch /var/log/auth.log
	chmod 640 /var/log/auth.log
	chown root:adm /var/log/auth.log 2> /dev/null
}

# Every jail we enable, by name. The single source of truth for "what should be running", which is what
# lets a smoke guard compare intent against reality instead of hardcoding a list.
fail2ban_enabled_jails() {
	[ -f "$F2B_OURS" ] || return 0
	awk '/^\[/ { j = substr($0, 2, length($0) - 2) }
	     /^enabled[[:space:]]*=[[:space:]]*true/ { if (j != "") print j }' "$F2B_OURS"
}

fail2ban_apply() {
	local mail="${1:-no}" ftp="${2:-no}"
	fail2ban_install_config
	fail2ban_disable_distro_jails
	fail2ban_gate_jails "$mail" "$ftp"
	fail2ban_ensure_authlog
	systemctl -q enable fail2ban 2> /dev/null
	systemctl restart fail2ban 2> /dev/null
}
