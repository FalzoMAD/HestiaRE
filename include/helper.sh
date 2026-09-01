#!/bin/bash

#===========================================================================#
#                                                                           #
# HestiaRE - Installer Helper Library                                        #
#                                                                           #
# General home for cross-cutting install-time helpers, sourced by           #
# sbin/h-install-hestia and the other lifecycle commands:                    #
#   - hestia_apt    : apt wrapper (spinner + stdout->log, stderr->term+log) #
#   - load_os_profile : per-OS data for all supported targets               #
#   - seed_hestia_etc  : create /etc/hestia env + seed hestia.conf          #
#                                                                           #
# Requires $LOG to point at the install log for hestia_apt.                 #
#===========================================================================#

# ── apt wrapper with spinner (stdout -> log, stderr -> terminal + log) ──────
_hestia_spin_pid=""

_hestia_spin_start() {
	(
		s='/-\|'
		i=0
		while true; do
			printf '\r  %s ' "${s:$((i % 4)):1}" >&2
			sleep 0.15
			i=$((i + 1))
		done
	) &
	_hestia_spin_pid=$!
}

_hestia_spin_stop() {
	[ -n "$_hestia_spin_pid" ] || return 0
	kill "$_hestia_spin_pid" 2> /dev/null || true
	wait "$_hestia_spin_pid" 2> /dev/null || true
	printf '\r\033[K' >&2
	_hestia_spin_pid=""
}

# Usage: hestia_apt [apt-get args...]
hestia_apt() {
	_hestia_spin_start
	local _rc=0
	# Lock::Timeout: wait for a held dpkg/apt lock instead of failing fast. On a freshly booted box
	# unattended-upgrades/apt-daily commonly hold it for the first minutes, and a fast failure on an
	# optional component used to leave the component flagged on with the package absent (#480).
	DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout="${HESTIA_APT_LOCK_WAIT:-300}" "$@" \
		1>> "${LOG}" \
		2> >(tee -a "${LOG}" >&2) || _rc=$?
	_hestia_spin_stop
	return $_rc
}

# Install packages that are OPTIONAL for the install to succeed - components, tools, addons.
# A failure must not abort the installer, but it must not vanish either: #480 had two fleet VMs come
# up with COMPONENT_ADDON_CROWDSEC=true and no crowdsec package, because the apt lock was held and the
# call site's `|| true` swallowed it. apt's exit code alone is not enough (a partial install can still
# report success), so the packages are verified against dpkg afterwards and anything missing is
# collected for the closing summary.
# Usage: apt_install_optional <label> <pkg>...   [APT_EXTRA_OPTS='-o ...' for per-call apt options]
apt_install_optional() {
	local label="$1"
	shift
	[ $# -gt 0 ] || return 0

	# shellcheck disable=SC2086 # APT_EXTRA_OPTS is a deliberate multi-token option string
	hestia_apt -y ${APT_EXTRA_OPTS:-} install "$@" || true

	local pkg missing=''
	for pkg in "$@"; do
		dpkg-query -W -f='${db:Status-Status}' "$pkg" 2> /dev/null | grep -q '^installed$' \
			|| missing="$missing $pkg"
	done
	[ -z "$missing" ] && return 0

	echo "[ ! ] $label: package(s) not installed:$missing" >&2
	echo "WARNING: $label: package(s) not installed:$missing" >> "${LOG}"
	HESTIA_INSTALL_WARNINGS="${HESTIA_INSTALL_WARNINGS:-}${label}:${missing}"$'\n'
	return 1
}

# Auto-apt units race the installer for the dpkg lock (#480). Masking them for the duration is the
# reliable fix; Lock::Timeout above is the belt-and-suspenders for anything else holding it. Restore
# is trap-driven so an aborted install does not leave a box with unattended-upgrades disabled - which
# would be a silent security regression, far worse than the race it prevents.
HESTIA_APT_AUTO_UNITS='unattended-upgrades.service apt-daily.service apt-daily.timer apt-daily-upgrade.service apt-daily-upgrade.timer'

apt_auto_units_mask() {
	local u
	HESTIA_APT_UNMASK=''
	for u in $HESTIA_APT_AUTO_UNITS; do
		systemctl list-unit-files "$u" > /dev/null 2>&1 || continue
		# Only record what WE masked, so the restore cannot enable a unit the admin had masked.
		systemctl is-enabled "$u" 2> /dev/null | grep -q '^masked$' && continue
		systemctl mask --now "$u" > /dev/null 2>&1 && HESTIA_APT_UNMASK="$HESTIA_APT_UNMASK $u"
	done
	[ -n "$HESTIA_APT_UNMASK" ] && echo "[ * ] Paused auto-apt units for the install:$HESTIA_APT_UNMASK"
	return 0
}

apt_auto_units_restore() {
	local u
	for u in ${HESTIA_APT_UNMASK:-}; do
		systemctl unmask "$u" > /dev/null 2>&1 || true
		case "$u" in *.timer) systemctl start "$u" > /dev/null 2>&1 || true ;; esac
	done
	HESTIA_APT_UNMASK=''
	return 0
}

