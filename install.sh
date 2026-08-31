#!/bin/bash

# ======================================================== #
#
# HestiaRE Installer — Bootstrap
#
# The single curl-able entry point. It only does what the bootstrap needs:
#   1. install prerequisites (curl, jq, whiptail, gnupg)
#   2. detect the OS
#   3. fetch + extract the release tarball into /usr/local/hestia
#   4. run the wizard (include/wizard.sh)  -> writes /etc/hestia/install.conf
#   5. seed /etc/hestia (env + hestia.conf) so h-* commands can run
#   6. hand off to sbin/h-install-hestia  (or: hestia install)
#
# There is no `just` dependency anymore — the installer is pure bash.
#
# Usage:
#   bash install.sh                  # full interactive wizard
#   bash install.sh <preset>         # fasttrack: skip component questions
#   bash install.sh <preset> -a      # fully unattended: also take the default
#                                    #   hostname/port/admin/email, no prompts
#   bash install.sh <preset> -a --port=9443   # unattended on a non-default panel port
#   bash install.sh --dev            # configure private source first
#   bash install.sh --profile=<p>    # same as positional preset arg
#
# Supported OS:
#   Debian 12 (bookworm), Debian 13 (trixie),
#   Ubuntu 24.04 LTS (noble), Ubuntu 26.04 LTS
#
# ======================================================== #

set -euo pipefail

# ── Constants ──────────────────────────────────────────────
SOURCE_CONF="/etc/hestia/source.conf"
INSTALL_DIR="/usr/local/hestia"
MANIFEST="${INSTALL_DIR}/share/manifest.json"
LOG_DIR="/var/log/hestia"

# GitHub defaults - can be overridden by /etc/hestia/source.conf
# (set HESTIARE_SOURCE=gitea + HESTIARE_REPO_URL for private Gitea releases)
GITHUB_REPO="HestiaRE/Hestia"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}"
GITHUB_RAW="https://github.com/${GITHUB_REPO}/releases/download"
# github.com has no AAAA, so on a v6-only box the primary is unreachable. This mirror serves the
# same repo's release API (/api) and assets (/raw) unchanged - a retry, not a second source. An
# empty HESTIARE_MIRROR in source.conf switches it off; the twin literal in sbin/h-update-hestia
# is deliberate, install.sh runs before the tree exists.
RELEASE_MIRROR="https://dl.hestiare.com"

# ── State ──────────────────────────────────────────────────
OS=""
FASTTRACK_PRESET=""
PANEL_PORT=""
DEV_MODE=false
AUTO_MODE=false

# ── Error surfacing ────────────────────────────────────────
# With set -e the script aborts on the first failed command. Because prerequisite
# output is redirected to the log, that abort would otherwise be silent. This
# trap surfaces the failure and the tail of the log.
_on_error() {
	local rc=$1 line=$2
	echo "" >&2
	echo "ERROR: install.sh aborted (exit ${rc}, line ${line})." >&2
	if [ -f "${LOG_DIR}/install.log" ]; then
		echo "       Last lines of ${LOG_DIR}/install.log:" >&2
		tail -n 15 "${LOG_DIR}/install.log" 2> /dev/null | sed 's/^/       | /' >&2 || true
	fi
}
trap '_on_error "$?" "$LINENO"' ERR

# ── Argument parsing ───────────────────────────────────────
for _arg in "$@"; do
	case $_arg in
		--dev) DEV_MODE=true ;;
		--profile=*) FASTTRACK_PRESET="${_arg#*=}" ;;
		--port=*) PANEL_PORT="${_arg#*=}" ;;
		-a | --auto) AUTO_MODE=true ;;
		-*) ;;
		*) [ -z "$FASTTRACK_PRESET" ] && FASTTRACK_PRESET="$_arg" ;;
	esac
done

# --auto only makes sense together with a preset: without one, the preset
# selection would still prompt, defeating "unattended". Fail early and clearly.
if [ "$AUTO_MODE" = true ] && [ -z "$FASTTRACK_PRESET" ]; then
	echo "ERROR: -a/--auto requires a preset, e.g.:  bash install.sh standard -a" >&2
	echo "       Valid presets: standard, compact, latest, singlephp, nomail, mailonly" >&2
	exit 1
fi

# ════════════════════════════════════════════════════════════
# Prerequisites
# ════════════════════════════════════════════════════════════

