#!/bin/bash

#===========================================================================#
#                                                                           #
# Hestia Control Panel - Firewall Function Library                          #
#                                                                           #
#===========================================================================#

# The one place that knows the backend's syntax. Callers ask in object-model terms (action, protocol,
# port, source, jail, set); this renders it into one nft table.
#
# Callers open a batch, append, apply. A batch is buffered into sections and assembled into a single
# document, because nft wants a document and because the order callers emit in is not the order the
# ruleset needs. One `nft -f` swaps the whole table, so there is no moment with an open policy or an
# empty chain - which is what the iptables renderer could not avoid.
#
# One inet table covers IPv4 and IPv6 and loads whether or not v6 is configured. Only v4 is rendered
# today; nothing here may require a v6 address to exist.

FW_NFT="/usr/sbin/nft"
FW_FAMILY="inet"
FW_TABLE="hestia"
FW_RULESET="/etc/hestia/firewall/ruleset.nft"
FW_WORK=""
FW_INPUT_POLICY="drop"

#----------------------------------------------------------#
#                     Batch handling                       #
#----------------------------------------------------------#

# nft wants a document, not a command stream, and the order callers emit in is not the order the ruleset
# needs: jail rules are added last but must match first. So a batch buffers into sections and the document
# is assembled at apply time. Callers are unaffected.
fw_batch_begin() {
	FW_WORK="$(mktemp -d)"
	: > "$FW_WORK/exclude"
	: > "$FW_WORK/jail"
	: > "$FW_WORK/base"
	: > "$FW_WORK/setjump"
	: > "$FW_WORK/rules"
	FW_INPUT_POLICY="drop"
}

fw_batch_discard() {
	[ -n "${FW_WORK:-}" ] && rm -rf "$FW_WORK"
	FW_WORK=""
}

# Append to a section, creating it on first use.
fw_sec() {
	echo "$2" >> "$FW_WORK/$1"
}

# Assemble the table and swap it in one transaction. The empty declaration before the delete is what
# makes this idempotent on a box that has no table yet; without it the delete fails and takes the
# transaction with it. There is no instant with an empty chain or an open policy.
fw_batch_render() {
	local f
	echo "table $FW_FAMILY $FW_TABLE {}"
	echo "delete table $FW_FAMILY $FW_TABLE"
	echo "table $FW_FAMILY $FW_TABLE {"
	fw_render_sets
	echo "	chain input {"
	echo "		type filter hook input priority filter; policy $FW_INPUT_POLICY;"
	# Jails first: they used to be inserted at the head, which put them above the conntrack accept, so
	# a ban drops live connections too. Keep that.
	cat "$FW_WORK/exclude" "$FW_WORK/jail" "$FW_WORK/base" "$FW_WORK/setjump" "$FW_WORK/rules"
	echo "	}"
	for f in "$FW_WORK"/chain.*; do
		[ -e "$f" ] || continue
		echo "	chain ${f##*/chain.} {"
		cat "$f"
		echo "	}"
	done
	echo "}"
}

# Validate before applying: nft -c parses and type-checks without touching the kernel. Note the flag
# order, `nft -c -f FILE`. Written the other way round it eats -c as the filename and reports a syntax
# error against the real path.
fw_batch_apply() {
	local doc="$FW_WORK/ruleset.nft"
	fw_batch_render > "$doc"
	if ! "$FW_NFT" -c -f "$doc" 2> "$FW_WORK/err"; then
		echo "firewall: rendered ruleset rejected, keeping the running one" >&2
		sed 's/^/  /' "$FW_WORK/err" >&2
		return 1
	fi
	"$FW_NFT" -f "$doc" 2> "$FW_WORK/err" || {
		echo "firewall: apply failed, ruleset unchanged" >&2
		sed 's/^/  /' "$FW_WORK/err" >&2
		return 1
	}
	cp -f "$doc" "$FW_RULESET"
	return 0
}

#----------------------------------------------------------#
#                  Chains and policy                       #
#----------------------------------------------------------#

# Policy is a property of the chain in nft, so this records it for the render instead of emitting.
fw_policy() {
	[ "$1" = 'INPUT' ] && FW_INPUT_POLICY="$(echo "$2" | tr '[:upper:]' '[:lower:]')"
	return 0
}

