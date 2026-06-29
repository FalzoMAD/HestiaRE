#!/bin/bash

#===========================================================================#
#                                                                           #
# HestiaRE - Installer Helper Library                                        #
#                                                                           #
# General home for cross-cutting install-time helpers, sourced by           #
# bin/h-install-hestia and the other lifecycle commands:                    #
#   - hestia_apt    : apt wrapper (spinner + stdout->log, stderr->term+log) #
#   - load_os_profile : per-OS data for all supported targets               #
#   - seed_hestia_etc  : create /etc/hestia env + seed hestia.conf          #
#                                                                           #
# Requires $LOG to point at the install log for hestia_apt.                 #
#===========================================================================#

# ── apt wrapper with spinner ───────────────────────────────────────────────
# stdout (verbose package text) -> log only
# stderr (apt errors/warnings)  -> terminal + log
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
	kill "$_hestia_spin_pid" 2>/dev/null || true
	wait "$_hestia_spin_pid" 2>/dev/null || true
	printf '\r\033[K' >&2
	_hestia_spin_pid=""
}

# Usage: hestia_apt [apt-get args...]
hestia_apt() {
	_hestia_spin_start
	local _rc=0
	DEBIAN_FRONTEND=noninteractive apt-get "$@" \
		1>> "${LOG}" \
		2> >(tee -a "${LOG}" >&2) || _rc=$?
	_hestia_spin_stop
	return $_rc
}

# ── Sury PHP repository (shared by wizard + installer) ──────────────────────
# Canonical, idempotent Sury setup. BOTH func/wizard.sh (PHP version discovery)
# and bin/h-install-hestia (base stage) call this, so the repo is defined exactly
# ONCE — same keyring, same signed-by, same source file. Two diverging
# definitions of packages.sury.org/php trip apt's
#   "Conflicting values set for option Signed-By"
# error and abort apt-get update. Canonical layout:
#   keyring: /usr/share/keyrings/sury-keyring.gpg
#   source : /etc/apt/sources.list.d/php.list   (deb [… signed-by=…] …)
# Usage: add_sury_repo <codename>
add_sury_repo() {
	local codename="$1"
	[ -n "$codename" ] || { echo "ERROR: add_sury_repo: codename missing" >&2; return 1; }
	local arch keyring list
	arch="$(dpkg --print-architecture 2>/dev/null || uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
	keyring="/usr/share/keyrings/sury-keyring.gpg"
	list="/etc/apt/sources.list.d/php.list"
	# Drop any legacy/foreign Sury definition that would conflict on Signed-By.
	rm -f /etc/apt/sources.list.d/sury-php.list /etc/apt/trusted.gpg.d/sury-php.gpg
	if [ ! -s "$keyring" ]; then
		curl -fsSL https://packages.sury.org/php/apt.gpg -o /tmp/sury_apt.gpg \
			|| { echo "ERROR: failed to download Sury PHP signing key" >&2; return 1; }
		gpg --dearmor < /tmp/sury_apt.gpg > "$keyring" \
			|| { echo "ERROR: failed to dearmor Sury PHP signing key" >&2; rm -f /tmp/sury_apt.gpg; return 1; }
		rm -f /tmp/sury_apt.gpg
	fi
	[ -s "$keyring" ] || { echo "ERROR: Sury keyring empty" >&2; return 1; }
	printf 'deb [arch=%s signed-by=%s] https://packages.sury.org/php/ %s main\n' \
		"$arch" "$keyring" "$codename" > "$list"
}