fn_prerequisites() {
	[ "${EUID:-$(id -u)}" -eq 0 ] || {
		echo "ERROR: Must run as root." >&2
		exit 1
	}

	if [ ! -f /etc/os-release ]; then
		echo "ERROR: Cannot determine OS. /etc/os-release missing." >&2
		exit 1
	fi
	source /etc/os-release
	case "${ID}:${VERSION_ID}" in
		debian:12) OS="debian-bookworm" ;;
		debian:13) OS="debian-trixie" ;;
		ubuntu:24.04) OS="ubuntu-noble" ;;
		ubuntu:26.04) OS="ubuntu-26lts" ;; # TODO: replace with official codename once confirmed
		*)
			echo "ERROR: Unsupported OS: ${ID} ${VERSION_ID}" >&2
			echo "Supported: Debian 12, Debian 13 (trixie), Ubuntu 24.04 LTS, Ubuntu 26.04 LTS" >&2
			exit 1
			;;
	esac

	mkdir -p "$LOG_DIR"
	# gnupg: needed to dearmor APT signing keys (Sury during PHP discovery, and Sury+MariaDB in the install stage).
	# jq+whiptail: the wizard. curl/ca-certs: downloads. apt-utils: without it debconf logs
	# "delaying package configuration, since apt-utils is not installed" on every later apt call
	echo "[ * ] Installing prerequisites..."
	DEBIAN_FRONTEND=noninteractive apt-get -qq update
	DEBIAN_FRONTEND=noninteractive apt-get -y -qq install curl jq whiptail ca-certificates gnupg apt-utils >> "$LOG_DIR/install.log" 2>&1

	if [ "$DEV_MODE" = true ]; then
		_dev_setup
	fi

	[ -f "$SOURCE_CONF" ] && source "$SOURCE_CONF" || true
	HESTIARE_SOURCE="${HESTIARE_SOURCE:-github}"

	if [ ! -f "$MANIFEST" ]; then
		_fetch_release
	fi
}

_dev_setup() {
	echo ""
	echo "HestiaRE — Dev Source Setup"
	echo "---------------------------"
	HESTIARE_REPO_URL="${HESTIARE_REPO_URL:-}"
	HESTIARE_TOKEN="${HESTIARE_TOKEN:-}"
	HESTIARE_CHANNEL="${HESTIARE_CHANNEL:-stable}"
	read -rp "Source repo URL [${HESTIARE_REPO_URL:-https://gitea.example.com/user/hestiare}]: " _i < /dev/tty
	HESTIARE_REPO_URL="${_i:-$HESTIARE_REPO_URL}"
	read -rsp "Access token (silent): " _i < /dev/tty
	echo ""
	HESTIARE_TOKEN="${_i:-$HESTIARE_TOKEN}"
	read -rp "Channel [stable/prerelease, default: stable]: " _i < /dev/tty
	HESTIARE_CHANNEL="${_i:-stable}"
	HESTIARE_SOURCE="gitea"
	mkdir -p "$(dirname "$SOURCE_CONF")"
	printf 'HESTIARE_SOURCE="%s"\nHESTIARE_REPO_URL="%s"\nHESTIARE_TOKEN="%s"\nHESTIARE_CHANNEL="%s"\n' \
		"$HESTIARE_SOURCE" "$HESTIARE_REPO_URL" "$HESTIARE_TOKEN" "$HESTIARE_CHANNEL" > "$SOURCE_CONF"
	chmod 600 "$SOURCE_CONF"
	echo "[ * ] Source config written to $SOURCE_CONF"
	echo ""
}

# Fetch one release path with the mirror as the second try. $1 = api|raw, $2 = path below that
# root, rest = curl args. Bounded: an unroutable host must surface in seconds, not after curl's
# default patience. Never carries the Gitea token, the mirror only knows the public repo.
_release_get() {
	local kind="$1" path="$2" primary mirror
	shift 2
	case "$kind" in
		api) primary="${GITHUB_API}" mirror="${RELEASE_MIRROR}/api" ;;
		raw) primary="${GITHUB_RAW}" mirror="${RELEASE_MIRROR}/raw" ;;
	esac
	curl -fsSL --connect-timeout 15 --max-time 600 "$@" "${primary}${path}" && return 0
	[ -n "$RELEASE_MIRROR" ] || return 1
	echo "[ * ] Release source unreachable, retrying via ${RELEASE_MIRROR}" >&2
	curl -fsSL --connect-timeout 15 --max-time 600 "$@" "${mirror}${path}"
}