# No-ops: replacing the table is the flush, and chains are declared by being written to.
fw_flush() { :; }
fw_chain_create() { [ "$1" = 'INPUT' ] || touch "$FW_WORK/chain.$1"; }
fw_chain_drop() { :; }

# Callers name chains the way the object model does (INPUT); nft chains are lower case. Read from the
# plain listing rather than the JSON: the JSON spacing is not stable enough to sed and jq is not a
# dependency of this library.
fw_policy_get() {
	local chain
	chain="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
	"$FW_NFT" list chain "$FW_FAMILY" "$FW_TABLE" "$chain" 2> /dev/null \
		| sed -n 's/.* policy \([a-z]*\);.*/\1/p' | head -1 | tr '[:lower:]' '[:upper:]'
}

fw_chain_exists() {
	"$FW_NFT" list chain "$FW_FAMILY" "$FW_TABLE" "$(echo "$1" | tr '[:upper:]' '[:lower:]')" > /dev/null 2>&1
}

#----------------------------------------------------------#
#                    Base INPUT rules                      #
#----------------------------------------------------------#

fw_accept_established() {
	fw_sec base "		ct state established,related accept"
}

fw_accept_source() {
	fw_sec base "		ip saddr $1 accept"
}

# excludes.conf used to only suppress NEW bans, which left an already-banned admin locked out and gave the
# file no effect on anything but fail2ban. Rendering it as an accept ahead of the ban matches makes it the
# recovery primitive it was always meant to be. Skipped when empty so an absent file costs nothing.
fw_accept_excludes() {
	[ -s "$CONF_DIR/firewall/excludes.conf" ] || return 0
	fw_set_declare excludes interval
	fw_sec exclude "		ip saddr @excludes accept"
}

fw_return_source() {
	fw_sec "chain.$1" "		ip saddr $2 return"
}

fw_chain_tail() {
	fw_sec "chain.$1" "		$(echo "$2" | tr '[:upper:]' '[:lower:]')"
}

# A set-fed jump. The set is declared here so the document never references one that does not exist -
# under iptables that mismatch was a boot-time landmine, in nft it is a parse error caught by -c.
fw_set_jump() {
	fw_set_declare "$2" interval
	fw_sec setjump "		ip saddr @$(fw_set_id "$2") jump $1"
}

# Set names: nft has a stricter charset than ipset, so dashes become underscores. One mapping, used by
# every declaration and reference.
fw_set_id() {
	echo "${1//-/_}"
}

# Where a dynamic set's contents come from. Replacing the whole table would otherwise drop every element,
# so a set is never the record of truth for itself: it is rendered from a file, the same way the ruleset is
# rendered from the object model. The CrowdSec feeder and the blocklist refresh each own one of these.
fw_set_src() {
	case "$1" in
		crowdsec-blacklists) echo "$CONF_DIR/firewall/crowdsec.iplist" ;;
		excludes) echo "$CONF_DIR/firewall/excludes.conf" ;;
		*) echo "$CONF_DIR/firewall/ipset/$1.v4.iplist" ;;
	esac
}

# Recorded as metadata, not as a finished line, so elements can be folded in at assembly time.
# Idempotent: a set referenced twice is declared once. `interval` is required for CIDR members and brings
# auto-merge, so overlapping ranges collapse instead of failing the whole transaction.
fw_set_declare() {
	local id
	id="$(fw_set_id "$1")"
	echo "${2:-plain}" > "$FW_WORK/set.$id"
	echo "$1" > "$FW_WORK/name.$id"
}

# One element list per set: whatever a caller buffered (bans) plus whatever the set's source file holds
# (blocklists, CrowdSec decisions). Comments and blanks are dropped; nft rejects the whole document over
# one bad element, so anything that is not an address or CIDR is filtered out here rather than trusted.
fw_set_elements() {
	local id="$1" src
	[ -s "$FW_WORK/elem.$id" ] && cat "$FW_WORK/elem.$id"
	src="$(fw_set_src "$(cat "$FW_WORK/name.$id")")"
	[ -s "$src" ] && grep -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$' "$src"
	return 0
}