# ── OS default PHP (shared by wizard + installer, #191) ─────────────────────
# The distro's own php meta package decides the panel/reference PHP version.
# Sury-filtered on purpose: on a Sury-enabled box the sury php meta shadows the
# OS one (apt-cache depends answered 8.4 on noble whose OS default is 8.3), so
# read madison and drop the sury lines. Empty output = caller must fail loudly,
# never fall back to a hardcoded version that may not exist in the OS repo.
os_default_php() {
	local all osl sury_host
	all=$(apt-cache madison php 2> /dev/null)
	osl=$(printf '%s' "$all" | grep -v 'packages\.sury\.org')
	# positive control of the filter, with the expectation read from the box's own
	# repo definition (the file add_sury_repo writes) instead of any grep pattern:
	# if madison carries the host named in php.list, the filter above must have
	# removed those lines - otherwise its spelling drifted and the first madison
	# line would be sury's newest, not the OS default. A php.list whose host is
	# not in the lists yet (update not run) raises no expectation and no alarm.
	sury_host=$(grep -oE 'https?://[^ ]+' /etc/apt/sources.list.d/php.list 2> /dev/null | head -n1)
	sury_host="${sury_host#*//}"
	sury_host="${sury_host%%/*}"
	if [ -n "$sury_host" ] && printf '%s' "$all" | grep -qF "$sury_host" && [ "$all" = "$osl" ]; then
		echo "ERROR: os_default_php: $sury_host is in the apt lists but the filter removed none of it - filter pattern drifted" >&2
		return 1
	fi
	printf '%s\n' "$osl" | awk -F'|' '{print $2}' | grep -oE '[0-9]+\.[0-9]+' | head -n1
}

# ── PHP package availability probe (#191) ───────────────────────────────────
# A pure-OS box does not carry everything the Sury list has. apt -s sees real
# and virtual packages alike. $1 names the extension suffixes that may drop
# with a warning, each carrying its own condition: "name" tolerates always,
# "name:X.Y" only from PHP X.Y on - php8.2-imap DOES exist in the OS repos, so
# a flat tolerance would swallow a real repo failure on 8.2/8.3. Any other
# failed probe is apt not answering, not a missing package: return 1 instead
# of installing through it and surfacing as a broken panel later.
filter_installable_php_pkgs() {
	local tolerated="$1" p keep="" suffix pv entry ename emin hit
	shift
	for p in "$@"; do
		if apt-get -qq -s install "$p" > /dev/null 2>&1; then
			keep="$keep $p"
			continue
		fi
		suffix="${p#php*.*-}"
		pv=$(printf '%s' "$p" | grep -oE '[0-9]+\.[0-9]+' | head -n1)
		hit=""
		for entry in $tolerated; do
			ename="${entry%%:*}"
			emin="${entry#*:}"
			[ "$ename" = "$suffix" ] || continue
			if [ "$emin" = "$entry" ]; then
				hit=yes # unconditional entry
			elif [ -n "$pv" ] && [ "$(printf '%s\n%s\n' "$emin" "$pv" | sort -V | head -n1)" = "$emin" ]; then
				hit=yes # pv >= emin
			fi
			break
		done
		if [ -n "$hit" ]; then
			echo "[ ! ] $p is not available from the configured repos - skipped" >&2
		else
			echo "ERROR: $p is not installable and its tolerated-drop entry does not cover this version - repos unreachable or broken?" >&2
			return 1
		fi
	done
	echo "${keep# }"
}