# ── per-OS data ─────────────────────────────────────────────────────────────
# Given the INSTALL_OS token (debian-bookworm, debian-trixie, ubuntu-noble,
# ubuntu-26lts) sets: OS_ID, CODENAME, RELEASE, EXIM_USR, BASE_PKGS_EXTRA.
# Replaces the per-file just/<os>.sh data modules. All four targets are
# first-class — deb13/ub26 are not stubbed.
load_os_profile() {
	case "$1" in
		debian-bookworm)
			OS_ID="debian"; CODENAME="bookworm"; RELEASE="12"
			EXIM_USR="Debian-exim"
			BASE_PKGS_EXTRA="libmail-dkim-perl unrar-free"
			;;
		debian-trixie)
			OS_ID="debian"; CODENAME="trixie"; RELEASE="13"
			EXIM_USR="Debian-exim"
			BASE_PKGS_EXTRA="libmail-dkim-perl unrar-free"
			;;
		ubuntu-noble)
			OS_ID="ubuntu"; CODENAME="noble"; RELEASE="24"
			EXIM_USR="Debian-exim"
			BASE_PKGS_EXTRA="libmail-dkim-perl libonig5 libzip4 apparmor-utils"
			;;
		ubuntu-26lts)
			# TODO: pin the official 26.04 LTS codename once confirmed. Until then
			# read it from /etc/os-release at runtime so APT repo lines are correct.
			OS_ID="ubuntu"; RELEASE="26"
			CODENAME="$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-}")"
			EXIM_USR="Debian-exim"
			BASE_PKGS_EXTRA="libmail-dkim-perl libonig5 libzip4 apparmor-utils"
			;;
		*)
			echo "ERROR: unsupported OS token '$1'" >&2
			return 1
			;;
	esac
	[ -n "$CODENAME" ] || { echo "ERROR: could not determine codename for '$1'" >&2; return 1; }
}

# ── seed /etc/hestia ────────────────────────────────────────────────────────
# Creates /etc/hestia/hestia.env, /etc/profile.d/hestia.sh and a seed
# $HESTIA/conf/hestia.conf with install-independent defaults — BEFORE any h-*
# command runs, so func/main.sh can source hestia.env + hestia.conf safely.
# Reads HESTIA_ADMIN / HESTIA_PANEL_PORT from install.conf (if present).
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
	version=$(cat "$hestia_root/VERSION" 2>/dev/null || echo "dev")

	mkdir -p /etc/hestia
	# Always (re)generate hestia.env. Use an `if`-form for the local.conf include
	# so the file's LAST statement returns 0 — a trailing `[[ -f x ]] && source x`
	# returns 1 when x is absent, which aborts any caller running under `set -e`.
	printf '%s\n' \
		"# Do not edit — use /etc/hestia/local.conf instead" \
		"export HESTIA='$hestia_root'" \
		"if [ -f /etc/hestia/local.conf ]; then . /etc/hestia/local.conf; fi" \
		> /etc/hestia/hestia.env
	printf 'export HESTIA='"'"'%s'"'"'\nPATH=$PATH:%s/bin\nexport PATH\n' \
		"$hestia_root" "$hestia_root" > /etc/profile.d/hestia.sh
	chmod 755 /etc/profile.d/hestia.sh

	# Instance config lives in /etc/hestia/conf (PATHS.md §5a). Bridge the historic
	# $HESTIA/conf path with a directory symlink so the ~466 commands referencing
	# $HESTIA/conf/hestia.conf keep working AND sed -i (33 writers) stays safe
	# (only file symlinks break under sed -i; directory symlinks do not).
	local conf_dir="/etc/hestia/conf"
	mkdir -p "$conf_dir"
	if [ ! -L "$hestia_root/conf" ]; then
		if [ -d "$hestia_root/conf" ]; then
			cp -an "$hestia_root/conf/." "$conf_dir/" 2>/dev/null || true
			rm -rf "$hestia_root/conf"
		fi
		ln -sfn "$conf_dir" "$hestia_root/conf"
	fi
	rm -f "$conf_dir/hestia.conf"
	touch "$conf_dir/hestia.conf"
	chmod 660 "$conf_dir/hestia.conf"
	_wcv() { echo "$1='$2'" >> "$conf_dir/hestia.conf"; }
	_wcv "BACKEND_PORT"             "$port"
	_wcv "CRON_SYSTEM"              "cron"
	_wcv "DISK_QUOTA"               "no"
	_wcv "RESOURCES_LIMIT"          "no"
	_wcv "BACKUP_SYSTEM"            "local"
	_wcv "BACKUP_GZIP"              "4"
	_wcv "BACKUP_MODE"              "zstd"
	_wcv "LANGUAGE"                 "en"
	_wcv "LOGIN_STYLE"              "default"
	_wcv "THEME"                    "dark"
	_wcv "INACTIVE_SESSION_TIMEOUT" "60"
	_wcv "VERSION"                  "$version"
	_wcv "RELEASE_BRANCH"           "release"
	_wcv "UPGRADE_SEND_EMAIL"       "true"
	_wcv "UPGRADE_SEND_EMAIL_LOG"   "false"
	_wcv "ROOT_USER"                "$admin"
	_wcv "DB_SYSTEM"                "mysql"
	unset -f _wcv
}
