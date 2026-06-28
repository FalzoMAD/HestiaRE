#!/bin/bash

# ======================================================== #
#
# HestiaRE Installer — Interactive Configuration Wizard
#
# Manifest-driven whiptail (with bash fallback) Q&A that writes the install
# recipe to /etc/hestia/install.conf. Called by install.sh after the release
# tarball is extracted, and also runnable standalone to regenerate the recipe:
#
#   bash /usr/local/hestia/func/wizard.sh                # full interactive
#   bash /usr/local/hestia/func/wizard.sh --preset=standard   # fasttrack
#   bash /usr/local/hestia/func/wizard.sh --os=debian-bookworm
#
# After it writes install.conf, run the installer:
#   h-install-hestia      (or: hestia install)
#
# ======================================================== #

set -euo pipefail

# ── Constants ──────────────────────────────────────────────
INSTALL_CONF="/etc/hestia/install.conf"
INSTALL_DIR="${HESTIA:-/usr/local/hestia}"
MANIFEST="${INSTALL_DIR}/share/manifest.json"
LOG_DIR="/var/log/hestia"

# Shared install-time helpers (add_sury_repo, …). Sourcing only defines
# functions — no side effects — so it is safe in the standalone wizard too.
# shellcheck source=func/helper.sh
[ -f "${INSTALL_DIR}/func/helper.sh" ] && . "${INSTALL_DIR}/func/helper.sh"

# ── State ──────────────────────────────────────────────────
HAS_WHIPTAIL=false
OS=""
INSTALL_PROFILE=""
FASTTRACK_PRESET=""
PHP_VERSIONS_AVAILABLE=""
OS_MARIADB_VERSION=""
TOOLS_SELECTION=""
declare -A COMP_VALUES

# ── Argument parsing ───────────────────────────────────────
for _arg in "$@"; do
    case $_arg in
        --os=*)      OS="${_arg#*=}" ;;
        --preset=*)  FASTTRACK_PRESET="${_arg#*=}" ;;
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

# ── OS detection (fallback when --os not given) ────────────
fn_detect_os() {
    [ -z "$OS" ] || return 0
    [ -f /etc/os-release ] || { echo "ERROR: /etc/os-release missing." >&2; exit 1; }
    . /etc/os-release
    case "${ID}:${VERSION_ID}" in
        debian:12)    OS="debian-bookworm" ;;
        debian:13)    OS="debian-trixie"   ;;
        ubuntu:24.04) OS="ubuntu-noble"    ;;
        ubuntu:26.04) OS="ubuntu-26lts"    ;;
        *)
            echo "ERROR: Unsupported OS: ${ID} ${VERSION_ID}" >&2
            echo "Supported: Debian 12/13, Ubuntu 24.04/26.04 LTS" >&2
            exit 1
            ;;
    esac
}

mq() { jq -r "$@" "$MANIFEST"; }

# ════════════════════════════════════════════════════════════
# Manifest load + schema sanity check
# ════════════════════════════════════════════════════════════

