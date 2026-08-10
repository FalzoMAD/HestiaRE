#!/bin/bash

user="$1"
domain="$2"
ip="$3"
home="$4"
docroot="$5"

str="proxy_cache_path /var/cache/nginx/$domain levels=1:2 use_temp_path=off keys_zone=$domain:10m inactive=60m max_size=256m;"
conf="/etc/nginx/conf.d/01_caching_pool.conf"

# Inlined remove_pool_zone (standalone trigger, no includes): a dot in $domain is a regex
# wildcard, and a lost zone with a vhost still referencing it breaks nginx -t box-wide
if [ -e "$conf" ]; then
	grep -vF "keys_zone=${domain}:" "$conf" > "$conf.tmp" || true
	mv -f "$conf.tmp" "$conf"
fi

echo "$str" >> $conf
