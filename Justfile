# ======================================================== #
# HestiaRE Justfile — orchestrator
# Install logic lives in make/*.just
#
# Usage:
#   just install os=debian-bookworm [profile=standard]
#   just install os=debian-bookworm \
#        h_hostname=host.example.com h_admin=admin \
#        h_email=admin@host h_pass=secret
#   just add-tools [tools_set=hestia|sysadmin|full]
#   just update | check-updates | status
# ======================================================== #

set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet

# ── Paths ─────────────────────────────────────────────────
export HESTIA             := "/usr/local/hestia"
export CONF_DIR           := "/etc/hestia"
export INSTALL_CONF       := "/etc/hestia/install.conf"
export SOURCE_CONF        := "/etc/hestia/source.conf"
export LOG                := "/var/log/hestia/install.log"
export HESTIA_INSTALL_DIR := "/usr/local/hestia/install/deb"
export HESTIA_COMMON_DIR  := "/usr/local/hestia/install/common"

# ── Versions ──────────────────────────────────────────────
export MARIADB_VER        := "11.8"
export PHP_VER            := "8.3"
export MULTIPHP_VER       := "5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3 8.4 8.5"
export VERSION            := `cat /usr/local/hestia/VERSION 2>/dev/null || cat VERSION 2>/dev/null || echo "dev"`
export ARCH               := `uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'`

# ── Modules ───────────────────────────────────────────────
import 'make/configure.just'
import 'make/base.just'
import 'make/panel.just'
import 'make/web.just'
import 'make/db.just'
import 'make/mail.just'
import 'make/security.just'
import 'make/tools.just'

# ──────────────────────────────────────────────────────── #
# install — main entry point
# ──────────────────────────────────────────────────────── #

install os="unknown" profile="standard" h_hostname="" h_admin="" h_email="" h_pass="" tools_set="hestia":
    echo "========================================================================"
    echo " HestiaRE $VERSION"
    echo " OS:      {{os}}"
    echo " Profile: {{profile}}"
    echo "========================================================================"
    echo ""
    just _check-root '{{os}}'
    H_HOSTNAME='{{h_hostname}}' H_ADMIN='{{h_admin}}' H_EMAIL='{{h_email}}' H_PASS='{{h_pass}}' \
        just _collect-params '{{os}}' '{{profile}}'
    just _bootstrap-hestia-env
    just _init-hestia-structure
    just _install-base '{{os}}'
    just _install-panel
    just _install-web '{{os}}'
    just _install-db
    just '_profile-{{profile}}'
    just _install-security '{{profile}}'
    just _configure-hestia '{{os}}' '{{profile}}'
    just add-tools '{{tools_set}}'
    just _finalize

_profile-standard os="unknown":
    just _install-mail '{{os}}'

_profile-minimal:
    echo "[ * ] Minimal profile — skipping mail stack"

# ──────────────────────────────────────────────────────── #
# update / check-updates
# ──────────────────────────────────────────────────────── #

update: check-updates
    just _do-update

