#!/bin/bash
# a backup exclusion names an object literally; only '*' is a pattern. An entry for aXb.com must
# not exclude a.b.com from the archive.
set -u
fail=0
exact() { echo -e "$1" | tr ',' '\n' | awk -v d="$2" '$0 == d || $0 == "*"'; }
prefix() { echo -e "$1" | tr ',' '\n' | awk -v d="$2" 'index($0, d) == 1 || /\*:/'; }

[ -z "$(exact 'aXb.com' 'a.b.com')" ] || { echo "FAIL: exact form excluded the wrong domain"; fail=1; }
[ -n "$(exact 'a.b.com' 'a.b.com')" ] || { echo "FAIL: exact form missed its own domain"; fail=1; }
[ -n "$(exact '*' 'a.b.com')" ] || { echo "FAIL: the * wildcard stopped working"; fail=1; }
[ -z "$(prefix 'aXb.com:tmp' 'a.b.com')" ] || { echo "FAIL: prefix form excluded the wrong domain"; fail=1; }
[ -n "$(prefix 'a.b.com:tmp' 'a.b.com')" ] || { echo "FAIL: prefix form missed its own domain"; fail=1; }
[ -n "$(prefix '*:cache' 'a.b.com')" ] || { echo "FAIL: the *: wildcard stopped working"; fail=1; }
exit "$fail"