# ── Sury PHP repository (shared by wizard + installer) ──────────────────────
# Idempotent, single canonical definition (keyring + signed-by + source file) -
# two diverging ones trip apt's "Conflicting values set for option Signed-By".
# Usage: add_sury_repo <codename>
add_sury_repo() {
	local codename="$1"
	[ -n "$codename" ] || {
		echo "ERROR: add_sury_repo: codename missing" >&2
		return 1
	}
	local arch keyring list
	arch="$(dpkg --print-architecture 2> /dev/null || uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
	keyring="/usr/share/keyrings/sury-keyring.gpg"
	list="/etc/apt/sources.list.d/php.list"
	# drop any legacy/foreign Sury definition that would conflict on Signed-By
	rm -f /etc/apt/sources.list.d/sury-php.list /etc/apt/trusted.gpg.d/sury-php.gpg
	if [ ! -s "$keyring" ]; then
		curl -fsSL https://packages.sury.org/php/apt.gpg -o /tmp/sury_apt.gpg \
			|| {
				echo "ERROR: failed to download Sury PHP signing key" >&2
				return 1
			}
		gpg --dearmor < /tmp/sury_apt.gpg > "$keyring" \
			|| {
				echo "ERROR: failed to dearmor Sury PHP signing key" >&2
				rm -f /tmp/sury_apt.gpg
				return 1
			}
		rm -f /tmp/sury_apt.gpg
	fi
	[ -s "$keyring" ] || {
		echo "ERROR: Sury keyring empty" >&2
		return 1
	}
	printf 'deb [arch=%s signed-by=%s] https://packages.sury.org/php/ %s main\n' \
		"$arch" "$keyring" "$codename" > "$list"
}

# ── per-OS data ─────────────────────────────────────────────────────────────
# INSTALL_OS token -> OS_ID, CODENAME, RELEASE, EXIM_USR, BASE_PKGS_EXTRA
load_os_profile() {
	case "$1" in
		debian-bookworm)
			OS_ID="debian"
			CODENAME="bookworm"
			RELEASE="12"
			EXIM_USR="Debian-exim"
			BASE_PKGS_EXTRA="libmail-dkim-perl unrar-free"
			;;
		debian-trixie)
			OS_ID="debian"
			CODENAME="trixie"
			RELEASE="13"
			EXIM_USR="Debian-exim"
			BASE_PKGS_EXTRA="libmail-dkim-perl unrar-free"
			;;
		ubuntu-noble)
			OS_ID="ubuntu"
			CODENAME="noble"
			RELEASE="24"
			EXIM_USR="Debian-exim"
			# libzip4t64: t64 transition renamed libzip4 on 24.04
			BASE_PKGS_EXTRA="libmail-dkim-perl libonig5 libzip4t64 apparmor-utils"
			;;
		ubuntu-26lts)
			# TODO: pin the official 26.04 codename; until then read it at runtime
			OS_ID="ubuntu"
			RELEASE="26"
			CODENAME="$(
				. /etc/os-release 2> /dev/null
				echo "${VERSION_CODENAME:-}"
			)"
			EXIM_USR="Debian-exim"
			# 26.04 ships libzip5; libzip4/libzip4t64 do not exist here at all
			BASE_PKGS_EXTRA="libmail-dkim-perl libonig5 libzip5 apparmor-utils"
			;;
		*)
			echo "ERROR: unsupported OS token '$1'" >&2
			return 1
			;;
	esac
	[ -n "$CODENAME" ] || {
		echo "ERROR: could not determine codename for '$1'" >&2
		return 1
	}
}