_do-update:
    source "$SOURCE_CONF" 2>/dev/null || true
    HESTIARE_SOURCE="${HESTIARE_SOURCE:-github}"
    HESTIARE_REPO_URL="${HESTIARE_REPO_URL:-}"
    HESTIARE_TOKEN="${HESTIARE_TOKEN:-}"
    HESTIARE_CHANNEL="${HESTIARE_CHANNEL:-stable}"
    GITHUB_REPO="FalzoMAD/HestiaRE"
    GITHUB_API="https://api.github.com/repos/$GITHUB_REPO"
    GITHUB_RAW="https://github.com/$GITHUB_REPO/releases/download"
    if [ "$HESTIARE_SOURCE" = "gitea" ]; then
        AUTH=""
        [ -n "$HESTIARE_TOKEN" ] && AUTH="-H \"Authorization: token $HESTIARE_TOKEN\""
        LATEST=$(curl -fsSL $AUTH "$HESTIARE_REPO_URL/releases/latest" \
            | grep '"tag_name"' | cut -d'"' -f4)
        URL="$HESTIARE_REPO_URL/releases/download/$LATEST/hestiare-$LATEST.tar.gz"
    else
        if [ "$HESTIARE_CHANNEL" = "prerelease" ]; then
            LATEST=$(curl -fsSL "$GITHUB_API/releases" \
                | grep '"tag_name"' | head -n1 | cut -d'"' -f4)
        else
            LATEST=$(curl -fsSL "$GITHUB_API/releases/latest" \
                | grep '"tag_name"' | cut -d'"' -f4)
        fi
        URL="$GITHUB_RAW/$LATEST/hestiare-$LATEST.tar.gz"
    fi
    echo "Updating to $LATEST..."
    curl -fsSL "$URL" -o /tmp/hestiare-update.tar.gz
    tar -xzf /tmp/hestiare-update.tar.gz -C /tmp
    rm /tmp/hestiare-update.tar.gz
    cp -r /tmp/hestiare-$LATEST/. "$HESTIA/"
    rm -rf /tmp/hestiare-$LATEST
    echo "Update complete."

check-updates:
    source "$SOURCE_CONF" 2>/dev/null || true
    HESTIARE_SOURCE="${HESTIARE_SOURCE:-github}"
    HESTIARE_REPO_URL="${HESTIARE_REPO_URL:-}"
    HESTIARE_TOKEN="${HESTIARE_TOKEN:-}"
    HESTIARE_CHANNEL="${HESTIARE_CHANNEL:-stable}"
    GITHUB_REPO="FalzoMAD/HestiaRE"
    GITHUB_API="https://api.github.com/repos/$GITHUB_REPO"
    echo "Checking for updates..."
    if [ "$HESTIARE_SOURCE" = "gitea" ]; then
        AUTH=""
        [ -n "$HESTIARE_TOKEN" ] && AUTH="-H \"Authorization: token $HESTIARE_TOKEN\""
        LATEST=$(curl -fsSL $AUTH "$HESTIARE_REPO_URL/releases/latest" \
            | grep '"tag_name"' | cut -d'"' -f4)
    else
        LATEST=$(curl -fsSL "$GITHUB_API/releases/latest" \
            | grep '"tag_name"' | cut -d'"' -f4)
    fi
    echo "Installed: $VERSION"
    echo "Available: $LATEST"
    if [ "$LATEST" = "v$VERSION" ] || [ "$LATEST" = "$VERSION" ]; then
        echo "Already up to date."
    else
        echo "Update available: $LATEST"
    fi

# ──────────────────────────────────────────────────────── #
# status / backup / uninstall
# ──────────────────────────────────────────────────────── #

status:
    source "$INSTALL_CONF" 2>/dev/null || true
    source "$SOURCE_CONF"  2>/dev/null || true
    echo "HestiaRE $VERSION"
    echo "Source:   ${HESTIARE_SOURCE:-github}"
    echo "Channel:  ${HESTIARE_CHANNEL:-stable}"
    echo "OS:       ${INSTALL_OS:-unknown}"
    echo "Profile:  ${INSTALL_PROFILE:-unknown}"
    echo ""
    echo "Completed install phases:"
    for s in "$CONF_DIR"/.done.*; do
        [ -f "$s" ] && echo "  + ${s##*/.done.}" || true
    done
    echo ""
    echo "Installed components:"
    grep '^COMPONENT_' "$INSTALL_CONF" 2>/dev/null | sed 's/^/  /' || echo "  (install.conf not found)"

backup:
    echo "HestiaRE — backup placeholder"

uninstall:
    echo "========================================================================"
    echo " HestiaRE Uninstall"
    echo "========================================================================"
    echo ""
    read -p "This will remove HestiaRE. Are you sure? [y/N] " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Aborted."
        exit 1
    fi
    echo "Uninstall placeholder — nothing removed yet."
    echo ""
    echo "Done."
