#!/bin/bash

set -euo pipefail

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

REPO="FalzoMAD/HestiaRE"
INSTALL_DIR="/usr/local/hestia-re"

# -- OS Check --------------------------------------------

if [ ! -f /etc/os-release ]; then
    echo "ERROR: Cannot determine OS. Aborting."
    exit 1
fi

source /etc/os-release

case "${ID}:${VERSION_ID}" in
    debian:12)   OS="debian-bookworm" ;;
    ubuntu:24.04) OS="ubuntu-noble"   ;;
    *)
        echo "ERROR: Unsupported OS: ${ID} ${VERSION_ID}"
        echo "Supported: Debian 12, Ubuntu 24.04"
        exit 1
        ;;
esac

echo "HestiaRE Installer"
echo "OS: ${ID} ${VERSION_ID} (${OS})"

# -- Dependencies ----------------------------------------

apt-get update -qq
apt-get install -y -qq curl make

# -- Fetch latest release --------------------------------

echo "Fetching latest release from GitHub..."

LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' | cut -d'"' -f4)

if [ -z "${LATEST}" ]; then
    echo "ERROR: Could not determine latest release."
    exit 1
fi

echo "Version: ${LATEST}"

URL="https://github.com/${REPO}/releases/download/${LATEST}/hestiare-${LATEST}.tar.gz"

curl -fsSL "${URL}" -o /tmp/hestiare.tar.gz
tar -xzf /tmp/hestiare.tar.gz -C /tmp
rm /tmp/hestiare.tar.gz

# -- Install ---------------------------------------------

mkdir -p "${INSTALL_DIR}"
cp -r /tmp/hestiare-${LATEST}/. "${INSTALL_DIR}/"

cd "${INSTALL_DIR}"
make install OS="${OS}"
