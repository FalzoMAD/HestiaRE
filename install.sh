#!/bin/bash

# ======================================================== #
#
# HestiaRE Installer — Interactive Configuration Wizard
#
# This script is the sole interactive layer.
# It collects all install parameters and writes:
#   /etc/hestia/install.conf
#
# Then run:
#   cd /usr/local/hestia && just install
#
# Usage:
#   bash install.sh                  # full interactive wizard
#   bash install.sh <preset>         # fasttrack: skip component questions
#   bash install.sh --dev            # configure private source first
#   bash install.sh --profile=<p>    # same as positional preset arg
#
# Supported OS:
#   Debian 12 (bookworm), Ubuntu 24.04 LTS (noble)
#
# ======================================================== #

set -euo pipefail

# ── Constants ──────────────────────────────────────────────
INSTALL_CONF="/etc/hestia/install.conf"
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
HAS_WHIPTAIL=false
OS=""
INSTALL_PROFILE=""
FASTTRACK_PRESET=""
DEV_MODE=false
PHP_VERSIONS_AVAILABLE=""
OS_MARIADB_VERSION=""
TOOLS_SELECTION=""
declare -A COMP_VALUES

# ── Argument parsing ───────────────────────────────────────
for _arg in "$@"; do
    case $_arg in
        --dev)       DEV_MODE=true ;;
        --profile=*) FASTTRACK_PRESET="${_arg#*=}" ;;
        -*)          ;;
        *)           [ -z "$FASTTRACK_PRESET" ] && FASTTRACK_PRESET="$_arg" ;;
    esac
done

# ── NEWT_COLORS branding ───────────────────────────────────
export NEWT_COLORS='
root=,black
window=white,black
border=green,black
title=green,black
button=black,green
actbutton=black,cyan
checkbox=white,black
actcheckbox=black,green
entry=white,black
listbox=white,black
actlistbox=black,green
compactbutton=black,green
label=white,black
'

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
    echo "[ * ] Installing prerequisites (curl, just, jq, whiptail)..."
    DEBIAN_FRONTEND=noninteractive apt-get -qq update
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq install curl just jq whiptail >> "$LOG_DIR/install.log" 2>&1

    # Use whiptail only when it's available AND running in a real interactive terminal.
    # Fallback to plain bash if terminal is dumb, stdin is a pipe, or TERM is unset —
    # e.g. curl | bash installs, serial consoles, or minimal container environments.
    if command -v whiptail >/dev/null 2>&1 \
        && [ -t 0 ] \
        && [ "${TERM:-}" != "dumb" ] \
        && [ -n "${TERM:-}" ]; then
        HAS_WHIPTAIL=true
    fi

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
# Manifest
# ════════════════════════════════════════════════════════════