fw_render_sets() {
	local f id kind elems
	for f in "$FW_WORK"/set.*; do
		[ -e "$f" ] || continue
		id="${f##*/set.}"
		kind="$(cat "$f")"
		elems="$(fw_set_elements "$id" | sort -u | paste -sd, - | sed 's/,/, /g')"
		[ -n "$elems" ] && elems=" elements = { $elems };"
		if [ "$kind" = 'interval' ]; then
			echo "	set $id { type ipv4_addr; flags interval; auto-merge;${elems} }"
		else
			echo "	set $id { type ipv4_addr;${elems} }"
		fi
	done
}

# Live replace of one set's contents, for the paths that must not rebuild the whole ruleset: the CrowdSec
# feeder runs every 45s and a blocklist refresh is a cron job. Flush and refill in ONE transaction, so the
# set is never observably empty - the ipset original needed a temporary set and a swap to get this.
fw_set_replace() {
	local id doc
	id="$(fw_set_id "$1")"
	doc="$(mktemp)"
	{
		echo "flush set $FW_FAMILY $FW_TABLE $id"
		grep -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$' "$2" 2> /dev/null \
			| sort -u | sed "s|^|add element $FW_FAMILY $FW_TABLE $id { |;s|$| }|"
	} > "$doc"
	"$FW_NFT" -f "$doc" 2> /dev/null
	local rc=$?
	rm -f "$doc"
	return $rc
}

fw_set_exists() {
	"$FW_NFT" list set "$FW_FAMILY" "$FW_TABLE" "$(fw_set_id "$1")" > /dev/null 2>&1
}

# Returns non-zero while a rule still matches the set: nft refuses to delete a referenced set, and that
# refusal is a useful answer rather than an error to swallow.
fw_set_destroy() {
	"$FW_NFT" delete set "$FW_FAMILY" "$FW_TABLE" "$(fw_set_id "$1")" 2> /dev/null
}

fw_set_count() {
	"$FW_NFT" list set "$FW_FAMILY" "$FW_TABLE" "$(fw_set_id "$1")" 2> /dev/null \
		| grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | wc -l
}

# A port list becomes an anonymous nft set. iptables writes ranges with a colon, nft with a dash.
fw_port_expr() {
	local spec="${1//:/-}"
	case "$spec" in
		*,* | *-*) echo "{ ${spec//,/, } }" ;;
		*) echo "$spec" ;;
	esac
}

# fw_rule <action> <protocol> <port> <source> [type] [conntrack_ftp]
# One rules.conf record.
#
# Two quirks carried over from the iptables renderer, deliberately:
#   - `type` mirrors the old $TYPE, which nothing ever sets (the field is COMMENT). So the FTP conntrack
#     branch only fires on a literal port 21, and the shipped rule is '21,12000-12100' - it never does.
#     Custom PassivePorts therefore get neither the static range nor the dynamic fallback.
#   - a source of 0.0.0.0/0 is omitted rather than rendered: matching everything is the default.
fw_rule() {
	local action="$1" protocol="$2" port_val="$3" source="$4" type="${5:-}" conntrack_ftp="${6:-}"
	local proto expr=""

	proto="$(echo "$protocol" | tr '[:upper:]' '[:lower:]')"

	case "$source" in
		ipset:*)
			fw_set_declare "${source#ipset:}" interval
			expr="ip saddr @$(fw_set_id "${source#ipset:}") "
			;;
		0.0.0.0/0 | '') ;;
		*) expr="ip saddr $source " ;;
	esac

	if [ "$proto" = 'icmp' ] || [ "$port_val" = '0' ]; then
		expr="${expr}ip protocol $proto "
	elif [ "$type" = 'FTP' ] || [ "$port_val" = '21' ]; then
		if [ "$conntrack_ftp" != 'no' ]; then
			expr="${expr}${proto} dport $(fw_port_expr "$port_val") ct state new "
		else
			expr="${expr}${proto} dport $(fw_port_expr '20,21,12000-12100') "
		fi
	else
		expr="${expr}${proto} dport $(fw_port_expr "$port_val") "
	fi

	fw_sec rules "		${expr}$(echo "$action" | tr '[:upper:]' '[:lower:]')"
}

