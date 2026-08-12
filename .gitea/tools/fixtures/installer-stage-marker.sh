#!/bin/bash
# a completed install stage may only be skipped for the answers it ran with
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CONF_DIR="$T"
printf 'COMPONENT_DB_MARIADB="false"\n' > "$T/install.conf"
eval "$(sed -n '/^stage_done() {/,/^}/p;/^stage_mark() {/,/^}/p;/^stage_fingerprint() {/,/^}/p' "$ROOT/bin/h-install-hestia")"

fail=0
stage_mark db
stage_done db || { echo "FAIL: unchanged answers did not skip"; fail=1; }
printf 'COMPONENT_DB_MARIADB="true"\n' > "$T/install.conf"
stage_done db && { echo "FAIL: changed answers were skipped"; fail=1; }
stage_mark db
stage_done db || { echo "FAIL: fresh mark did not skip"; fail=1; }
: > "$T/.done.db"
stage_done db && { echo "FAIL: an empty legacy marker counted as done"; fail=1; }
exit "$fail"
