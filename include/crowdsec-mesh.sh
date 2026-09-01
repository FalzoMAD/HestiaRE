#!/bin/bash
# HestiaRE CrowdSec fleet-mesh: peering + transport helpers.
#
# Transport = an authenticated pull over the panel port: each box serves its own published ban list at
# /mesh-decisions.php behind a per-peer token and pulls its peers' with the token they issued. The LAPI
# stays loopback-only; only a file of IP values crosses the wire.
#
# Pairing needs an admin on BOTH boxes: one to run h-add-sys-crowdsec-peer, one to mint the one-time
# code (/mesh-pair.php is a 404 while no code is live). Neither side handles the other's credentials.
#
# TLS is pinned by SPKI, not CA - panel certs are usually self-signed, so pairing records the peer's
# key (TOFU) and every later pull is bound to it. A swapped cert fails closed.
#
# Secrets never appear in argv (/proc/*/cmdline is world-readable): curl reads tokens from a 0600
# config, the panel hands its payload over in a 0600 file, and only hashes are staged for it.

MESH_CONF_FILE="$CONF_DIR/crowdsec/mesh.conf"
MESH_PEERS_CONF="$CONF_DIR/crowdsec/peers.conf"
MESH_PAIRING_CONF="$CONF_DIR/crowdsec/pairing.conf"
MESH_RUN_DIR='/run/hestia/mesh'

# Returns 1 when the mesh is off: the conf's presence IS the switch, so callers no-op quietly.
mesh_load() {
	[ -f "$MESH_CONF_FILE" ] || return 1
	# shellcheck source=/etc/hestia/crowdsec/mesh.conf
	source "$MESH_CONF_FILE"
	MESH_TTL="${MESH_TTL:-30m}"
	MESH_PUBLISH="${MESH_PUBLISH:-/var/lib/crowdsec/mesh/published.json}"
	MESH_PEERS_DIR="${MESH_PEERS_DIR:-/var/lib/crowdsec/mesh/peers}"
	MESH_MAX_PER_PEER="${MESH_MAX_PER_PEER:-5000}"
	MESH_MAX_TOTAL="${MESH_MAX_TOTAL:-50000}"
	MESH_PAIRING_TTL="${MESH_PAIRING_TTL:-900}"
	MESH_PAIRING_TRIES="${MESH_PAIRING_TRIES:-5}"
	MESH_STALE_MIN="${MESH_STALE_MIN:-360}"
	return 0
}

# Peer id doubles as filename, scenario suffix and firewall comment - hence the charset, the cap and
# the trailing-non-alnum strip (is_comment_format_valid rejects a trailing . or -).
mesh_peer_id() {
	local id
	id=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-' | cut -c1-32)
	id=$(printf '%s' "$id" | sed -e 's/^[^a-z0-9]*//' -e 's/[^a-z0-9]*$//')
	printf '%s' "$id"
}

mesh_fw_comment() { printf 'hestia-mesh %s' "$1"; }

# MESH_TTL ("30m") in seconds, for deciding when imported decisions need renewing.
mesh_ttl_seconds() {
	local t="${MESH_TTL:-30m}" n u
	n=${t%[smhd]}
	u=${t: -1}
	[[ "$n" =~ ^[0-9]+$ ]] || {
		echo 1800
		return
	}
	case "$u" in
		s) echo "$n" ;;
		m) echo $((n * 60)) ;;
		h) echo $((n * 3600)) ;;
		d) echo $((n * 86400)) ;;
		*) echo 1800 ;;
	esac
}

# Compare secrets without storing plaintext.
mesh_hash() { printf '%s' "$1" | sha256sum | cut -f1 -d ' '; }

mesh_token_new() { openssl rand -hex 32; }

# The peer's key in curl's --pinnedpubkey form. Fetched over an unverified handshake on purpose:
# there is no CA to trust, the pin IS the identity from here on.
mesh_spki_pin() {
	local host="$1" port="$2" pin
	# bracketed: -connect splits on the last colon, and an address is full of them
	pin=$(echo | timeout 10 openssl s_client -connect "$(url_host "$host"):$port" 2> /dev/null \
		| openssl x509 -pubkey -noout 2> /dev/null \
		| openssl pkey -pubin -outform der 2> /dev/null \
		| openssl dgst -sha256 -binary 2> /dev/null | base64 | tr -d '\n')
	[ ${#pin} -ge 40 ] || return 1
	printf '%s' "$pin"
}

# Only ADDS to admin access - never narrowed to peers-only, that would lock the admin out. $1 may
# name several addresses: a dual-stack peer calls back over v6, so one family alone would not match.
mesh_fw_open() {
	local addr peer="$2" comment opened=0
	for addr in $1; do
		case "$addr" in
			*:*) comment="$(mesh_fw_comment "$peer") v6" ;;
			*) comment="$(mesh_fw_comment "$peer")" ;;
		esac
		if grep -qF "COMMENT='$comment'" "$CONF_DIR/firewall/rules.conf" 2> /dev/null; then
			opened=1
			continue
		fi
		$BIN/h-add-firewall-rule 'ACCEPT' "$addr" "${BACKEND_PORT:-8083}" 'TCP' "$comment" > /dev/null 2>&1 \
			&& opened=1
	done
	[ "$opened" = 1 ]
}

