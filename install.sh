#!/bin/bash

# ======================================================== #
#
# HestiaRE Installer — Bootstrap
#
# The single curl-able entry point. It only does what the bootstrap needs:
#   1. install prerequisites (curl, jq, whiptail, gnupg)
#   2. detect the OS
#   3. fetch + extract the release tarball into /usr/local/hestia
#   4. run the wizard (func/wizard.sh)  -> writes /etc/hestia/install.conf
#   5. seed /etc/hestia (env + hestia.conf) so h-* commands can run
#   6. hand off to bin/h-install-hestia  (or: hestia install)
#
# There is no `just` dependency anymore — the installer is pure bash.
#
# Usage:
#   bash install.sh                  # full interactive wizard
#   bash install.sh <preset>         # fasttrack: skip component questions
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
MANIFEST="${INSTALL_DIR}/conf/manifest.json"
LOG_DIR="/var/log/hestia"

# GitHub defaults — can be overridden by /etc/hestia/source.conf
# (set HESTIARE_SOURCE=gitea + HESTIARE_REPO_URL for private Gitea releases)
GITHUB_REPO="FalzoMAD/HestiaRE"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}"
GITHUB_RAW="https://github.com/${GITHUB_REPO}/releases/download"

# ── State ──────────────────────────────────────────────────
OS=""
FASTTRACK_PRESET=""
DEV_MODE=false

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
        tail -n 15 "${LOG_DIR}/install.log" 2>/dev/null | sed 's/^/       | /' >&2 || true
    fi
}
trap '_on_error "$?" "$LINENO"' ERR

# ── Argument parsing ───────────────────────────────────────
for _arg in "$@"; do
    case $_arg in
        --dev)       DEV_MODE=true ;;
        --profile=*) FASTTRACK_PRESET="${_arg#*=}" ;;
        -*)          ;;
        *)           [ -z "$FASTTRACK_PRESET" ] && FASTTRACK_PRESET="$_arg" ;;
    esac
done

# ════════════════════════════════════════════════════════════
# Prerequisites
# ════════════════════════════════════════════════════════════

fn_prerequisites() {
    [ "${EUID:-$(id -u)}" -eq 0 ] || { echo "ERROR: Must run as root." >&2; exit 1; }

    if [ ! -f /etc/os-release ]; then
        echo "ERROR: Cannot determine OS. /etc/os-release missing." >&2; exit 1
    fi
    source /etc/os-release
    case "${ID}:${VERSION_ID}" in
        debian:12)    OS="debian-bookworm" ;;
        debian:13)    OS="debian-trixie"   ;;
        ubuntu:24.04) OS="ubuntu-noble"    ;;
        ubuntu:26.04) OS="ubuntu-26lts"    ;;  # TODO: replace with official codename once confirmed
        *)
            echo "ERROR: Unsupported OS: ${ID} ${VERSION_ID}" >&2
            echo "Supported: Debian 12, Debian 13 (trixie), Ubuntu 24.04 LTS, Ubuntu 26.04 LTS" >&2
            exit 1
            ;;
    esac

    mkdir -p "$LOG_DIR"
    # gnupg: needed to dearmor APT signing keys (Sury during PHP discovery, and
    # Sury+MariaDB in the install stage). jq+whiptail: the wizard. curl/ca-certs:
    # downloads. No 'just' — the installer is pure bash now.
    echo "[ * ] Installing prerequisites (curl, jq, whiptail, gnupg)..."
    DEBIAN_FRONTEND=noninteractive apt-get -qq update
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq install curl jq whiptail ca-certificates gnupg >> "$LOG_DIR/install.log" 2>&1

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
    read -rsp "Access token (silent): " _i < /dev/tty; echo ""
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

_fetch_release() {
    HESTIARE_REPO_URL="${HESTIARE_REPO_URL:-}"
    HESTIARE_TOKEN="${HESTIARE_TOKEN:-}"
    HESTIARE_CHANNEL="${HESTIARE_CHANNEL:-stable}"

    echo "[ * ] Fetching latest release..."
    local latest tarball_url
    local -a curl_auth=()
    [ -n "$HESTIARE_TOKEN" ] && curl_auth=(-H "Authorization: token ${HESTIARE_TOKEN}")

    if [ "${HESTIARE_SOURCE:-github}" = "gitea" ]; then
        latest=$(curl -fsSL "${curl_auth[@]}" "${HESTIARE_REPO_URL}/releases/latest" \
            | jq -r '.tag_name')
        tarball_url="${HESTIARE_REPO_URL}/releases/download/${latest}/hestiare-${latest}.tar.gz"
    else
        if [ "${HESTIARE_CHANNEL}" = "prerelease" ]; then
            latest=$(curl -fsSL "${GITHUB_API}/releases" | jq -r '.[0].tag_name')
        else
            latest=$(curl -fsSL "${GITHUB_API}/releases/latest" | jq -r '.tag_name')
        fi
        tarball_url="${GITHUB_RAW}/${latest}/hestiare-${latest}.tar.gz"
        curl_auth=()
    fi

    [ -n "$latest" ] || { echo "ERROR: Could not determine latest release." >&2; exit 1; }
    echo "[ * ] Version: ${latest}"

    curl -fsSL "${curl_auth[@]}" "${tarball_url}" -o /tmp/hestiare.tar.gz
    tar -xzf /tmp/hestiare.tar.gz -C /tmp
    rm /tmp/hestiare.tar.gz
    mkdir -p "${INSTALL_DIR}"
    cp -r /tmp/hestiare-${latest}/. "${INSTALL_DIR}/"
    rm -rf /tmp/hestiare-${latest}
    echo "[ * ] Extracted to ${INSTALL_DIR}"
}

# ════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════

main() {
    clear 2>/dev/null || true
    echo "========================================================================"
    echo " HestiaRE Installer"
    echo "========================================================================"
    echo ""

    fn_prerequisites
    echo "[ * ] OS: ${OS}"
    echo ""

    # Wizard: manifest-driven Q&A -> /etc/hestia/install.conf (separate process)
    bash "${INSTALL_DIR}/func/wizard.sh" --os="${OS}" ${FASTTRACK_PRESET:+--preset="${FASTTRACK_PRESET}"}

    # Seed /etc/hestia (env + hestia.conf) before any h-* command runs, so the
    # bootstrap-trap (func/main.sh sourcing hestia.env/hestia.conf at load) is a
    # non-issue. h-install-hestia then only validates these files exist.
    # shellcheck source=/usr/local/hestia/func/helper.sh
    HESTIA="${INSTALL_DIR}" source "${INSTALL_DIR}/func/helper.sh"
    HESTIA="${INSTALL_DIR}" seed_hestia_etc

    echo ""
    echo "========================================================================"
    echo " Starting installation..."
    echo "========================================================================"
    echo ""

    "${INSTALL_DIR}/bin/h-install-hestia"
}

main "$@"
