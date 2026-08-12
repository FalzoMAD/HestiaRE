#!/bin/bash
# a.b.com and aXb.com may coexist (the creation guard compares literally), so a read on one must
# never return the other's record - the dot is a regex wildcard.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CONF_DIR="$T"; mkdir -p "$T/users/bob"
cat > "$T/users/bob/web.conf" << 'CONF'
DOMAIN='a.b.com' IP='10.0.0.1' TPL='correct' SSL='yes' TIME='10:00:00' DATE='2026-08-12'
DOMAIN='aXb.com' IP='10.0.0.9' TPL='wildcard-victim' SSL='no' TIME='10:00:00' DATE='2026-08-12'
CONF
USER_DATA="$T/users/bob"; user=bob
_object_conf() { echo "$USER_DATA/$1.conf"; }
E_NOTEXIST=3
check_result() { exit "$1"; }
parse_object_kv_list() { eval "$@"; }
eval "$(sed -n '/^get_object_value() {/,/^}/p;/^is_object_valid() {/,/^}/p' "$ROOT/func/main.sh")"

fail=0
got=$(get_object_value 'web' 'DOMAIN' 'a.b.com' '$TPL')
[ "$got" = 'correct' ] || { echo "FAIL: a.b.com read returned '$got'"; fail=1; }
got=$(get_object_value 'web' 'DOMAIN' 'aXb.com' '$TPL')
[ "$got" = 'wildcard-victim' ] || { echo "FAIL: aXb.com read returned '$got'"; fail=1; }

cat > "$T/users/bob/web.conf" << 'CONF'
DOMAIN='aXb.com' IP='10.0.0.9' TPL='wildcard-victim' SSL='no' TIME='10:00:00' DATE='2026-08-12'
CONF
if (is_object_valid 'web' 'DOMAIN' 'a.b.com') 2> /dev/null; then
	echo "FAIL: is_object_valid accepted a.b.com while only aXb.com exists"
	fail=1
fi
exit "$fail"
