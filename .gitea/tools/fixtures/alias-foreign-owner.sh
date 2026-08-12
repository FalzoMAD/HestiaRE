#!/bin/bash
# an alias that belongs to another customer must be refused for every object type, and the owner
# must still be able to use their own.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CONF_DIR="$T"; mkdir -p "$T/users/alice" "$T/users/bob"
cat > "$T/users/alice/web.conf" << 'CONF'
DOMAIN='alice.com' IP='10.0.0.1' ALIAS='shop.alice.com,www.alice.com' TPL='default' TIME='10:00:00'
CONF
: > "$T/users/bob/web.conf"
E_EXISTS=4
check_result() { exit "$1"; }
eval "$(sed -n '/^is_web_alias_new() {/,/^}/p' "$ROOT/func/domain.sh")"

fail=0
for t in web mail; do
	user=bob
	if (is_web_alias_new 'shop.alice.com' "$t") 2> /dev/null; then
		echo "FAIL: bob was allowed to take alice's alias as type=$t"
		fail=1
	fi
done
user=alice
if ! (is_web_alias_new 'shop.alice.com' mail) 2> /dev/null; then
	echo "FAIL: alice was refused her own alias"
	fail=1
fi
user=bob
if ! (is_web_alias_new 'free.example.com' mail) 2> /dev/null; then
	echo "FAIL: an unused alias was refused"
	fail=1
fi
exit "$fail"
