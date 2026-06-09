#!/bin/bash

# ======================================================== #
#
# HestiaRE Installer
# https://hestiare.com
#
# Supported:
#   Debian 12
#   Ubuntu 24.04
#
# ======================================================== #

set -euo pipefail

# -- Defaults --------------------------------------------

GITHUB_REPO="FalzoMAD/HestiaRE"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}"
GITHUB_RAW="https://github.com/${GITHUB_REPO}/releases/download"

SOURCE_CONF="/etc/hestia-re/source.conf"
INSTALL_DIR="/usr/local/hestia-re"
PROFILE="standard"
DEV_MODE=false

# -- Parse arguments -------------------------------------

for arg in "$@"; do
    case $arg in
        --dev)        DEV_MODE=true ;;
        --profile=*)  PROFILE="${arg#*=}" ;;
    esac
done

# -- Load source config if exists ------------------------

if [ -f "${SOURCE_CONF}" ]; then
    source "${SOURCE_CONF}"
fi

HESTIARE_SOURCE="${HESTIARE_SOURCE:-github}"
HESTIARE_REPO_URL="${HESTIARE_REPO_URL:-}"
HESTIARE_TOKEN="${HESTIARE_TOKEN:-}"
HESTIARE_CHANNEL="${HESTIARE_CHANNEL:-stable}"

# -- Dev mode: interactive setup -------------------------

if [ "${DEV_MODE}" = true ]; then
    echo ""
    echo "HestiaRE – Dev Setup"
    echo "--------------------"
    read -rp "Source repo URL [${HESTIARE_REPO_URL:-https://gitea.example.com/user/hestiare}]: " input_url
    HESTIARE_REPO_URL="${input_url:-$HESTIARE_REPO_URL}"

    read -rsp "Access token (silent): " input_token
    echo ""
    HESTIARE_TOKEN="${input_token:-$HESTIARE_TOKEN}"

    read -rp "Channel [stable/prerelease, default: stable]: " input_channel
    HESTIARE_CHANNEL="${input_channel:-stable}"

    HESTIARE_SOURCE="gitea"

    mkdir -p "$(dirname ${SOURCE_CONF})"
    cat > "${SOURCE_CONF}" << EOF
HESTIARE_SOURCE="${HESTIARE_SOURCE}"
HESTIARE_REPO_URL="${HESTIARE_REPO_URL}"
HESTIARE_TOKEN="${HESTIARE_TOKEN}"
HESTIARE_CHANNEL="${HESTIARE_CHANNEL}"
EOF
    chmod 600 "${SOURCE_CONF}"
    echo "Source config written to ${SOURCE_CONF}"
    echo ""
fi

# -- OS Check --------------------------------------------

if [ ! -f /etc/os-release ]; then
    echo "ERROR: Cannot determine OS. Aborting."
    exit 1
fi

source /etc/os-release

case "${ID}:${VERSION_ID}" in
    debian:12)    OS="debian-bookworm" ;;
    ubuntu:24.04) OS="ubuntu-noble"    ;;
    *)
        echo "ERROR: Unsupported OS: ${ID} ${VERSION_ID}"
        echo "Supported: Debian 12, Ubuntu 24.04"
        exit 1
        ;;
esac

echo "HestiaRE Installer"
echo "OS:      ${ID} ${VERSION_ID} (${OS})"
echo "Source:  ${HESTIARE_SOURCE}"
echo "Channel: ${HESTIARE_CHANNEL}"
echo ""

# -- Dependencies ----------------------------------------

apt-get update -qq
apt-get install -y -qq curl make

# -- Fetch latest release --------------------------------

echo "Fetching latest release..."

if [ "${HESTIARE_SOURCE}" = "gitea" ]; then
    AUTH_HEADER=""
    if [ -n "${HESTIARE_TOKEN}" ]; then
        AUTH_HEADER="-H \"Authorization: token ${HESTIARE_TOKEN}\""
    fi
    API_URL="${HESTIARE_REPO_URL}/releases/latest"
    LATEST=$(curl -fsSL ${AUTH_HEADER} "${API_URL}" \
        | grep '"tag_name"' | cut -d'"' -f4)
    TARBALL_URL="${HESTIARE_REPO_URL}/releases/download/${LATEST}/hestiare-${LATEST}.tar.gz"
    CURL_OPTS="-fsSL"
    if [ -n "${HESTIARE_TOKEN}" ]; then
        CURL_OPTS="${CURL_OPTS} -H \"Authorization: token ${HESTIARE_TOKEN}\""
    fi
else
    # GitHub
    if [ "${HESTIARE_CHANNEL}" = "prerelease" ]; then
        LATEST=$(curl -fsSL "${GITHUB_API}/releases" \
            | grep '"tag_name"' | head -n1 | cut -d'"' -f4)
    else
        LATEST=$(curl -fsSL "${GITHUB_API}/releases/latest" \
            | grep '"tag_name"' | cut -d'"' -f4)
    fi
    TARBALL_URL="${GITHUB_RAW}/${LATEST}/hestiare-${LATEST}.tar.gz"
    CURL_OPTS="-fsSL"
fi

if [ -z "${LATEST}" ]; then
    echo "ERROR: Could not determine latest release."
    exit 1
fi

echo "Version: ${LATEST}"

# -- Download & extract ----------------------------------

curl ${CURL_OPTS} "${TARBALL_URL}" -o /tmp/hestiare.tar.gz
tar -xzf /tmp/hestiare.tar.gz -C /tmp
rm /tmp/hestiare.tar.gz

# -- Install ---------------------------------------------

mkdir -p "${INSTALL_DIR}"
cp -r /tmp/hestiare-${LATEST}/. "${INSTALL_DIR}/"
rm -rf /tmp/hestiare-${LATEST}

cd "${INSTALL_DIR}"
make install OS="${OS}" PROFILE="${PROFILE}"