# FIXED strings: a peer id may carry dots and dashes, which an expression would read as meta.
mesh_fw_rule_ids() {
	local c
	[ -f "$CONF_DIR/firewall/rules.conf" ] || return 0
	c=$(mesh_fw_comment "$1")
	grep -F -e "COMMENT='$c'" -e "COMMENT='$c v6'" "$CONF_DIR/firewall/rules.conf" 2> /dev/null \
		| sed -n "s/^RULE='\([0-9]*\)'.*/\1/p"
}

mesh_fw_close() {
	local id
	for id in $(mesh_fw_rule_ids "$1"); do
		$BIN/h-delete-firewall-rule "$id" > /dev/null 2>&1
	done
	return 0
}

# Stage what the panel needs under /run: the payload plus the per-peer serve-token HASHES. The panel
# runs as `hestia` and can read neither /etc/hestia nor /var/lib/crowdsec, so it compares hashes here
# rather than shelling out with a secret in argv - and a leak of this file yields no working token.
mesh_stage_serve() {
	mkdir -p "$MESH_RUN_DIR/in"
	chown root:hestia "$MESH_RUN_DIR" "$MESH_RUN_DIR/in" 2> /dev/null
	chmod 750 "$MESH_RUN_DIR"
	chmod 730 "$MESH_RUN_DIR/in"

	if [ -f "$MESH_PUBLISH" ]; then
		install -m 640 -o root -g hestia "$MESH_PUBLISH" "$MESH_RUN_DIR/published.json" 2> /dev/null
	fi

	local tmp str
	tmp=$(mktemp)
	if [ -f "$MESH_PEERS_CONF" ]; then
		while read -r str; do
			[ -z "$str" ] && continue
			unset PEER SERVE_TOKEN SUSPENDED
			parse_object_kv_list "$str"
			[ -n "$SERVE_TOKEN" ] || continue
			[ "$SUSPENDED" = 'yes' ] && continue
			echo "$(mesh_hash "$SERVE_TOKEN") $PEER"
		done < "$MESH_PEERS_CONF" >> "$tmp"
	fi
	install -m 640 -o root -g hestia "$tmp" "$MESH_RUN_DIR/tokens" 2> /dev/null
	rm -f "$tmp"
}

# Pull each peer's list for the import step. Only a valid response replaces the last good copy, so an
# unreachable peer keeps its previous list rather than silently unbanning the fleet; one that stays
# gone ages out via MESH_STALE_MIN.
mesh_pull_peers() {
	[ -f "$MESH_PEERS_CONF" ] || return 0
	local str cfg out
	while read -r str; do
		[ -z "$str" ] && continue
		unset PEER HOST PORT PIN PULL_TOKEN SUSPENDED
		parse_object_kv_list "$str"
		if [ -z "$PEER" ] || [ -z "$HOST" ] || [ -z "$PULL_TOKEN" ]; then continue; fi
		[ "$SUSPENDED" = 'yes' ] && continue

		cfg=$(mktemp)
		chmod 600 "$cfg"
		{
			echo "url = \"https://$(url_host "$HOST"):${PORT:-8083}/mesh-decisions.php\""
			echo "header = \"Authorization: Bearer $PULL_TOKEN\""
			[ -n "$PIN" ] && echo "pinnedpubkey = \"sha256//$PIN\""
		} > "$cfg"
		out=$(mktemp)
		if curl -fsS -k --config "$cfg" --max-time 20 --max-filesize 8000000 -o "$out" 2> /dev/null \
			&& jq -e 'type == "array"' "$out" > /dev/null 2>&1; then
			install -m 600 -o root -g root "$out" "$MESH_PEERS_DIR/$PEER.json" 2> /dev/null
		fi
		rm -f "$cfg" "$out"
	done < "$MESH_PEERS_CONF"

	find "$MESH_PEERS_DIR" -maxdepth 1 -name '*.json' -mmin "+$MESH_STALE_MIN" -delete 2> /dev/null
	return 0
}