_fetch_release() {
	HESTIARE_REPO_URL="${HESTIARE_REPO_URL:-}"
	HESTIARE_TOKEN="${HESTIARE_TOKEN:-}"
	HESTIARE_CHANNEL="${HESTIARE_CHANNEL:-stable}"
	RELEASE_MIRROR="${HESTIARE_MIRROR-$RELEASE_MIRROR}"
	# A private Gitea release is a different build - it never falls back to the public mirror.
	[ "${HESTIARE_SOURCE:-github}" = "gitea" ] && RELEASE_MIRROR=""

	echo "[ * ] Fetching latest release..."
	local latest
	local -a curl_auth=()
	[ -n "$HESTIARE_TOKEN" ] && curl_auth=(-H "Authorization: token ${HESTIARE_TOKEN}")

	if [ "${HESTIARE_SOURCE:-github}" = "gitea" ]; then
		latest=$(curl -fsSL "${curl_auth[@]}" "${HESTIARE_REPO_URL}/releases/latest" \
			| jq -r '.tag_name') || latest=''
	elif [ "${HESTIARE_CHANNEL}" = "prerelease" ]; then
		latest=$(_release_get api "/releases" | jq -r '.[0].tag_name') || latest=''
	else
		latest=$(_release_get api "/releases/latest" | jq -r '.tag_name') || latest=''
	fi

	# the assignments above absorb their own failure, or set -e would abort before this message
	{ [ -n "$latest" ] && [ "$latest" != "null" ]; } || {
		echo "ERROR: Could not determine latest release." >&2
		exit 1
	}
	echo "[ * ] Version: ${latest}"

	if [ "${HESTIARE_SOURCE:-github}" = "gitea" ]; then
		curl -fsSL "${curl_auth[@]}" \
			"${HESTIARE_REPO_URL}/releases/download/${latest}/hestiare-${latest}.tar.gz" \
			-o /tmp/hestiare.tar.gz
	else
		_release_get raw "/${latest}/hestiare-${latest}.tar.gz" -o /tmp/hestiare.tar.gz
	fi
	tar -xzf /tmp/hestiare.tar.gz -C /tmp
	rm /tmp/hestiare.tar.gz
	# A mirror can cache or hand back the wrong asset, and on a v6-only box there is no second
	# opinion: the extracted tree has to carry the version that was asked for.
	_got=$(cat "/tmp/hestiare-${latest}/VERSION" 2> /dev/null || echo "")
	if [ "${_got#v}" != "${latest#v}" ]; then
		echo "ERROR: fetched release is not ${latest} (tree says '${_got:-nothing}')." >&2
		rm -rf "/tmp/hestiare-${latest}"
		exit 1
	fi
	mkdir -p "${INSTALL_DIR}"
	cp -r /tmp/hestiare-${latest}/. "${INSTALL_DIR}/"
	rm -rf /tmp/hestiare-${latest}
	echo "[ * ] Extracted to ${INSTALL_DIR}"
}

# ════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════

main() {
	clear 2> /dev/null || true
	echo "========================================================================"
	echo " HestiaRE Installer"
	echo "========================================================================"
	echo ""

	fn_prerequisites
	echo "[ * ] OS: ${OS}"
	echo ""

	# Wizard: manifest-driven Q&A -> /etc/hestia/install.conf (separate process)
	bash "${INSTALL_DIR}/include/wizard.sh" --os="${OS}" \
		${FASTTRACK_PRESET:+--preset="${FASTTRACK_PRESET}"} \
		${PANEL_PORT:+--port="${PANEL_PORT}"} \
		$([ "$AUTO_MODE" = true ] && echo --auto)

	# Seed /etc/hestia (env + hestia.conf) before any h-* command runs, so the
	# bootstrap-trap (include/main.sh sourcing hestia.env/hestia.conf at load) is a
	# non-issue. h-install-hestia then only validates these files exist.
	# shellcheck source=/usr/local/hestia/include/helper.sh
	HESTIA="${INSTALL_DIR}" source "${INSTALL_DIR}/include/helper.sh"
	HESTIA="${INSTALL_DIR}" seed_hestia_etc

	echo ""
	echo "========================================================================"
	echo " Starting installation..."
	echo "========================================================================"
	echo ""

	"${INSTALL_DIR}/sbin/h-install-hestia"
}

main "$@"
