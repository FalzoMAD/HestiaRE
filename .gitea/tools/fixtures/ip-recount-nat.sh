#!/bin/bash
# the ip domain recount has to see both spellings of the address: behind NAT a record carries the
# public one while the ip file is named after the local one.
set -u
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/users/alice" "$T/ips"
cat > "$T/ips/10.5.5.12" << 'IPC'
OWNER='admin' STATUS='shared' U_WEB_DOMAINS='9' NAT='37.187.128.33' TIME='10:00:00' DATE='2026-08-12'
IPC
cat > "$T/users/alice/web.conf" << 'CONF'
DOMAIN='a.example.com' IP='37.187.128.33' TPL='default' SUSPENDED='no' TIME='10:00:00'
DOMAIN='b.example.com' IP='10.5.5.12' TPL='default' SUSPENDED='no' TIME='10:00:00'
CONF
ip=10.5.5.12
nat=$(grep -o "NAT='[^']*'" "$T/ips/$ip" | head -1 | cut -f 2 -d \')
counted=$(grep -H -e "IP='$ip'" ${nat:+-e "IP='$nat'"} "$T"/users/*/web.conf | sed '/^$/d' | wc -l)
if [ "$counted" -ne 2 ]; then
	echo "FAIL: recount saw $counted of 2 records (NAT form missed?)"
	exit 1
fi
exit 0
