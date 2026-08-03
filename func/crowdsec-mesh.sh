# HestiaRE CrowdSec fleet-mesh: peering + transport helpers.
#
# Transport = an authenticated pull over the panel port (:8083 HTTPS). Each box serves its own
# published ban list at /mesh-decisions.php behind a per-peer bearer token, and pulls every peer's
# list with the token that peer issued during pairing. The CrowdSec LAPI itself stays loopback-only -
# what crosses the wire is a file of IP values, never the API.
#
# Pairing needs an admin on BOTH boxes and cannot happen otherwise:
#   - on the joining box (A): root shell / admin panel session to run h-add-sys-crowdsec-peer,
#   - on the accepting box (B): root shell / admin panel session to mint a one-time code
#     (h-generate-sys-crowdsec-pairing). /mesh-pair.php is a 404 while no code is live.
# Neither side ever handles the other's credentials; the code is single-use and short-lived, and the
# long-lived artefact is a per-peer token.
#
# TLS is verified by SPKI pin, not by CA: panel certs are usually self-signed, so pairing records the
# peer's public-key hash (TOFU) and every later pull is pinned to it. A swapped cert fails closed.
#
# Secret hygiene: tokens never appear in argv (a local user can read /proc/*/cmdline). Curl reads
# them from a 0600 config file, the panel hands the pairing payload over in a 0600 handoff file, and
# only hashes are staged for the panel to compare against.

MESH_CONF_FILE="$CONF_DIR/crowdsec/mesh.conf"
MESH_PEERS_CONF="$CONF_DIR/crowdsec/peers.conf"
MESH_PAIRING_CONF="$CONF_DIR/crowdsec/pairing.conf"
MESH_RUN_DIR='/run/hestia/mesh'

# Load mesh.conf + defaults. Returns 1 when the mesh is not enabled (conf absent), so callers can
# no-op quietly: the conf's presence IS the on/off switch.
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

# Peer id: the record key, the peers-dir filename and the hestia-mesh:<id> scenario suffix, so it must
# be filename- and comment-safe. Trailing non-alnum is stripped for is_comment_format_valid.
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
	[[ "$n" =~ ^[0-9]+$ ]] || { echo 1800; return; }
	case "$u" in
		s) echo "$n" ;;
		m) echo $((n * 60)) ;;
		h) echo $((n * 3600)) ;;
		d) echo $((n * 86400)) ;;
		*) echo 1800 ;;
	esac
}

# sha256 of a secret, for comparing without storing the plaintext.
mesh_hash() { printf '%s' "$1" | sha256sum | cut -f1 -d ' '; }

mesh_token_new() { openssl rand -hex 32; }

# The peer's TLS public-key hash, in curl's --pinnedpubkey form. Fetched over an unverified handshake
# on purpose: there is no CA to trust, the pin IS the identity from here on.
mesh_spki_pin() {
	local host="$1" port="$2" pin
	pin=$(echo | timeout 10 openssl s_client -connect "$host:$port" 2> /dev/null \
		| openssl x509 -pubkey -noout 2> /dev/null \
		| openssl pkey -pubin -outform der 2> /dev/null \
		| openssl dgst -sha256 -binary 2> /dev/null | base64 | tr -d '\n')
	[ ${#pin} -ge 40 ] || return 1
	printf '%s' "$pin"
}

# Open/close the panel port for a peer IP. These rules only ADD to admin access - :8083 is never
# narrowed to peers-only, which would lock the admin out.
mesh_fw_open() {
	local ip="$1" peer="$2"
	[ -n "$(mesh_fw_rule_id "$peer")" ] && return 0
	$BIN/h-add-firewall-rule 'ACCEPT' "$ip" "${BACKEND_PORT:-8083}" 'TCP' "$(mesh_fw_comment "$peer")" > /dev/null 2>&1
}

mesh_fw_rule_id() {
	[ -f "$CONF_DIR/firewall/rules.conf" ] || return 0
	grep -m1 "COMMENT='$(mesh_fw_comment "$1")'" "$CONF_DIR/firewall/rules.conf" 2> /dev/null \
		| sed -n "s/^RULE='\([0-9]*\)'.*/\1/p"
}

mesh_fw_close() {
	local id
	id=$(mesh_fw_rule_id "$1")
	[ -n "$id" ] && $BIN/h-delete-firewall-rule "$id" > /dev/null 2>&1
	return 0
}

# Stage what the panel needs under /run (tmpfs, recreated by tmpfiles.d + this call): the published
# payload and the per-peer serve-token HASHES. The panel runs as `hestia` and cannot read /etc/hestia
# or /var/lib/crowdsec, so /mesh-decisions.php compares hashes here instead of shelling out with a
# secret in argv. Hashes only - the file leaking must not hand anyone a working token.
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

# Pull each peer's published list into MESH_PEERS_DIR for the import step. Token via a 0600 curl
# config (never argv), TLS pinned, size- and shape-checked before it replaces the last good copy: an
# unreachable peer keeps serving its previous list rather than silently unbanning the fleet. Files
# older than MESH_STALE_MIN are dropped, so a peer that stays gone eventually stops counting.
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
			echo "url = \"https://$HOST:${PORT:-8083}/mesh-decisions.php\""
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
