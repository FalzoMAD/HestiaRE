#!/bin/bash
# Ports HestiaRE declares for its own listeners (#730), derived from the shipped configs so a
# listener added later cannot fall out. Nothing is bound at wizard time, so a live check cannot
# replace it. Excluded: comment lines, *.php (vendored code declares ports too), IP octets.

# (?!...) drops comment lines, \K keeps the number, (?![\d.]) stops an IP octet reading as a port.
PORT_DECL_RE='^(?!\s*(?:#|;|//|--)).*?(?:listen[\s=]+(?:[0-9a-fA-F.:\[\]*]+:)?|127\.0\.0\.1:|localhost:|https?://:|[a-z_]*port\s*=\s*['"'"'"]?)\K\d{2,5}(?![\d.])'

# The panel's own port is no conflict for the panel; read from the template so it follows.
panel_port_shipped() {
	local root="${1:-${HESTIA:-/usr/local/hestia}}"
	sed -n 's|^[[:space:]]*https\?://:\([0-9]\{2,5\}\).*|\1|p' "$root/share/panel-caddy/hestia.conf" 2> /dev/null | head -n1
}

# PORT<TAB>SOURCE. Empty is a broken tree, not a free choice: return 1 so the callers refuse.
reserved_ports() {
	local root="${1:-${HESTIA:-/usr/local/hestia}}" own out
	own=$(panel_port_shipped "$root")
	out=$(grep -rPnoi --exclude='*.php' "$PORT_DECL_RE" "$root/share" "$root/include" 2> /dev/null \
		| sed "s|^$root/||" \
		| awk -F: '{print $NF"\t"$1}' \
		| awk -v own="$own" '$1 != own' | sort -u)
	[ -n "$out" ] || return 1
	printf '%s\n' "$out"
}

# Listener and proxies both declare the port, so the most specific wins; unknown ones by path.
reserved_port_owner() {
	local port="$1" root="${2:-${HESTIA:-/usr/local/hestia}}" src
	src=$(reserved_ports "$root" \
		| awk -v p="$port" '$1 == p {rank = 4; if ($2 ~ /panel-caddy\/webmail-/) rank = 1; else if ($2 ~ /panel-caddy/) rank = 2; else if ($2 ~ /firewall\/rules.conf/) rank = 5; else if ($2 ~ /^share\//) rank = 3; print rank "\t" $2}' \
		| sort -k1,1n | head -n1 | cut -f2) || return 1
	[ -n "$src" ] || return 1
	case "$src" in
		*/panel-caddy/webmail-roundcube.conf) echo "the Roundcube webmail listener" ;;
		*/panel-caddy/webmail-tachyon.conf) echo "the SnappyMail/Tachyon webmail listener" ;;
		*/panel-caddy/*) echo "the panel webserver ($(basename "$src"))" ;;
		*/nginx/*) echo "nginx ($(basename "$src"))" ;;
		*/apache2/*) echo "apache2 ($(basename "$src"))" ;;
		*/crowdsec*) echo "the CrowdSec local API" ;;
		*/mysql/*) echo "the database server" ;;
		*/dovecot/*) echo "dovecot ($(basename "$src"))" ;;
		*/firewall/rules.conf) echo "the firewall rule set" ;;
		*/db.sh) echo "the database stack" ;;
		*/web-model.sh) echo "the web stack backend (WEB_PORT/WEB_SSL_PORT)" ;;
		*) echo "$src" ;;
	esac
}

# One validator for wizard and h-change-sys-port.
panel_port_refusal() {
	local port="$1" root="${2:-${HESTIA:-/usr/local/hestia}}" owner
	if [[ ! "$port" =~ ^[0-9]+$ ]]; then
		echo "must be a number"
		return 1
	fi
	# Below 1024 needs root and collides with the web stack.
	if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
		echo "must be between 1024 and 65535"
		return 1
	fi
	if ! reserved_ports "$root" > /dev/null; then
		echo "the reserved-port scan found no listener declaration under $root - refusing to validate against an empty set"
		return 1
	fi
	if owner=$(reserved_port_owner "$port" "$root"); then
		echo "reserved for $owner"
		return 1
	fi
	return 0
}

# What is bound right now: little during the install, decisive on a live box.
panel_port_live_holder() {
	local port="$1" line name
	line=$(ss -H -tlnp 2> /dev/null | awk -v p="[:.]$port$" '$4 ~ p {print; exit}')
	[ -n "$line" ] || return 1
	# Without root the process column is empty and $NF would be the peer address.
	name=$(sed -n 's/.*users:((\"\([^\"]*\)\".*/\1/p' <<< "$line")
	echo "${name:-an unidentified process (run as root to name it)}"
}
