#!/bin/bash
# The ports HestiaRE hands out to its own listeners (#730).
#
# Derived from the shipped configs, never a maintained list: a listener added later would
# otherwise fall out of the set because nobody remembered to add it here, and a guard that
# looks at less is worse than none.
#
# This is NOT a reserved numeric band. It is the set of ports our own files DECLARE, which
# measures out at about a dozen individual numbers - the panel and web-stack 80xx, but also
# 3306 from share/mysql/my-*.cnf, 5432 from include/db.sh and 4190 from our managesieve
# config. A digit class that only looked at 8xxx let 3306 through as a panel port, and an
# hour later MariaDB could not bind: exactly the failure this guard exists for.
#
# Three things the scan must exclude, each measured rather than assumed:
#   - comment lines: dovecot and rspamd ship their defaults commented out (11333, 9900,
#     2000), and a comment naming a port does not claim it
#   - application code (*.php): a listener is declared in configuration, not in a program,
#     and vendored code carries other people's ports - adminer connects to "localhost:1433".
#     NOT covered as a consequence: a listener that only ever appears in a .php.
#     (VENDORED.json cannot do this job: it is export-ignore, so it never reaches a box and
#     the exclusion would look right in the repo and be inert where it matters.)
#   - IP octets and clock fields: hence the anchors below and the "not followed by a dot"
#
# A live check cannot replace any of this at wizard time: most of these services are not
# installed yet when the operator picks the panel port, so nothing is bound and nothing
# collides - until the installer brings them up an hour later.

# Anchored on declaration forms only: nginx/apache `listen`, a loopback target, a Caddy site
# address, a `port =` or `*_PORT=` assignment. The leading (?!...) drops comment lines, \K
# keeps only the number, and (?![\d.]) stops an IP octet from reading as a port.
PORT_DECL_RE='^(?!\s*(?:#|;|//|--)).*?(?:listen[\s=]+(?:[0-9a-fA-F.:\[\]*]+:)?|127\.0\.0\.1:|localhost:|https?://:|[a-z_]*port\s*=\s*['"'"'"]?)\K\d{2,5}(?![\d.])'

# The port the panel's own site template declares. It is not a conflict for the panel to
# take it, so it is subtracted from the reserved set - read from the template rather than
# written down, so moving the panel moves this with it.
panel_port_shipped() {
	local root="${1:-${HESTIA:-/usr/local/hestia}}"
	sed -n 's|^[[:space:]]*https\?://:\([0-9]\{2,5\}\).*|\1|p' "$root/share/panel-caddy/hestia.conf" 2> /dev/null | head -n1
}

# PORT<TAB>SOURCE per line. Returns 1 on an empty result: "nothing reserved" is a broken
# tree (or a grep without -P), not a free choice, and the callers must refuse rather than
# wave everything through.
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

# Names the conflict partner. Several files can declare the same port (a listener and the
# proxies pointing at it), so the most specific declaration wins: the panel-caddy listener
# before a service config before a shell default. Falls back to the declaring file - an
# unknown location must still be named, never swallowed into "some other service".
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

# The single validator for the panel port, shared by the wizard and h-change-sys-port so a
# port one of them refuses cannot be accepted by the other. Echoes the reason, returns 1.
panel_port_refusal() {
	local port="$1" root="${2:-${HESTIA:-/usr/local/hestia}}" owner
	if [[ ! "$port" =~ ^[0-9]+$ ]]; then
		echo "must be a number"
		return 1
	fi
	# Below 1024 needs root to bind and collides with the customer web stack; the panel runs
	# unprivileged behind the firewall rule that opens exactly this port.
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

# Second, weaker check for the runtime path: what is bound RIGHT NOW. Worth little during
# the install (half the stack is not up yet), decisive on a live box.
panel_port_live_holder() {
	local port="$1" line name
	line=$(ss -H -tlnp 2> /dev/null | awk -v p="[:.]$port$" '$4 ~ p {print; exit}')
	[ -n "$line" ] || return 1
	# The process column is empty without root, and $NF would then be the peer address - a
	# holder named "*:*" reads like a finding and is none.
	name=$(sed -n 's/.*users:((\"\([^\"]*\)\".*/\1/p' <<< "$line")
	echo "${name:-an unidentified process (run as root to name it)}"
}