# ── seed /etc/hestia ────────────────────────────────────────────────────────
# Create hestia.env, /etc/profile.d/hestia.sh and a seed hestia.conf before any
# h-* command runs, so main.sh can source them safely.
seed_hestia_etc() {
	local hestia_root="${HESTIA:-/usr/local/hestia}"
	local install_conf="/etc/hestia/install.conf"
	local admin="admin" port="8083" version
	if [ -f "$install_conf" ]; then
		# shellcheck disable=SC1090
		. "$install_conf"
		admin="${HESTIA_ADMIN:-admin}"
		port="${HESTIA_PANEL_PORT:-8083}"
	fi
	version=$(cat "$hestia_root/VERSION" 2> /dev/null || echo "dev")

	mkdir -p /etc/hestia
	# if-form for the local.conf include so the file's last statement returns 0
	# (a trailing `&& source` returns 1 when absent and aborts callers under set -e)
	printf '%s\n' \
		"# Do not edit - use /etc/hestia/local.conf instead" \
		"export HESTIA='$hestia_root'" \
		"export CONF_DIR='/etc/hestia'" \
		"if [ -f /etc/hestia/local.conf ]; then . /etc/hestia/local.conf; fi" \
		> /etc/hestia/hestia.env
	# root-only (0600): /etc/profile skips it for non-root, so login users aren't exposed.
	# sbin holds what the panel must never reach through sudo (#209) - root still types it.
	printf 'export HESTIA='"'"'%s'"'"'\nPATH=$PATH:%s/bin:%s/sbin\nexport PATH\n' \
		"$hestia_root" "$hestia_root" "$hestia_root" > /etc/profile.d/hestia.sh
	chmod 600 /etc/profile.d/hestia.sh

	# instance config lives in /etc/hestia/conf; bridge $HESTIA/conf as a DIRECTORY
	# symlink (file symlinks break under the 33 sed -i writers, directory ones don't)
	local conf_dir="/etc/hestia/conf"
	mkdir -p "$conf_dir"
	if [ ! -L "$hestia_root/conf" ]; then
		if [ -d "$hestia_root/conf" ]; then
			cp -an "$hestia_root/conf/." "$conf_dir/" 2> /dev/null || true
			rm -rf "$hestia_root/conf"
		fi
		ln -sfn "$conf_dir" "$hestia_root/conf"
	fi
	# SEED, not rewrite: install.sh runs this on every start, and truncating left a resumed install
	# with only the keys of the stages that had NOT completed - an empty WEB_SYSTEM on a web box.
	[ -f "$conf_dir/hestia.conf" ] || : > "$conf_dir/hestia.conf"
	chmod 660 "$conf_dir/hestia.conf"
	_wcv() { grep -q "^$1=" "$conf_dir/hestia.conf" || echo "$1='$2'" >> "$conf_dir/hestia.conf"; }
	_wcv "BACKEND_PORT" "$port"
	_wcv "CRON_SYSTEM" "cron"
	# capability state, not a switch (#211): quota_arm overwrites it from measurement
	_wcv "PROJECT_QUOTA" "none:unprobed"
	_wcv "BACKUP_SYSTEM" "local"
	_wcv "BACKUP_GZIP" "3"
	_wcv "BACKUP_MODE" "zstd"
	_wcv "LANGUAGE" "en"
	_wcv "LOGIN_STYLE" "default"
	_wcv "THEME" "dark"
	_wcv "INACTIVE_SESSION_TIMEOUT" "60"
	_wcv "VERSION" "$version"
	_wcv "RELEASE_BRANCH" "release"
	_wcv "UPGRADE_SEND_EMAIL" "true"
	_wcv "UPGRADE_SEND_EMAIL_LOG" "false"
	_wcv "ROOT_USER" "$admin"
	# seed DB_SYSTEM empty - it is composed from registered hosts by h-add-database-host
	_wcv "DB_SYSTEM" ""
	unset -f _wcv
	# Not a seed value, it follows the tree. Replace OR append - a bare sed would do nothing the day
	# the seed above stops writing the key.
	if grep -q "^VERSION=" "$conf_dir/hestia.conf"; then
		sed -i "s|^VERSION=.*|VERSION='$version'|" "$conf_dir/hestia.conf"
	else
		echo "VERSION='$version'" >> "$conf_dir/hestia.conf"
	fi
}

