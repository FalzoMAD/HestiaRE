#!/bin/bash
# The ports HestiaRE hands out to its own listeners (#730).
#
# Derived from the shipped configs, never a maintained list: a listener added later would
# otherwise fall out of the set because nobody remembered to add it here, and a guard that
# looks at less is worse than none. The regex anchors on the forms that DECLARE a listener,
# which is why a buffer size of 8192 in a vendored file is not read as a port.
#
# A live check cannot replace this at wizard time: most of these services are not installed
# yet when the operator picks the panel port, so nothing is bound and nothing collides -
# until the installer brings them up an hour later.

# Anchored on declaration forms: nginx/apache `listen`, a loopback target, a Caddy site
# address, a `port =` assignment. Ports outside 8000-8999 are not ours to hand out.
PORT_DECL_RE='(listen[[:space:]=]+[^;]*[^0-9]|127\.0\.0\.1:|localhost:|https?://:|port[[:space:]]*=[[:space:]]*)(8[0-9]{3})'

# The port the panel's own site template declares. It is not a conflict for the panel to
# take it, so it is subtracted from the reserved set - read from the template rather than
# written down, so moving the panel moves this with it.
panel_port_shipped() {
	local root="${1:-${HESTIA:-/usr/local/hestia}}"
	sed -n 's|^[[:space:]]*https\?://:\([0-9]\{2,5\}\).*|\1|p' "$root/share/panel-caddy/hestia.conf" 2> /dev/null | head -n1
}

# PORT<TAB>SOURCE per line. Returns 1 on an empty result: "nothing reserved" is a broken
# tree, not a free choice, and the callers must refuse rather than wave everything through.
reserved_ports() {
	local root="${1:-${HESTIA:-/usr/local/hestia}}" own out
	own=$(panel_port_shipped "$root")
	out=$(grep -rsoiE "$PORT_DECL_RE" "$root/share" "$root/include" 2> /dev/null \
		| sed -E 's|^([^:]*):.*[^0-9]([0-9]{4})$|\2\t\1|' \
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
		| awk -v p="$port" '$1 == p {rank = 4; if ($2 ~ /panel-caddy\/webmail-/) rank = 1; else if ($2 ~ /panel-caddy/) rank = 2; else if ($2 ~ /\/share\//) rank = 3; print rank "\t" $2}' \
		| sort -k1,1n | head -n1 | cut -f2) || return 1
	[ -n "$src" ] || return 1
	case "$src" in
		*/panel-caddy/webmail-roundcube.conf) echo "the Roundcube webmail listener" ;;
		*/panel-caddy/webmail-tachyon.conf) echo "the SnappyMail/Tachyon webmail listener" ;;
		*/panel-caddy/*) echo "the panel webserver ($(basename "$src"))" ;;
		*/nginx/*) echo "nginx ($(basename "$src"))" ;;
		*/apache2/*) echo "apache2 ($(basename "$src"))" ;;
		*/crowdsec*) echo "the CrowdSec local API" ;;
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