#----------------------------------------------------------#
#                     fail2ban jails                       #
#----------------------------------------------------------#

# A jail is a set plus one rule, not a chain full of per-IP rules: nft matches a set in constant time and
# a ban becomes an element add with no rule bookkeeping. The chain-with-RETURN-tail shape existed only
# because iptables had no other way to hold a list.
fw_jail_set() {
	echo "f2b_$1"
}

fw_jail_rebuild() {
	local chain="$1" protocol="$2" port_val="$3" proto
	proto="$(echo "$protocol" | tr '[:upper:]' '[:lower:]')"
	fw_set_declare "$(fw_jail_set "$chain")"
	fw_sec jail "		ip saddr @$(fw_jail_set "$chain") ${proto} dport $(fw_port_expr "$port_val") reject with icmpx type port-unreachable"
}

fw_jail_teardown() { :; }

# Live attach: the rule has to go to the head of the chain for a ban to outrank the service accepts.
fw_jail_attach() {
	local chain="$1" protocol="$2" port_val="$3" proto
	proto="$(echo "$protocol" | tr '[:upper:]' '[:lower:]')"
	"$FW_NFT" add set "$FW_FAMILY" "$FW_TABLE" "$(fw_jail_set "$chain")" '{ type ipv4_addr; }' 2> /dev/null
	"$FW_NFT" list chain "$FW_FAMILY" "$FW_TABLE" input 2> /dev/null \
		| grep -q "@$(fw_jail_set "$chain") " && return 0
	"$FW_NFT" insert rule "$FW_FAMILY" "$FW_TABLE" input index 0 \
		ip saddr "@$(fw_jail_set "$chain")" "$proto" dport "$(fw_port_expr "$port_val")" \
		reject with icmpx type port-unreachable 2> /dev/null
}

# Deleting the rule needs its handle; the set goes with it. No multiport asymmetry to inherit here,
# because there is only one rule per jail whatever the port list looks like.
fw_jail_detach() {
	local handle
	handle=$("$FW_NFT" -a list chain "$FW_FAMILY" "$FW_TABLE" input 2> /dev/null \
		| sed -n "s/.*@$(fw_jail_set "$1") .*# handle \([0-9]*\)$/\1/p" | head -1)
	[ -n "$handle" ] && "$FW_NFT" delete rule "$FW_FAMILY" "$FW_TABLE" input handle "$handle" 2> /dev/null
	return 0
}

fw_jail_destroy() {
	"$FW_NFT" delete set "$FW_FAMILY" "$FW_TABLE" "$(fw_jail_set "$1")" 2> /dev/null
	return 0
}

# Jail sets, reported under the chain names the object model uses.
fw_jail_chains_live() {
	"$FW_NFT" list sets "$FW_FAMILY" 2> /dev/null | sed -n 's/^	set f2b_\([A-Za-z0-9_]*\) .*/\1/p'
}

# Wired means the set exists and the input chain still matches it.
fw_jail_wired() {
	"$FW_NFT" list set "$FW_FAMILY" "$FW_TABLE" "$(fw_jail_set "$1")" > /dev/null 2>&1 || return 1
	"$FW_NFT" list chain "$FW_FAMILY" "$FW_TABLE" input 2> /dev/null | grep -q "@$(fw_jail_set "$1") "
}

fw_set_chain_destroy() {
	"$FW_NFT" delete set "$FW_FAMILY" "$FW_TABLE" "$(fw_set_id "$2")" 2> /dev/null
	"$FW_NFT" delete chain "$FW_FAMILY" "$FW_TABLE" "$1" 2> /dev/null
	return 0
}

#----------------------------------------------------------#
#                          Bans                            #
#----------------------------------------------------------#

fw_ban_add() {
	"$FW_NFT" add element "$FW_FAMILY" "$FW_TABLE" "$(fw_jail_set "$1")" "{ $2 }" 2> /dev/null
	return 0
}

# Batched replay from banlist.conf. The set must exist in the same document, so declare on demand: a
# banlist row can name a chain that chains.conf no longer has.
fw_ban_emit() {
	fw_set_declare "$(fw_jail_set "$1")"
	echo "$2" >> "$FW_WORK/elem.$(fw_jail_set "$1")"
}