# ── re-apply what a copy-only update cannot: state outside the install tree ───
# Idempotent throughout, so a fresh install runs this as a no-op.
# Keep panel command lines (passwords are passed as arguments) out of persistent logs. Classic
# sudo takes "!log_allowed" - allowed calls unlogged, denials still logged; sudo-rs accepts no
# logging option, so there the rsyslog drop rule carries it. Only visudo-validated content is
# ever installed: a broken sudoers locks the panel out.
deploy_hestia_sudoers() {
	local root="${HESTIA:-/usr/local/hestia}" tmp
	[ -f "$root/share/hestia/sudoers" ] && [ -d /etc/sudoers.d ] || return 0
	local suppressed="no" dropped="no"
	tmp=$(mktemp)
	{
		printf 'Defaults:hestia !log_allowed\n'
		cat "$root/share/hestia/sudoers"
	} > "$tmp"
	if visudo -c -f "$tmp" > /dev/null 2>&1; then
		suppressed="yes"
	else
		# This flavor keeps logging argv and depends entirely on the rsyslog rule - say so.
		echo "NOTE: this sudo does not accept !log_allowed - relying on the rsyslog drop rule"
		cp -f "$root/share/hestia/sudoers" "$tmp"
	fi
	if visudo -c -f "$tmp" > /dev/null 2>&1; then
		install -m 440 -o root -g root "$tmp" /etc/sudoers.d/hestia
	else
		echo "WARN: sudoers does not validate on this box - /etc/sudoers.d/hestia left untouched"
	fi
	rm -f "$tmp"
	if [ -f "$root/share/hestia/rsyslog-sudo-nolog.conf" ] && [ -d /etc/rsyslog.d ]; then
		cp -f "$root/share/hestia/rsyslog-sudo-nolog.conf" /etc/rsyslog.d/10-hestia-sudo-nolog.conf
		systemctl try-restart rsyslog > /dev/null 2>&1 || true
		dropped="yes"
	fi
	# State of both layers in one line - the first thing worth knowing after a distro change.
	echo "  sudoers suppression: $([ "$suppressed" = yes ] && echo active || echo "not supported by this sudo")," \
		"rsyslog drop rule: $([ "$dropped" = yes ] && echo deployed || echo "rsyslog absent")"
	if [ "$suppressed" = "no" ] && [ "$dropped" = "no" ]; then
		echo "WARN: neither layer could be applied - panel command lines (incl. secrets passed" \
			"as arguments) stay in the system log"
	fi
}