fn_manifest_load() {
    [ -f "$MANIFEST" ] || {
        echo "ERROR: Manifest not found at $MANIFEST" >&2
        echo "       Run install.sh after extracting a release." >&2
        exit 1
    }
    jq empty "$MANIFEST" 2>/dev/null || {
        echo "ERROR: $MANIFEST is not valid JSON" >&2; exit 1
    }
    # Schema sanity check: required top-level fields must exist with the right
    # type. Without this a missing key would silently yield empty values via jq.
    local missing
    missing=$(jq -r '
        . as $root
        | [ ({presets:"object",components:"object",tools:"object",pre_questions:"array",always_installed_packages:"array"}
            | to_entries[])
          | .key as $k | .value as $t
          | if ($root | has($k) | not) then "\($k): fehlt"
            elif (($root[$k]) | type) != $t then "\($k): falscher Typ (erwartet \($t))"
            else empty end ]
        | join("; ")
    ' "$MANIFEST")
    [ -z "$missing" ] || {
        echo "ERROR: $MANIFEST ist unvollstaendig oder hat eine falsche Struktur:" >&2
        echo "       $missing" >&2
        exit 1
    }
}

mq() { jq -r "$@" "$MANIFEST"; }

# ════════════════════════════════════════════════════════════
# TUI helpers — whiptail with bash fallback
# ════════════════════════════════════════════════════════════

_wt_inputbox() {
    local title="$1" prompt="$2" default="$3"
    if [ "$HAS_WHIPTAIL" = true ]; then
        whiptail --title "$title" --inputbox "$prompt" 10 60 "$default" \
            3>&1 1>&2 2>&3 3>&-
    else
        printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
        read -r _i < /dev/tty
        echo "${_i:-$default}"
    fi
}

_wt_menu() {
    # args: title text [tag desc] ...
    local title="$1" text="$2"
    shift 2
    local -a items=("$@")
    if [ "$HAS_WHIPTAIL" = true ]; then
        whiptail --title "$title" --menu "$text" 20 72 10 "${items[@]}" \
            3>&1 1>&2 2>&3 3>&-
    else
        echo "" > /dev/tty
        echo "$text" > /dev/tty
        local -a tags=()
        local i=0
        while [ $i -lt ${#items[@]} ]; do
            local tag="${items[$i]}"
            local desc="${items[$((i+1))]}"
            tags+=("$tag")
            printf '  %d) %-12s  %s\n' "${#tags[@]}" "$tag" "$desc" > /dev/tty
            i=$((i+2))
        done
        printf 'Choice [1]: ' > /dev/tty
        read -r _i < /dev/tty
        local idx=$((_i > 0 ? _i - 1 : 0))
        echo "${tags[$idx]:-${tags[0]}}"
    fi
}

_wt_radiolist() {
    # args: title text [tag desc ON/OFF] ...
    local title="$1" text="$2"
    shift 2
    local -a items=("$@")
    local list_h=$(( ${#items[@]} / 3 ))
    [ $list_h -gt 14 ] && list_h=14
    [ $list_h -lt 3 ]  && list_h=3
    local win_h=$(( list_h + 8 ))
    if [ "$HAS_WHIPTAIL" = true ]; then
        whiptail --title "$title" --radiolist "$text" "$win_h" 72 "$list_h" "${items[@]}" \
            3>&1 1>&2 2>&3 3>&-
    else
        echo "" > /dev/tty
        echo "$text" > /dev/tty
        local -a tags=()
        local default_val=""
        local i=0
        while [ $i -lt ${#items[@]} ]; do
            local tag="${items[$i]}"
            local desc="${items[$((i+1))]}"
            local state="${items[$((i+2))]}"
            tags+=("$tag")
            [ "$state" = "ON" ] && default_val="$tag"
            local marker="  "; [ "$state" = "ON" ] && marker="(*)"
            printf '  %s %d) %s\n' "$marker" "${#tags[@]}" "$tag" > /dev/tty
            i=$((i+3))
        done
        printf 'Choice [%s]: ' "${default_val}" > /dev/tty
        read -r _i < /dev/tty
        if [[ "$_i" =~ ^[0-9]+$ ]] && [ "$_i" -ge 1 ] && [ "$_i" -le "${#tags[@]}" ]; then
            echo "${tags[$((_i-1))]}"
        else
            echo "${_i:-$default_val}"
        fi
    fi
}

_wt_checklist() {
    # args: title text [tag desc ON/OFF] ...
    local title="$1" text="$2"
    shift 2
    local -a items=("$@")
    local list_h=$(( ${#items[@]} / 3 ))
    [ $list_h -gt 14 ] && list_h=14
    [ $list_h -lt 3 ]  && list_h=3
    local win_h=$(( list_h + 8 ))
    if [ "$HAS_WHIPTAIL" = true ]; then
        whiptail --title "$title" --checklist "$text" "$win_h" 72 "$list_h" "${items[@]}" \
            3>&1 1>&2 2>&3 3>&- || true
    else
        echo "" > /dev/tty
        echo "$text" > /dev/tty
        local -a tags=()
        local -a defaults=()
        local i=0
        while [ $i -lt ${#items[@]} ]; do
            local tag="${items[$i]}"
            local desc="${items[$((i+1))]}"
            local state="${items[$((i+2))]}"
            tags+=("$tag")
            [ "$state" = "ON" ] && defaults+=("$tag")
            local marker="[ ]"; [ "$state" = "ON" ] && marker="[x]"
            printf '  %s %d) %s\n' "$marker" "${#tags[@]}" "$tag" > /dev/tty
            i=$((i+3))
        done
        printf '  Pre-selected: %s\n' "${defaults[*]:-none}" > /dev/tty
        printf '  Enter space-separated numbers or names to toggle (Enter = accept): ' > /dev/tty
        read -r _i < /dev/tty
        if [ -z "$_i" ]; then
            echo "${defaults[*]:-}"
        else
            echo "$_i"
        fi
    fi
}

# ════════════════════════════════════════════════════════════
# Pre-questions (before preset, always asked)
# ════════════════════════════════════════════════════════════

fn_ask_pre_questions() {
    local default_host
    default_host=$(hostname --fqdn 2>/dev/null || hostname 2>/dev/null || echo "server.example.com")

    HESTIA_HOSTNAME=$(_wt_inputbox "HestiaRE Setup (1/4)" "Hostname (FQDN):" "$default_host")
    HESTIA_PANEL_PORT=$(_wt_inputbox "HestiaRE Setup (2/4)" "Panel port:" "8083")
    HESTIA_ADMIN=$(_wt_inputbox "HestiaRE Setup (3/4)" "Admin username:" "admin")
    HESTIA_EMAIL=$(_wt_inputbox "HestiaRE Setup (4/4)" "Admin email:" "admin@${HESTIA_HOSTNAME}")

    [ -n "$HESTIA_HOSTNAME" ]   || { echo "ERROR: Hostname is required." >&2; exit 1; }
    [ -n "$HESTIA_ADMIN" ]      || { echo "ERROR: Admin username is required." >&2; exit 1; }
    [ -n "$HESTIA_EMAIL" ]      || { echo "ERROR: Admin email is required." >&2; exit 1; }
    [[ "$HESTIA_PANEL_PORT" =~ ^[0-9]+$ ]] || { echo "ERROR: Panel port must be a number." >&2; exit 1; }
}

# ════════════════════════════════════════════════════════════
# Preset selection
# ════════════════════════════════════════════════════════════

fn_ask_preset() {
    if [ -n "$FASTTRACK_PRESET" ]; then
        INSTALL_PROFILE="$FASTTRACK_PRESET"
        local valid
        valid=$(mq --arg p "$FASTTRACK_PRESET" '.presets | has($p) | tostring')
        [ "$valid" = "true" ] || {
            echo "ERROR: Unknown preset '$INSTALL_PROFILE'" >&2
            echo "Valid presets: $(mq '.presets | keys | join(", ")')" >&2
            exit 1
        }
        if [ "$INSTALL_PROFILE" = "custom" ]; then
            # 'custom' is interactive-only: the preset is fixed by the argument,
            # but every component is asked with no preselection. Clearing the
            # fasttrack flag routes us into the full interactive component loop
            # while skipping the preset-selection menu (custom is already set).
            FASTTRACK_PRESET=""
            echo "[ * ] Preset 'custom' — full interactive configuration (no defaults)"
            return
        fi
        echo "[ * ] Fasttrack preset: $INSTALL_PROFILE"
        return
    fi

    local -a items=()
    while IFS=$'\t' read -r key label; do
        items+=("$key" "$label")
    done < <(mq '.presets | to_entries[] | [.key, .value.label] | @tsv')

    INSTALL_PROFILE=$(_wt_menu "HestiaRE — Preset" "Select installation preset:" "${items[@]}")
    [ -n "$INSTALL_PROFILE" ] || { echo "ERROR: No preset selected." >&2; exit 1; }
}

# ════════════════════════════════════════════════════════════
# Dynamic version discovery (runs after preset is known)
# ════════════════════════════════════════════════════════════

fn_discover_php_versions() {
    echo "[ * ] Adding Sury PHP repository for version discovery..."
    local codename
    codename=$(. /etc/os-release; echo "$VERSION_CODENAME")
    curl -fsSL https://packages.sury.org/php/apt.gpg \
        | gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-php.gpg
    printf 'deb https://packages.sury.org/php/ %s main\n' "$codename" \
        > /etc/apt/sources.list.d/sury-php.list
    DEBIAN_FRONTEND=noninteractive apt-get -qq update >> "$LOG_DIR/install.log" 2>&1

    # Enumerate every PHP version Sury actually ships by listing package names
    # matching phpX.Y-common / phpX.Y-fpm. The old approach queried only the
    # `php` metapackage (a single candidate) and used a start-anchored regex
    # that failed on Sury's epoch-prefixed versions (e.g. "2:8.3"). The version
    # is now extracted unanchored from the package name itself.
    PHP_VERSIONS_AVAILABLE=$(apt-cache pkgnames php 2>/dev/null \
        | grep -E '^php[0-9]+\.[0-9]+-(common|fpm)$' \
        | grep -oE '[0-9]+\.[0-9]+' \
        | sort -Vr \
        | uniq \
        | tr '\n' ' ' \
        | sed 's/ $//')

    [ -n "$PHP_VERSIONS_AVAILABLE" ] || {
        echo "[ ! ] Sury version discovery failed — using built-in fallback list" >&2
        PHP_VERSIONS_AVAILABLE="8.5 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0 5.6"
    }
    echo "[ * ] Available PHP versions: $PHP_VERSIONS_AVAILABLE"
}

fn_discover_mariadb_version() {
    local ver=""
    # Try apt-cache policy first (works without external repos)
    ver=$(apt-cache policy mariadb-server 2>/dev/null \
        | grep -i 'Kandidat\|Candidate' \
        | awk '{print $2}' \
        | grep -oE '^[0-9]+:[0-9]+\.[0-9]+|^[0-9]+\.[0-9]+' \
        | grep -oE '[0-9]+\.[0-9]+' \
        | head -n1 || true)
    # Fallback: apt-cache madison
    if [ -z "$ver" ]; then
        ver=$(apt-cache madison mariadb-server 2>/dev/null \
            | awk '{print $3}' \
            | head -n1 \
            | grep -oE '[0-9]+\.[0-9]+' || true)
    fi
    OS_MARIADB_VERSION="${ver:-10.11}"
    echo "[ * ] OS MariaDB version: $OS_MARIADB_VERSION"
}

fn_pre_discovery() {
    # Determine the effective PHP_MODE for the preset (fn_component_default
    # already honours fixed_no_prompt) to know whether the Sury repo is needed.
    # For 'custom' this is empty here; discovery then runs lazily once the user
    # actually picks sury_multi (see _ask_checklist).
    local php_mode
    php_mode=$(fn_component_default PHP_MODE "$INSTALL_PROFILE")

    if [ "$php_mode" = "sury_multi" ]; then
        fn_discover_php_versions
    fi

    fn_discover_mariadb_version
}

# ════════════════════════════════════════════════════════════
# default_rule — PHP version selection
# ════════════════════════════════════════════════════════════

fn_apply_default_rule() {
    # $1: rule (e.g. "skip_newest:1,take:3" or "take_newest:2")
    # $2: space-separated versions sorted newest-first
    local rule="$1"
    local -a versions
    read -ra versions <<< "$2"
    local -a result=()

    if [[ "$rule" =~ ^skip_newest:([0-9]+),take:([0-9]+)$ ]]; then
        local skip="${BASH_REMATCH[1]}" take="${BASH_REMATCH[2]}"
        local -a rem=("${versions[@]:$skip}")
        result=("${rem[@]:0:$take}")
    elif [[ "$rule" =~ ^take_newest:([0-9]+)$ ]]; then
        local take="${BASH_REMATCH[1]}"
        result=("${versions[@]:0:$take}")
    fi

    echo "${result[*]:-}"
}

# ════════════════════════════════════════════════════════════
# Component helpers
# ════════════════════════════════════════════════════════════

fn_component_default() {
    # Returns the effective default for component $1 under preset $2.
    # Distinguishes boolean false / null / missing key explicitly so an
    # intentional "false" survives (jq's `// empty` treats false as empty too).
    local id="$1" preset="$2"
    jq -r --arg id "$id" --arg preset "$preset" '
      .components[$id] as $c |
      if ($c.fixed_no_prompt // {} | has($preset)) then
        $c.fixed_no_prompt[$preset] | tostring
      elif ($c.default | type) == "object" then
        (if ($c.default | has($preset)) and ($c.default[$preset] != null)
         then $c.default[$preset] | tostring
         else "" end)
      elif ($c.default != null) then
        $c.default | tostring
      else
        ""
      end
    ' "$MANIFEST"
}

fn_eval_condition() {
    # Evaluates "KEY OP VALUE" against COMP_VALUES associative array (by nameref)
    local cond="$1"
    local -n _cv="$2"
    local key op val
    read -r key op val <<< "$cond"
    local actual="${_cv[$key]:-}"

    case "$op" in
        "==")
            [ "$actual" = "$val" ] && echo "true" || echo "false"
            ;;
        "!=")
            if [ "$val" = "null" ]; then
                # "!= null" means the component has a non-empty value
                [ -n "$actual" ] && [ "$actual" != "null" ] && [ "$actual" != "false" ] \
                    && echo "true" || echo "false"
            else
                [ "$actual" != "$val" ] && echo "true" || echo "false"
            fi
            ;;
        *)
            echo "true"
            ;;
    esac
}

# ════════════════════════════════════════════════════════════
# Shared value helpers (used by both interactive and fasttrack)
# ════════════════════════════════════════════════════════════

fn_resolve_version_value() {
    # Translates the __os__ placeholder to the discovered OS version, so
    # install.conf always holds a real version number — never "__os__".
    # Shared by the interactive version_select dialog and the fasttrack path.
    local val="$1"
    if [ "$val" = "__os__" ]; then
        [ -n "$OS_MARIADB_VERSION" ] || fn_discover_mariadb_version
        printf '%s' "$OS_MARIADB_VERSION"
    else
        printf '%s' "$val"
    fi
}

fn_normalize_list() {
    # Normalizes a checklist selection into one canonical format regardless of
    # source: whiptail emits quoted, space-separated tags ("8.4" "8.3"); the
    # bash fallback emits bare tokens. Output is space-separated, unquoted,
    # de-duplicated, order preserved — trivially re-readable via a word-split.
    local raw="${1//\"/}"
    local -a parts=()
    local p s dup
    for p in $raw; do
        [ -n "$p" ] || continue
        dup=0
        for s in "${parts[@]:-}"; do [ "$s" = "$p" ] && { dup=1; break; }; done
        if [ "$dup" -eq 0 ]; then parts+=("$p"); fi
    done
    printf '%s' "${parts[*]:-}"
}

fn_tools_default_for_preset() {
    # Sets TOOLS_SELECTION to the manifest tool defaults for the current preset
    # without prompting (used by the fasttrack path).
    local -a defs=()
    readarray -t defs < <(mq --arg p "$INSTALL_PROFILE" '.tools.selection.default[$p][]? // empty')
    TOOLS_SELECTION=$(fn_normalize_list "${defs[*]:-}")
}

# ════════════════════════════════════════════════════════════
# Component question dispatchers
# ════════════════════════════════════════════════════════════

_ask_radio() {
    local id="$1" question="$2" default_val="$3"
    local -a opts=()
    readarray -t opts < <(mq --arg id "$id" '.components[$id].options[]')
    local -a items=()
    for opt in "${opts[@]}"; do
        local state="OFF"
        [ "$opt" = "$default_val" ] && state="ON"
        items+=("$opt" "$opt" "$state")
    done
    COMP_VALUES["$id"]=$(_wt_radiolist "HestiaRE — $id" "$question" "${items[@]}")
}

_ask_checkbox() {
    local id="$1" question="$2" default_val="$3"
    local state="OFF"
    [ "$default_val" = "true" ] && state="ON"
    if [ "$HAS_WHIPTAIL" = true ]; then
        local result
        result=$(whiptail --title "HestiaRE — $id" --checklist \
            "$question" 10 60 1 "$id" "" "$state" \
            3>&1 1>&2 2>&3 3>&- || true)
        if echo "$result" | grep -q "$id"; then
            COMP_VALUES["$id"]="true"
        else
            COMP_VALUES["$id"]="false"
        fi
    else
        local yn_default; [ "$state" = "ON" ] && yn_default="y" || yn_default="n"
        printf '%s [y/n, default: %s]: ' "$question" "$yn_default" > /dev/tty
        read -r _yn < /dev/tty
        case "${_yn:-}" in
            [yY]*) COMP_VALUES["$id"]="true"  ;;
            [nN]*) COMP_VALUES["$id"]="false" ;;
            *)     COMP_VALUES["$id"]="$([ "$state" = "ON" ] && echo true || echo false)" ;;
        esac
    fi
}

_ask_checklist() {
    local id="$1" question="$2" default_val="$3"
    local dynamic_source
    dynamic_source=$(mq --arg id "$id" '.components[$id].dynamic_source // empty')
    local -a all_opts=()
    local -a default_opts=()

    if [ "$dynamic_source" = "sury_repo_metadata" ]; then
        [ -n "$PHP_VERSIONS_AVAILABLE" ] || fn_discover_php_versions
        read -ra all_opts <<< "$PHP_VERSIONS_AVAILABLE"
        local rule
        rule=$(mq --arg id "$id" --arg p "$INSTALL_PROFILE" \
            '.components[$id].default_rule[$p] // empty')
        if [ -n "$rule" ] && [ "$rule" != "null" ]; then
            local selected
            selected=$(fn_apply_default_rule "$rule" "$PHP_VERSIONS_AVAILABLE")
            [ -n "$selected" ] && read -ra default_opts <<< "$selected"
        fi
    else
        readarray -t all_opts < <(mq --arg id "$id" '.components[$id].options[]? // empty')
        if [ -n "$default_val" ] && [ "$default_val" != "null" ]; then
            readarray -t default_opts < <(
                echo "$default_val" | jq -r '.[]?' 2>/dev/null \
                    || echo "$default_val" | tr ' ' '\n'
            )
        fi
    fi

    local -a items=()
    for opt in "${all_opts[@]}"; do
        local state="OFF"
        for d in "${default_opts[@]}"; do
            [ "$d" = "$opt" ] && state="ON" && break
        done
        items+=("$opt" "$opt" "$state")
    done

    local selected
    selected=$(_wt_checklist "HestiaRE — $id" "$question" "${items[@]}")
    COMP_VALUES["$id"]=$(fn_normalize_list "$selected")
}

_ask_version_select() {
    local id="$1" question="$2" default_val="$3"
    [ -n "$OS_MARIADB_VERSION" ] || fn_discover_mariadb_version

    local -a items=()
    while IFS=$'\t' read -r value source label_tmpl; do
        local display_val display_label state="OFF"
        if [ "$value" = "__os__" ]; then
            display_val=$(fn_resolve_version_value "$value")
            display_label="${label_tmpl/\{version\}/$OS_MARIADB_VERSION}"
            [ "$default_val" = "__os__" ] && state="ON"
        else
            display_val="$value"
            display_label="$value ($source)"
            [ "$default_val" = "$value" ] && state="ON"
        fi
        items+=("$display_val" "$display_label" "$state")
    done < <(mq --arg id "$id" \
        '.components[$id].options[] | [.value, .source, (.label_template // "")] | @tsv')

    COMP_VALUES["$id"]=$(_wt_radiolist "HestiaRE — $id" "$question" "${items[@]}")
}

_ask_tools_selection() {
    local followup_id="$1"
    local question
    question=$(mq '.tools.selection.question')
    local -a all_opts=()
    readarray -t _vorbelegt < <(mq '.tools.selection.options.vorbelegt[]')
    readarray -t _unbelegt  < <(mq '.tools.selection.options.unbelegt[]')
    all_opts=("${_vorbelegt[@]}" "${_unbelegt[@]}")

    local -a default_tools=()
    readarray -t default_tools < <(mq --arg p "$INSTALL_PROFILE" \
        '.tools.selection.default[$p][]? // empty')

    local -a items=()
    for opt in "${all_opts[@]}"; do
        local state="OFF"
        for d in "${default_tools[@]}"; do
            [ "$d" = "$opt" ] && state="ON" && break
        done
        items+=("$opt" "$opt" "$state")
    done

    local _sel
    _sel=$(_wt_checklist "HestiaRE — Tools" "$question" "${items[@]}")
    TOOLS_SELECTION=$(fn_normalize_list "$_sel")
}

# ════════════════════════════════════════════════════════════
# Fasttrack value derivation (no prompts)
# ════════════════════════════════════════════════════════════

fn_fasttrack_value() {
    # Derives a component's value for the fasttrack path the same way the
    # interactive path would default it — honouring visibility, dynamic PHP
    # version rules, the __os__ placeholder and the tools follow-up — but
    # without ever prompting. Mirrors fn_ask_components so both paths agree.
    local id="$1" type="$2"

    # Respect visibility so hidden components stay empty, exactly like interactive.
    local cond
    cond=$(mq --arg id "$id" '.components[$id].visible_if // empty')
    if [ -n "$cond" ] && [ "$(fn_eval_condition "$cond" COMP_VALUES)" = "false" ]; then
        COMP_VALUES["$id"]=""; return
    fi
    cond=$(mq --arg id "$id" '.components[$id].dependent_on // empty')
    if [ -n "$cond" ] && [ "$(fn_eval_condition "$cond" COMP_VALUES)" = "false" ]; then
        COMP_VALUES["$id"]=""; return
    fi

    case "$type" in
        checklist)
            local dyn
            dyn=$(mq --arg id "$id" '.components[$id].dynamic_source // empty')
            if [ "$dyn" = "sury_repo_metadata" ]; then
                [ -n "$PHP_VERSIONS_AVAILABLE" ] || fn_discover_php_versions
                local rule sel=""
                rule=$(mq --arg id "$id" --arg p "$INSTALL_PROFILE" \
                    '.components[$id].default_rule[$p] // empty')
                if [ -n "$rule" ] && [ "$rule" != "null" ]; then
                    sel=$(fn_apply_default_rule "$rule" "$PHP_VERSIONS_AVAILABLE")
                fi
                COMP_VALUES["$id"]=$(fn_normalize_list "$sel")
            else
                COMP_VALUES["$id"]=$(fn_normalize_list "$(fn_component_default "$id" "$INSTALL_PROFILE")")
            fi
            ;;
        version_select)
            COMP_VALUES["$id"]=$(fn_resolve_version_value "$(fn_component_default "$id" "$INSTALL_PROFILE")")
            ;;
        *)
            COMP_VALUES["$id"]=$(fn_component_default "$id" "$INSTALL_PROFILE")
            ;;
    esac

    # opens_followup: pull in the preset's tool defaults without prompting.
    local followup
    followup=$(mq --arg id "$id" '.components[$id].opens_followup // empty')
    if [ -n "$followup" ] && [ "${COMP_VALUES[$id]:-}" = "true" ]; then
        fn_tools_default_for_preset
    fi
}

# ════════════════════════════════════════════════════════════
# Main component loop
# ════════════════════════════════════════════════════════════

fn_ask_components() {
    local -a ids=()
    readarray -t ids < <(mq '.components | keys_unsorted[]')

    for id in "${ids[@]}"; do
        local type
        type=$(mq --arg id "$id" '.components[$id].type')

        # fixed: always installed, no question
        if [ "$type" = "fixed" ]; then
            COMP_VALUES["$id"]="true"
            continue
        fi

        # implicit: derived from preset, normally no question.
        # Exception: under 'custom' the preset default is null, so an implicit
        # component that defines options (PHP_MODE, MAIL_BLOCK_PRESENT,
        # WEB_REPO_SOURCE) is asked as a real question with no preselection —
        # otherwise its dependent questions could never become visible.
        if [ "$type" = "implicit" ]; then
            local idefault
            idefault=$(fn_component_default "$id" "$INSTALL_PROFILE")
            if [ "$INSTALL_PROFILE" = "custom" ] && [ -z "$idefault" ] \
               && [ "$(mq --arg id "$id" '.components[$id] | has("options") | tostring')" = "true" ]; then
                local iq
                iq=$(mq --arg id "$id" '.components[$id].question // $id')
                _ask_radio "$id" "$iq" ""
            else
                COMP_VALUES["$id"]="$idefault"
            fi
            continue
        fi

        # Fasttrack: derive the value from the preset, no interaction.
        if [ -n "$FASTTRACK_PRESET" ]; then
            fn_fasttrack_value "$id" "$type"
            continue
        fi

        # Check fixed_no_prompt for this preset
        local fixed
        fixed=$(mq --arg id "$id" --arg p "$INSTALL_PROFILE" \
            '.components[$id].fixed_no_prompt[$p] // empty')
        if [ -n "$fixed" ]; then
            COMP_VALUES["$id"]="$fixed"
            continue
        fi

        # Check visible_if
        local visible_if
        visible_if=$(mq --arg id "$id" '.components[$id].visible_if // empty')
        if [ -n "$visible_if" ]; then
            local vis
            vis=$(fn_eval_condition "$visible_if" COMP_VALUES)
            if [ "$vis" = "false" ]; then
                COMP_VALUES["$id"]=""
                continue
            fi
        fi

        # Check dependent_on
        local dep_on
        dep_on=$(mq --arg id "$id" '.components[$id].dependent_on // empty')
        if [ -n "$dep_on" ]; then
            local dep_met
            dep_met=$(fn_eval_condition "$dep_on" COMP_VALUES)
            if [ "$dep_met" = "false" ]; then
                COMP_VALUES["$id"]=""
                continue
            fi
        fi

        local question default_val
        question=$(mq --arg id "$id" '.components[$id].question // $id')
        # Default comes solely from the manifest. DB_PHPMYADMIN/DB_PGADMIN now
        # carry explicit per-preset defaults and fn_component_default preserves
        # boolean false, so the interactive and fasttrack paths share identical
        # defaults (no interactive-only fallback that would diverge from fasttrack).
        default_val=$(fn_component_default "$id" "$INSTALL_PROFILE")

        case "$type" in
            radio)          _ask_radio          "$id" "$question" "$default_val" ;;
            checkbox)       _ask_checkbox       "$id" "$question" "$default_val" ;;
            checklist)      _ask_checklist      "$id" "$question" "$default_val" ;;
            version_select) _ask_version_select "$id" "$question" "$default_val" ;;
        esac

        # opens_followup: ADDON_UTILITIES → TOOLS_SELECTION
        local followup
        followup=$(mq --arg id "$id" '.components[$id].opens_followup // empty')
        if [ -n "$followup" ] && [ "${COMP_VALUES[$id]:-}" = "true" ]; then
            _ask_tools_selection "$followup"
        fi
    done
}

# ════════════════════════════════════════════════════════════
# Write install.conf
# ════════════════════════════════════════════════════════════

fn_write_install_conf() {
    mkdir -p "$(dirname "$INSTALL_CONF")"
    chmod 700 "$(dirname "$INSTALL_CONF")"

    local ids=()
    readarray -t ids < <(mq '.components | keys_unsorted[]')

    {
        echo "# HestiaRE install.conf"
        echo "# Written by install.sh — do not edit manually."
        echo "# Re-run install.sh to change parameters."
        echo ""
        echo "HESTIA_HOSTNAME=\"${HESTIA_HOSTNAME}\""
        echo "HESTIA_PANEL_PORT=\"${HESTIA_PANEL_PORT}\""
        echo "HESTIA_ADMIN=\"${HESTIA_ADMIN}\""
        echo "HESTIA_EMAIL=\"${HESTIA_EMAIL}\""
        echo "INSTALL_OS=\"${OS}\""
        echo "INSTALL_PROFILE=\"${INSTALL_PROFILE}\""
        echo ""
        echo "# Components"
        for id in "${ids[@]}"; do
            echo "COMPONENT_${id}=\"${COMP_VALUES[$id]:-}\""
        done
        echo ""
        echo "# Selected utilities (from tools checklist)"
        echo "TOOLS_SELECTION=\"${TOOLS_SELECTION:-}\""
        echo ""
        echo "# Always-installed packages"
        local pkgs
        pkgs=$(mq '.always_installed_packages | join(" ")')
        echo "ALWAYS_INSTALLED_PACKAGES=\"${pkgs}\""
    } > "$INSTALL_CONF"

    chmod 600 "$INSTALL_CONF"
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

    fn_manifest_load
    fn_ask_pre_questions
    fn_ask_preset
    fn_pre_discovery
    fn_ask_components
    fn_write_install_conf

    clear 2>/dev/null || true
    echo "========================================================================"
    echo " Configuration complete"
    echo "========================================================================"
    echo ""
    echo "  Hostname : ${HESTIA_HOSTNAME}"
    echo "  Port     : ${HESTIA_PANEL_PORT}"
    echo "  Admin    : ${HESTIA_ADMIN} <${HESTIA_EMAIL}>"
    echo "  Profile  : ${INSTALL_PROFILE}"
    echo "  OS       : ${OS}"
    echo ""
    echo "  install.conf written to: ${INSTALL_CONF}"
    echo ""
    echo "========================================================================"
    echo " Starting installation..."
    echo "========================================================================"
    echo ""

    cd "${INSTALL_DIR}"
    just install
}

main "$@"