fn_manifest_load() {
    [ -f "$MANIFEST" ] || {
        echo "ERROR: Manifest not found at $MANIFEST" >&2
        echo "       Run install.sh after extracting a release." >&2
        exit 1
    }
    jq empty "$MANIFEST" 2>/dev/null || { echo "ERROR: $MANIFEST is not valid JSON" >&2; exit 1; }
    local missing
    missing=$(jq -r '
        . as $root
        | [ ({presets:"object",components:"object",tools:"object",pre_questions:"array",always_installed_packages:"array"}
            | to_entries[])
          | .key as $k | .value as $t
          | if ($root | has($k) | not) then "\($k): missing"
            elif (($root[$k]) | type) != $t then "\($k): wrong type (expected \($t))"
            else empty end ]
        | join("; ")
    ' "$MANIFEST")
    [ -z "$missing" ] || {
        echo "ERROR: $MANIFEST is incomplete or has an invalid structure:" >&2
        echo "       $missing" >&2
        exit 1
    }
}

# ════════════════════════════════════════════════════════════
# TUI helpers — whiptail with bash fallback
# ════════════════════════════════════════════════════════════

_wt_inputbox() {
    local title="$1" prompt="$2" default="$3"
    if [ "$HAS_WHIPTAIL" = true ]; then
        whiptail --title "$title" --inputbox "$prompt" 10 60 "$default" 3>&1 1>&2 2>&3 3>&-
    else
        printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
        read -r _i < /dev/tty
        echo "${_i:-$default}"
    fi
}

_wt_menu() {
    local title="$1" text="$2"; shift 2
    local -a items=("$@")
    if [ "$HAS_WHIPTAIL" = true ]; then
        whiptail --title "$title" --menu "$text" 20 72 10 "${items[@]}" 3>&1 1>&2 2>&3 3>&-
    else
        echo "" > /dev/tty; echo "$text" > /dev/tty
        local -a tags=(); local i=0
        while [ $i -lt ${#items[@]} ]; do
            local tag="${items[$i]}" desc="${items[$((i+1))]}"
            tags+=("$tag"); printf '  %d) %-12s  %s\n' "${#tags[@]}" "$tag" "$desc" > /dev/tty
            i=$((i+2))
        done
        printf 'Choice [1]: ' > /dev/tty; read -r _i < /dev/tty
        local idx=$((_i > 0 ? _i - 1 : 0)); echo "${tags[$idx]:-${tags[0]}}"
    fi
}

_wt_radiolist() {
    local title="$1" text="$2"; shift 2
    local -a items=("$@")
    local list_h=$(( ${#items[@]} / 3 )); [ $list_h -gt 14 ] && list_h=14; [ $list_h -lt 3 ] && list_h=3
    local win_h=$(( list_h + 8 ))
    if [ "$HAS_WHIPTAIL" = true ]; then
        whiptail --title "$title" --radiolist "$text" "$win_h" 72 "$list_h" "${items[@]}" 3>&1 1>&2 2>&3 3>&-
    else
        echo "" > /dev/tty; echo "$text" > /dev/tty
        local -a tags=(); local default_val=""; local i=0
        while [ $i -lt ${#items[@]} ]; do
            local tag="${items[$i]}" state="${items[$((i+2))]}"
            tags+=("$tag"); [ "$state" = "ON" ] && default_val="$tag"
            local marker="  "; [ "$state" = "ON" ] && marker="(*)"
            printf '  %s %d) %s\n' "$marker" "${#tags[@]}" "$tag" > /dev/tty
            i=$((i+3))
        done
        printf 'Choice [%s]: ' "${default_val}" > /dev/tty; read -r _i < /dev/tty
        if [[ "$_i" =~ ^[0-9]+$ ]] && [ "$_i" -ge 1 ] && [ "$_i" -le "${#tags[@]}" ]; then
            echo "${tags[$((_i-1))]}"
        else
            echo "${_i:-$default_val}"
        fi
    fi
}

_wt_checklist() {
    local title="$1" text="$2"; shift 2
    local -a items=("$@")
    local list_h=$(( ${#items[@]} / 3 )); [ $list_h -gt 14 ] && list_h=14; [ $list_h -lt 3 ] && list_h=3
    local win_h=$(( list_h + 8 ))
    if [ "$HAS_WHIPTAIL" = true ]; then
        whiptail --title "$title" --checklist "$text" "$win_h" 72 "$list_h" "${items[@]}" 3>&1 1>&2 2>&3 3>&- || true
    else
        echo "" > /dev/tty; echo "$text" > /dev/tty
        local -a tags=() defaults=(); local i=0
        while [ $i -lt ${#items[@]} ]; do
            local tag="${items[$i]}" state="${items[$((i+2))]}"
            tags+=("$tag"); [ "$state" = "ON" ] && defaults+=("$tag")
            local marker="[ ]"; [ "$state" = "ON" ] && marker="[x]"
            printf '  %s %d) %s\n' "$marker" "${#tags[@]}" "$tag" > /dev/tty
            i=$((i+3))
        done
        printf '  Pre-selected: %s\n' "${defaults[*]:-none}" > /dev/tty
        printf '  Enter space-separated numbers or names to toggle (Enter = accept): ' > /dev/tty
        read -r _i < /dev/tty
        [ -z "$_i" ] && echo "${defaults[*]:-}" || echo "$_i"
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
    [ -n "$HESTIA_HOSTNAME" ] || { echo "ERROR: Hostname is required." >&2; exit 1; }
    [ -n "$HESTIA_ADMIN" ]    || { echo "ERROR: Admin username is required." >&2; exit 1; }
    [ -n "$HESTIA_EMAIL" ]    || { echo "ERROR: Admin email is required." >&2; exit 1; }
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
            FASTTRACK_PRESET=""
            echo "[ * ] Preset 'custom' — full interactive configuration (no defaults)"
            return
        fi
        echo "[ * ] Fasttrack preset: $INSTALL_PROFILE"
        return
    fi
    local -a items=()
    while IFS=$'\t' read -r key label; do items+=("$key" "$label"); done \
        < <(mq '.presets | to_entries[] | [.key, .value.label] | @tsv')
    INSTALL_PROFILE=$(_wt_menu "HestiaRE — Preset" "Select installation preset:" "${items[@]}")
    [ -n "$INSTALL_PROFILE" ] || { echo "ERROR: No preset selected." >&2; exit 1; }
}

# ════════════════════════════════════════════════════════════
# Dynamic version discovery
# ════════════════════════════════════════════════════════════

fn_discover_php_versions() {
    echo "[ * ] Adding Sury PHP repository for version discovery..."
    local codename
    codename=$(. /etc/os-release; echo "$VERSION_CODENAME")
    # Same canonical repo definition the installer's base stage writes, so the
    # later apt-get update in h-install-hestia does not see a conflicting entry.
    if ! command -v add_sury_repo >/dev/null 2>&1 || ! add_sury_repo "$codename"; then
        echo "[ ! ] Sury repo setup failed — using built-in PHP version list" >&2
        PHP_VERSIONS_AVAILABLE="8.5 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0 5.6"
        echo "[ * ] Available PHP versions: $PHP_VERSIONS_AVAILABLE"
        return 0
    fi
    DEBIAN_FRONTEND=noninteractive apt-get -qq update >> "$LOG_DIR/install.log" 2>&1
    PHP_VERSIONS_AVAILABLE=$(apt-cache pkgnames php 2>/dev/null \
        | grep -E '^php[0-9]+\.[0-9]+-(common|fpm)$' \
        | grep -oE '[0-9]+\.[0-9]+' \
        | sort -Vr | uniq | tr '\n' ' ' | sed 's/ $//' || true)
    [ -n "$PHP_VERSIONS_AVAILABLE" ] || {
        echo "[ ! ] Sury version discovery failed — using built-in fallback list" >&2
        PHP_VERSIONS_AVAILABLE="8.5 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0 5.6"
    }
    echo "[ * ] Available PHP versions: $PHP_VERSIONS_AVAILABLE"
}

fn_discover_mariadb_version() {
    local ver=""
    ver=$(apt-cache policy mariadb-server 2>/dev/null \
        | grep -i 'Kandidat\|Candidate' | awk '{print $2}' \
        | grep -oE '^[0-9]+:[0-9]+\.[0-9]+|^[0-9]+\.[0-9]+' \
        | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)
    if [ -z "$ver" ]; then
        ver=$(apt-cache madison mariadb-server 2>/dev/null \
            | awk '{print $3}' | head -n1 | grep -oE '[0-9]+\.[0-9]+' || true)
    fi
    OS_MARIADB_VERSION="${ver:-10.11}"
    echo "[ * ] OS MariaDB version: $OS_MARIADB_VERSION"
}

fn_pre_discovery() {
    local php_mode
    php_mode=$(fn_component_default PHP_MODE "$INSTALL_PROFILE")
    [ "$php_mode" = "sury_multi" ] && fn_discover_php_versions
    fn_discover_mariadb_version
}

# ════════════════════════════════════════════════════════════
# default_rule — PHP version selection
# ════════════════════════════════════════════════════════════

fn_apply_default_rule() {
    local rule="$1"; local -a versions; read -ra versions <<< "$2"; local -a result=()
    if [[ "$rule" =~ ^skip_newest:([0-9]+),take:([0-9]+)$ ]]; then
        local skip="${BASH_REMATCH[1]}" take="${BASH_REMATCH[2]}"
        local -a rem=("${versions[@]:$skip}"); result=("${rem[@]:0:$take}")
    elif [[ "$rule" =~ ^take_newest:([0-9]+)$ ]]; then
        local take="${BASH_REMATCH[1]}"; result=("${versions[@]:0:$take}")
    fi
    echo "${result[*]:-}"
}

# ════════════════════════════════════════════════════════════
# Component helpers
# ════════════════════════════════════════════════════════════

fn_component_default() {
    local id="$1" preset="$2"
    jq -r --arg id "$id" --arg preset "$preset" '
      .components[$id] as $c |
      if ($c.fixed_no_prompt // {} | has($preset)) then $c.fixed_no_prompt[$preset] | tostring
      elif ($c.default | type) == "object" then
        (if ($c.default | has($preset)) and ($c.default[$preset] != null)
         then $c.default[$preset] | tostring else "" end)
      elif ($c.default != null) then $c.default | tostring
      else "" end
    ' "$MANIFEST"
}

fn_eval_condition() {
    local cond="$1"; local -n _cv="$2"
    local key op val; read -r key op val <<< "$cond"
    local actual="${_cv[$key]:-}"
    case "$op" in
        "==") [ "$actual" = "$val" ] && echo "true" || echo "false" ;;
        "!=")
            if [ "$val" = "null" ]; then
                [ -n "$actual" ] && [ "$actual" != "null" ] && [ "$actual" != "false" ] && echo "true" || echo "false"
            else
                [ "$actual" != "$val" ] && echo "true" || echo "false"
            fi
            ;;
        *) echo "true" ;;
    esac
}

# ── Shared value helpers ────────────────────────────────────

fn_resolve_version_value() {
    local val="$1"
    if [ "$val" = "__os__" ]; then
        [ -n "$OS_MARIADB_VERSION" ] || fn_discover_mariadb_version
        printf '%s' "$OS_MARIADB_VERSION"
    else
        printf '%s' "$val"
    fi
}

fn_normalize_list() {
    local raw="${1//\"/}"; local -a parts=(); local p s dup
    for p in $raw; do
        [ -n "$p" ] || continue
        dup=0; for s in "${parts[@]:-}"; do [ "$s" = "$p" ] && { dup=1; break; }; done
        [ "$dup" -eq 0 ] && parts+=("$p")
    done
    printf '%s' "${parts[*]:-}"
}

fn_tools_default_for_preset() {
    local -a defs=()
    readarray -t defs < <(mq --arg p "$INSTALL_PROFILE" '.tools.selection.default[$p][]? // empty')
    TOOLS_SELECTION=$(fn_normalize_list "${defs[*]:-}")
}

# ── Question dispatchers ────────────────────────────────────

_ask_radio() {
    local id="$1" question="$2" default_val="$3"
    # Options may be plain strings (value == display) or objects
    # { value, label, description }. The stored value is always .value; the
    # whiptail item column shows "label — description" (mirrors the grouped
    # checklist UX so the raw enum is never shown bare).
    local -a items=()
    local value text
    while IFS=$'\t' read -r value text; do
        local state="OFF"; [ "$value" = "$default_val" ] && state="ON"
        items+=("$value" "$text" "$state")
    done < <(mq --arg id "$id" '
        .components[$id].options[]
        | if type=="object" then
            [ .value,
              ((.label // .value)
               + (if (.description // "") != "" then "  —  " + .description else "" end)) ]
          else [ ., . ] end
        | @tsv')
    COMP_VALUES["$id"]=$(_wt_radiolist "HestiaRE — $id" "$question" "${items[@]}")
}

_ask_checkbox() {
    local id="$1" question="$2" default_val="$3"
    local state="OFF"; [ "$default_val" = "true" ] && state="ON"
    if [ "$HAS_WHIPTAIL" = true ]; then
        local result
        result=$(whiptail --title "HestiaRE — $id" --checklist "$question" 10 60 1 "$id" "" "$state" 3>&1 1>&2 2>&3 3>&- || true)
        echo "$result" | grep -q "$id" && COMP_VALUES["$id"]="true" || COMP_VALUES["$id"]="false"
    else
        local yn_default; [ "$state" = "ON" ] && yn_default="y" || yn_default="n"
        printf '%s [y/n, default: %s]: ' "$question" "$yn_default" > /dev/tty
        read -r _yn < /dev/tty
        case "${_yn:-}" in
            [yY]*) COMP_VALUES["$id"]="true" ;;
            [nN]*) COMP_VALUES["$id"]="false" ;;
            *)     COMP_VALUES["$id"]="$([ "$state" = "ON" ] && echo true || echo false)" ;;
        esac
    fi
}

_ask_checklist() {
    local id="$1" question="$2" default_val="$3"
    local dynamic_source
    dynamic_source=$(mq --arg id "$id" '.components[$id].dynamic_source // empty')
    local -a all_opts=() default_opts=()
    if [ "$dynamic_source" = "sury_repo_metadata" ]; then
        [ -n "$PHP_VERSIONS_AVAILABLE" ] || fn_discover_php_versions
        read -ra all_opts <<< "$PHP_VERSIONS_AVAILABLE"
        local rule
        rule=$(mq --arg id "$id" --arg p "$INSTALL_PROFILE" '.components[$id].default_rule[$p] // empty')
        if [ -n "$rule" ] && [ "$rule" != "null" ]; then
            local selected; selected=$(fn_apply_default_rule "$rule" "$PHP_VERSIONS_AVAILABLE")
            [ -n "$selected" ] && read -ra default_opts <<< "$selected"
        fi
    else
        readarray -t all_opts < <(mq --arg id "$id" '.components[$id].options[]? // empty')
        if [ -n "$default_val" ] && [ "$default_val" != "null" ]; then
            readarray -t default_opts < <(echo "$default_val" | jq -r '.[]?' 2>/dev/null || echo "$default_val" | tr ' ' '\n')
        fi
    fi
    local -a items=()
    for opt in "${all_opts[@]}"; do
        local state="OFF"; for d in "${default_opts[@]}"; do [ "$d" = "$opt" ] && state="ON" && break; done
        items+=("$opt" "$opt" "$state")
    done
    local selected; selected=$(_wt_checklist "HestiaRE — $id" "$question" "${items[@]}")
    COMP_VALUES["$id"]=$(fn_normalize_list "$selected")
}

_ask_version_select() {
    local id="$1" question="$2" default_val="$3"
    [ -n "$OS_MARIADB_VERSION" ] || fn_discover_mariadb_version
    local -a items=()
    # Use a non-whitespace field separator (US, \x1f): with IFS=$'\t' bash would
    # collapse an empty middle field (empty label_template), shifting later fields.
    while IFS=$'\x1f' read -r value source label_tmpl descr; do
        local display_val display_label state="OFF"
        if [ "$value" = "__os__" ]; then
            display_val=$(fn_resolve_version_value "$value")
            display_label="${label_tmpl/\{version\}/$OS_MARIADB_VERSION}"
            [ -n "$descr" ] && display_label="$display_label  —  $descr"
            [ "$default_val" = "__os__" ] && state="ON"
        else
            display_val="$value"; display_label="${descr:-$source}"
            [ "$default_val" = "$value" ] && state="ON"
        fi
        items+=("$display_val" "$display_label" "$state")
    done < <(mq --arg id "$id" '.components[$id].options[] | [.value, .source, (.label_template // ""), (.description // "")] | join("\u001f")')
    COMP_VALUES["$id"]=$(_wt_radiolist "HestiaRE — $id" "$question" "${items[@]}")
}

_ask_tools_selection() {
    local question; question=$(mq '.tools.selection.question')
    local -a all_opts=()
    readarray -t _vorbelegt < <(mq '.tools.selection.options.vorbelegt[]')
    readarray -t _unbelegt  < <(mq '.tools.selection.options.unbelegt[]')
    all_opts=("${_vorbelegt[@]}" "${_unbelegt[@]}")
    local -a default_tools=()
    readarray -t default_tools < <(mq --arg p "$INSTALL_PROFILE" '.tools.selection.default[$p][]? // empty')
    local -a items=()
    for opt in "${all_opts[@]}"; do
        local state="OFF"; for d in "${default_tools[@]}"; do [ "$d" = "$opt" ] && state="ON" && break; done
        items+=("$opt" "$opt" "$state")
    done
    local _sel; _sel=$(_wt_checklist "HestiaRE — Tools" "$question" "${items[@]}")
    TOOLS_SELECTION=$(fn_normalize_list "$_sel")
}

# ── Fasttrack value derivation (no prompts) ─────────────────

fn_fasttrack_value() {
    local id="$1" type="$2"
    local cond
    cond=$(mq --arg id "$id" '.components[$id].visible_if // empty')
    if [ -n "$cond" ] && [ "$(fn_eval_condition "$cond" COMP_VALUES)" = "false" ]; then COMP_VALUES["$id"]=""; return; fi
    cond=$(mq --arg id "$id" '.components[$id].dependent_on // empty')
    if [ -n "$cond" ] && [ "$(fn_eval_condition "$cond" COMP_VALUES)" = "false" ]; then COMP_VALUES["$id"]=""; return; fi
    case "$type" in
        checklist)
            local dyn; dyn=$(mq --arg id "$id" '.components[$id].dynamic_source // empty')
            if [ "$dyn" = "sury_repo_metadata" ]; then
                [ -n "$PHP_VERSIONS_AVAILABLE" ] || fn_discover_php_versions
                local rule sel=""
                rule=$(mq --arg id "$id" --arg p "$INSTALL_PROFILE" '.components[$id].default_rule[$p] // empty')
                if [ -n "$rule" ] && [ "$rule" != "null" ]; then sel=$(fn_apply_default_rule "$rule" "$PHP_VERSIONS_AVAILABLE"); fi
                COMP_VALUES["$id"]=$(fn_normalize_list "$sel")
            else
                COMP_VALUES["$id"]=$(fn_normalize_list "$(fn_component_default "$id" "$INSTALL_PROFILE")")
            fi
            ;;
        version_select) COMP_VALUES["$id"]=$(fn_resolve_version_value "$(fn_component_default "$id" "$INSTALL_PROFILE")") ;;
        *)              COMP_VALUES["$id"]=$(fn_component_default "$id" "$INSTALL_PROFILE") ;;
    esac
    local followup; followup=$(mq --arg id "$id" '.components[$id].opens_followup // empty')
    if [ -n "$followup" ] && [ "${COMP_VALUES[$id]:-}" = "true" ]; then fn_tools_default_for_preset; fi
}

# ── Main component loop ─────────────────────────────────────

# Render all checkbox components of a group as ONE multi-select screen, set each.
fn_ask_group_checklist() {
    local group="$1"
    local -a cb_ids=()
    readarray -t cb_ids < <(mq --arg g "$group" '.components | to_entries[] | select(.value.group==$g and .value.type=="checkbox") | .key')
    local -a items=() shown=()
    local -A lbl2id=()
    local id
    for id in "${cb_ids[@]}"; do
        local fnp; fnp=$(mq --arg id "$id" --arg p "$INSTALL_PROFILE" '.components[$id].fixed_no_prompt[$p] // empty')
        if [ -n "$fnp" ]; then COMP_VALUES["$id"]="$fnp"; continue; fi
        local vis; vis=$(mq --arg id "$id" '.components[$id].visible_if // empty')
        if [ -n "$vis" ] && [ "$(fn_eval_condition "$vis" COMP_VALUES)" = "false" ]; then COMP_VALUES["$id"]=""; continue; fi
        local dv label desc state="OFF"
        dv=$(fn_component_default "$id" "$INSTALL_PROFILE")
        [ "$dv" = "true" ] && state="ON"
        # whiptail checklist columns are <tag> <description> <on/off>. Use a clean
        # single-token label as the tag (round-tripped back to the component id via
        # lbl2id) and the human-readable description as the second column — so the
        # raw COMPONENT id (ADDON_*/DB_*) is never shown to the user.
        label=$(mq --arg id "$id" '.components[$id].label // ($id | sub("^(ADDON_|DB_)";""))')
        desc=$(mq --arg id "$id" '.components[$id].description // ""')
        items+=("$label" "$desc" "$state"); shown+=("$id"); lbl2id["$label"]="$id"
    done
    [ ${#shown[@]} -gt 0 ] || return 0
    local question; question=$(mq --arg g "$group" '.group_questions[$g] // ("Select: " + $g)')
    local selected; selected=" $(fn_normalize_list "$(_wt_checklist "HestiaRE — $group" "$question" "${items[@]}")") "
    for id in "${shown[@]}"; do COMP_VALUES["$id"]="false"; done
    local lbl
    for lbl in "${!lbl2id[@]}"; do
        case "$selected" in *" $lbl "*) COMP_VALUES["${lbl2id[$lbl]}"]="true" ;; esac
    done
}

fn_ask_components() {
    local -a ids=(); readarray -t ids < <(mq '.components | keys_unsorted[]')
    local grouped; grouped=" $(mq '.grouped_prompts // [] | join(" ")') "
    local -A group_done=()
    for id in "${ids[@]}"; do
        local type grp
        type=$(mq --arg id "$id" '.components[$id].type')
        grp=$(mq --arg id "$id" '.components[$id].group // ""')

        # fixed: always installed, no question
        if [ "$type" = "fixed" ]; then COMP_VALUES["$id"]="true"; continue; fi

        # derived: value mirrors another component (no prompt). Source precedes it.
        if [ "$type" = "derived" ]; then
            local src; src=$(mq --arg id "$id" '.components[$id].derived_from')
            COMP_VALUES["$id"]="${COMP_VALUES[$src]:-false}"
            continue
        fi

        # implicit: preset default; under custom asked as a real question
        if [ "$type" = "implicit" ]; then
            local idefault; idefault=$(fn_component_default "$id" "$INSTALL_PROFILE")
            if [ "$INSTALL_PROFILE" = "custom" ] && [ -z "$idefault" ] \
               && [ "$(mq --arg id "$id" '.components[$id] | has("options") | tostring')" = "true" ]; then
                _ask_radio "$id" "$(mq --arg id "$id" '.components[$id].question // $id')" ""
            else
                COMP_VALUES["$id"]="$idefault"
            fi
            continue
        fi

        # Fasttrack: derive value, no prompts (grouped screens are interactive-only)
        if [ -n "$FASTTRACK_PRESET" ]; then fn_fasttrack_value "$id" "$type"; continue; fi

        # Grouped checkbox: render the whole group as one multi-select screen, once.
        if [ "$type" = "checkbox" ] && [ -n "$grp" ] && [[ "$grouped" == *" $grp "* ]]; then
            if [ -z "${group_done[$grp]:-}" ]; then
                fn_ask_group_checklist "$grp"
                group_done["$grp"]=1
            fi
            local fu; fu=$(mq --arg id "$id" '.components[$id].opens_followup // empty')
            if [ -n "$fu" ] && [ "${COMP_VALUES[$id]:-}" = "true" ]; then _ask_tools_selection; fi
            continue
        fi

        # fixed_no_prompt for this preset
        local fixed
        fixed=$(mq --arg id "$id" --arg p "$INSTALL_PROFILE" '.components[$id].fixed_no_prompt[$p] // empty')
        if [ -n "$fixed" ]; then COMP_VALUES["$id"]="$fixed"; continue; fi

        # visible_if / dependent_on
        local cond
        cond=$(mq --arg id "$id" '.components[$id].visible_if // empty')
        if [ -n "$cond" ] && [ "$(fn_eval_condition "$cond" COMP_VALUES)" = "false" ]; then COMP_VALUES["$id"]=""; continue; fi
        cond=$(mq --arg id "$id" '.components[$id].dependent_on // empty')
        if [ -n "$cond" ] && [ "$(fn_eval_condition "$cond" COMP_VALUES)" = "false" ]; then COMP_VALUES["$id"]=""; continue; fi

        local question default_val
        question=$(mq --arg id "$id" '.components[$id].question // $id')
        default_val=$(fn_component_default "$id" "$INSTALL_PROFILE")
        case "$type" in
            radio)          _ask_radio          "$id" "$question" "$default_val" ;;
            checkbox)       _ask_checkbox       "$id" "$question" "$default_val" ;;
            checklist)      _ask_checklist      "$id" "$question" "$default_val" ;;
            version_select) _ask_version_select "$id" "$question" "$default_val" ;;
        esac
        local followup; followup=$(mq --arg id "$id" '.components[$id].opens_followup // empty')
        if [ -n "$followup" ] && [ "${COMP_VALUES[$id]:-}" = "true" ]; then _ask_tools_selection; fi
    done
}

# ════════════════════════════════════════════════════════════
# Write install.conf
# ════════════════════════════════════════════════════════════

fn_write_install_conf() {
    mkdir -p "$(dirname "$INSTALL_CONF")"
    chmod 700 "$(dirname "$INSTALL_CONF")"
    local ids=(); readarray -t ids < <(mq '.components | keys_unsorted[]')
    {
        echo "# HestiaRE install.conf"
        echo "# Written by func/wizard.sh — do not edit manually."
        echo "# Re-run the wizard to change parameters."
        echo ""
        echo "HESTIA_HOSTNAME=\"${HESTIA_HOSTNAME}\""
        echo "HESTIA_PANEL_PORT=\"${HESTIA_PANEL_PORT}\""
        echo "HESTIA_ADMIN=\"${HESTIA_ADMIN}\""
        echo "HESTIA_EMAIL=\"${HESTIA_EMAIL}\""
        echo "INSTALL_OS=\"${OS}\""
        echo "INSTALL_PROFILE=\"${INSTALL_PROFILE}\""
        echo ""
        echo "# Components"
        for id in "${ids[@]}"; do echo "COMPONENT_${id}=\"${COMP_VALUES[$id]:-}\""; done
        echo ""
        echo "# Selected utilities (from tools checklist)"
        echo "TOOLS_SELECTION=\"${TOOLS_SELECTION:-}\""
        echo ""
        echo "# Always-installed packages"
        local pkgs; pkgs=$(mq '.always_installed_packages | join(" ")')
        echo "ALWAYS_INSTALLED_PACKAGES=\"${pkgs}\""
    } > "$INSTALL_CONF"
    chmod 600 "$INSTALL_CONF"
}

# ════════════════════════════════════════════════════════════
# Wizard entry point
# ════════════════════════════════════════════════════════════

wizard_main() {
    [ "$(id -u)" = "0" ] || { echo "ERROR: wizard must run as root (writes /etc/hestia + APT)." >&2; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }
    mkdir -p "$LOG_DIR"
    fn_detect_os

    # whiptail only in a real interactive terminal; else bash fallback.
    if command -v whiptail >/dev/null 2>&1 && [ -t 0 ] && [ "${TERM:-}" != "dumb" ] && [ -n "${TERM:-}" ]; then
        HAS_WHIPTAIL=true
    fi

    fn_manifest_load
    fn_ask_pre_questions
    fn_ask_preset
    fn_pre_discovery
    fn_ask_components
    fn_write_install_conf

    echo ""
    echo "[ OK ] install.conf written to: ${INSTALL_CONF}"
    echo "       Hostname : ${HESTIA_HOSTNAME}"
    echo "       Port     : ${HESTIA_PANEL_PORT}"
    echo "       Admin    : ${HESTIA_ADMIN} <${HESTIA_EMAIL}>"
    echo "       Profile  : ${INSTALL_PROFILE}   OS: ${OS}"
}

# Run only when executed directly (not when sourced).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    wizard_main
fi