reapply_outside_tree() {
	local hestia_root="${HESTIA:-/usr/local/hestia}"

	# theme renames: vestia removed, default->light, flat->light-flat; drop stale files
	local theme_sed="s/^THEME='vestia'/THEME='light'/; s/^THEME='default'/THEME='light'/; s/^THEME='flat'/THEME='light-flat'/"
	local conf
	for conf in "$hestia_root/conf/hestia.conf" "$CONF_DIR/conf/hestia.conf"; do
		[ -f "$conf" ] && sed -i "$theme_sed" "$conf"
	done
	for conf in "$CONF_DIR/users"/*/user.conf; do
		[ -f "$conf" ] && sed -i "$theme_sed" "$conf"
	done
	rm -f "$hestia_root/web/css/src/themes/vestia.css" \
		"$hestia_root/web/css/src/themes/default.css" \
		"$hestia_root/web/css/src/themes/flat.css"

	deploy_hestia_sudoers

	# build the isolated panel conf.d - activates the isolation on existing installs
	if [ -x "$hestia_root/sbin/hestia-php-confd" ] && [ -f /etc/php/hestia/php-version ]; then
		"$hestia_root/sbin/hestia-php-confd" > /dev/null 2>&1 || true
	fi

	# restrict the shell-profile snippet to root on existing installs (was world-readable)
	[ -f /etc/profile.d/hestia.sh ] && chmod 600 /etc/profile.d/hestia.sh

	# move /proc hardening off the @reboot cron onto its systemd unit (proc_hardening_apply);
	# idempotent, so a box already converted just gets its gid re-asserted
	proc_hardening_apply || true

	# The customer PHP cap on an existing box: the units and the drop-ins are ours, so an
	# update installs what a fresh install would have (#212).
	if declare -F customer_php_limit_apply > /dev/null 2>&1; then
		customer_php_limit_apply || true
	elif [ -f "$hestia_root/include/limits.sh" ]; then
		# shellcheck source=/usr/local/hestia/include/limits.sh
		source "$hestia_root/include/limits.sh" && customer_php_limit_apply || true
	fi

	# The band guard travels with the allocator (#388); existing accounts are left alone.
	login_defs_guard || true
}

# ── /proc hardening (hidepid) ───────────────────────────────────────────────
# Why a unit, why hidepid=invisible, why the gid= exemption and why the gid is resolved
# at boot: see the header of share/security/systemd/hestia-proc-hardening.service.
PROC_VISIBLE_GROUP='procvis'
PROC_HARDENING_UNIT='hestia-proc-hardening.service'

proc_visible_gid() { getent group "$PROC_VISIBLE_GROUP" 2> /dev/null | cut -d: -f3; }

# Remove the docker0 bridge the rootful daemon leaves behind (#579).
#
# `apt-get install docker-ce` starts the rootful daemon - systemd enables and starts the unit as
# part of the package install - and it creates docker0 before h-add-sys-docker gets to disable it
# again. The bridge then stays: empty, `down`, and holding 172.17.0.0/16.
#
# It is not merely untidy. `ip route get 172.17.0.2` answers `dev docker0 src 172.17.0.1`, so a
# route to a rootless container's address looks like it exists while the packets go nowhere - the
# containers live in their own netns with no path from the host. That costs real time in exactly
# the area where per-user Docker is debugged.
#
# Only when empty. A host where someone deliberately runs rootful Docker has interfaces enslaved to
# the bridge, and removing it there would cut live containers off.
docker_drop_orphan_bridge() {
	ip -o link show docker0 > /dev/null 2>&1 || return 0
	if [ "$(ip -o link show master docker0 2> /dev/null | wc -l)" -gt 0 ]; then
		echo "Note: docker0 has attached interfaces - left alone (rootful Docker in use?)." >&2
		return 0
	fi
	ip link delete docker0 > /dev/null 2>&1 \
		&& echo "Removed the orphaned docker0 bridge (left by the packaged rootful daemon)."
	return 0
}

# Re-runnable: proc_visible_add plus a re-run is how "enable Docker" wires a companion
# in. Returns 0 when hidepid is not applicable (container), so 0 does not imply the
# unit is installed.
proc_hardening_apply() {
	local gid opts src="${HESTIA:-/usr/local/hestia}/share/security/systemd/$PROC_HARDENING_UNIT"
	local dst="/etc/systemd/system/$PROC_HARDENING_UNIT"

	getent group "$PROC_VISIBLE_GROUP" > /dev/null 2>&1 \
		|| groupadd --system "$PROC_VISIBLE_GROUP" > /dev/null 2>&1 \
		|| {
			echo "Warning: cannot create group $PROC_VISIBLE_GROUP - skipping /proc hardening" >&2
			return 1
		}

	# Mirrors what the unit does at every boot. gid=0 when the group is gone: a remount
	# that merely omits gid keeps the previous value, so this is what actually withdraws
	# a stale exemption on a running box.
	gid="$(proc_visible_gid)"
	opts="nosuid,nodev,noexec,relatime,hidepid=invisible,gid=${gid:-0}"

	# The legacy @reboot job goes regardless of which branch we take below.
	rm -f /etc/cron.d/hestia-proc

	# Prove it on the running kernel first: a container refuses the remount, and the unit
	# would then only fail at every boot.
	if ! mount -o "remount,$opts" /proc > /dev/null 2>&1; then
		echo "Info: cannot remount /proc (container) - skipping hidepid"
		systemctl disable --now "$PROC_HARDENING_UNIT" > /dev/null 2>&1 || true
		rm -f "$dst"
		systemctl daemon-reload
		return 0
	fi

	# Installed verbatim: the unit resolves the gid itself on every start, so there is
	# nothing host-specific to substitute and nothing to go stale.
	[ -f "$src" ] || {
		echo "Warning: $src missing - hidepid applied live, not persisted" >&2
		return 1
	}
	install -m 644 "$src" "$dst" || return 1
	systemctl daemon-reload
	systemctl enable "$PROC_HARDENING_UNIT" > /dev/null 2>&1
}

# The user manager caches supplementary groups: an already-running session under that
# uid must be restarted before this takes effect.
proc_visible_add() {
	local user="$1"
	[ -n "$user" ] || return 1
	getent group "$PROC_VISIBLE_GROUP" > /dev/null 2>&1 || return 1
	usermod -aG "$PROC_VISIBLE_GROUP" "$user"
}

# ── login.defs guard rail for the panel UID band (#388) ─────────────────────
# Keeps a bare useradd/adduser out of the band include/identity.sh allocates from; a
# foreign account inside it would collide with an allocation. SUB_UID_MAX has to be
# raised too - the shipped 600100000 is below our highest range end (1048675999).
login_defs_guard() {
	local f='/etc/login.defs' kv k v
	[ -f "$f" ] || return 0
	for kv in 'UID_MAX 9999' 'GID_MAX 9999' \
		'SUB_UID_MIN 100000' 'SUB_UID_MAX 2147483647' \
		'SUB_GID_MIN 100000' 'SUB_GID_MAX 2147483647'; do
		k="${kv%% *}"
		v="${kv##* }"
		if grep -qE "^[[:space:]]*#?[[:space:]]*${k}[[:space:]]" "$f"; then
			sed -i -E "s|^[[:space:]]*#?[[:space:]]*${k}[[:space:]].*|${k}\t\t\t${v}|" "$f"
		else
			printf '%s\t\t\t%s\n' "$k" "$v" >> "$f"
		fi
	done
}