fw_ban_delete() {
	"$FW_NFT" delete element "$FW_FAMILY" "$FW_TABLE" "$(fw_jail_set "$1")" "{ $2 }" 2> /dev/null
	return 0
}

#----------------------------------------------------------#
#                      Persistence                        #
#----------------------------------------------------------#

# The ruleset file is written by fw_batch_apply, so persisting is only ever "make sure the unit that
# reloads it at boot exists and is enabled". There is no save step and no dump to post-process: the
# document that was applied IS the document that gets reloaded.
#
# Own file and own unit, not /etc/nftables.conf and nftables.service. That file is a dpkg conffile, and
# writing to a package's conffile is how the distro fail2ban jail kept coming back.
fw_boot_unit_path() {
	echo "/lib/systemd/system/hestia-nftables.service"
}

fw_boot_unit_write() {
	local sd_unit
	sd_unit="$(fw_boot_unit_path)"
	[ -e "$sd_unit" ] && return 0
	{
		echo "[Unit]"
		echo "Description=Loading Hestia firewall rules"
		echo "DefaultDependencies=no"
		echo "Wants=network-pre.target local-fs.target"
		echo "Before=network-pre.target"
		echo "After=local-fs.target"
		echo ""
		echo "[Service]"
		echo "Type=oneshot"
		echo "RemainAfterExit=yes"
		# No ExecStartPre that provisions sets separately: sets and the rules that match them are in one
		# file and load in one transaction, so the ordering hazard that could boot the box open is gone.
		echo "ExecStart=$FW_NFT -f $FW_RULESET"
		echo ""
		echo "[Install]"
		echo "WantedBy=multi-user.target"
	} >> "$sd_unit"
	systemctl -q daemon-reload
}

fw_persist_enable() {
	fw_boot_unit_write
	systemctl -q is-enabled hestia-nftables 2> /dev/null || systemctl -q enable hestia-nftables
	return 0
}

fw_persist_disable() {
	fw_boot_unit_write
	systemctl -q is-enabled hestia-nftables 2> /dev/null && systemctl -q disable hestia-nftables
	if [ -z "$FIREWALL_SYSTEM" ]; then
		rm -f "$(fw_boot_unit_path)"
		systemctl -q daemon-reload
	fi
	return 0
}

# Drop our own table, for h-stop-firewall.
fw_table_destroy() {
	"$FW_NFT" delete table "$FW_FAMILY" "$FW_TABLE" 2> /dev/null
	rm -f "$FW_RULESET"
	return 0
}

#----------------------------------------------------------#
#                    Legacy iptables                       #
#----------------------------------------------------------#

# Retire the iptables ruleset this box used to carry.
#
# This is required, not tidy-up. iptables here is xtables-nft-multi, so its rules live in the same kernel
# backend as ours, as `table ip filter`. Left in place they keep being evaluated next to the nft table:
# two firewalls, one of them managed by nothing.
#
# Driven off what is actually in the ruleset rather than off chains.conf, because a box that hit the
# multi-port delete bug carries a fail2ban chain with no record left - and that is exactly the corpse a
# model-driven teardown would walk past.
fw_legacy_teardown() {
	local ipt=/sbin/iptables c
	[ -x "$ipt" ] || return 0
	"$ipt" -S INPUT > /dev/null 2>&1 || return 0

	"$ipt" -P INPUT ACCEPT 2> /dev/null
	"$ipt" -F INPUT 2> /dev/null
	for c in $("$ipt" -S 2> /dev/null | sed -n 's/^-N \(fail2ban-[A-Za-z0-9_]*\|hestia\|hestia-crowdsec\)$/\1/p'); do
		"$ipt" -F "$c" 2> /dev/null
		"$ipt" -X "$c" 2> /dev/null
	done

	# The old boot unit and its saved dump would otherwise reinstate all of it on the next reboot.
	if [ -e /lib/systemd/system/hestia-iptables.service ]; then
		systemctl -q disable hestia-iptables 2> /dev/null
		rm -f /lib/systemd/system/hestia-iptables.service
		systemctl -q daemon-reload
	fi
	rm -f /etc/iptables.rules /etc/sysconfig/iptables
	return 0
}
