#!/bin/bash

#===========================================================================#
#                                                                           #
# Hestia Control Panel - Firewall Function Library                          #
#                                                                           #
#===========================================================================#

# The ONE place that knows the backend's syntax (#495). Every h-*-firewall* command states what it
# wants in object-model terms (action, protocol, port, source, jail, set) and this library renders it,
# so swapping iptables for nft is a change here and nowhere else.
#
# Emission model, deliberately unchanged by the seam step: callers open a batch, append to it, then
# apply it. A batch is a script of backend commands that gets `bash`ed, which is what lets a rendered
# fragment carry shell quoting (`--match-set 'name' src`); executing an argv array instead would pass
# those quotes through literally and silently never match. The nft step replaces a batch with one
# ruleset file applied via a single `nft -f`, which is also what closes the fail-open window.

FW_IPTABLES="/sbin/iptables"
FW_BATCH=""

heal_iptables_links() {
	packages="iptables iptables-save iptables-restore"
	for package in $packages; do
		if [ ! -e "/sbin/${package}" ]; then
			if which ${package}; then
				ln -s "$(which ${package})" /sbin/${package}
			elif [ -e "/usr/sbin/${package}" ]; then
				ln -s /usr/sbin/${package} /sbin/${package}
			elif whereis -B /bin /sbin /usr/bin /usr/sbin -f -b ${package}; then
				autoiptables=$(whereis -B /bin /sbin /usr/bin /usr/sbin -f -b ${package} | cut -d '' -f 2)
				if [ -x "$autoiptables" ]; then
					ln -s "$autoiptables" /sbin/${package}
				fi
			fi
		fi
	done
}

#----------------------------------------------------------#
#                     Batch handling                       #
#----------------------------------------------------------#

fw_batch_begin() {
	FW_BATCH="$(mktemp)"
}

# Errors are swallowed to match the pre-seam behaviour exactly. That is a known defect (a
# half-applied ruleset is invisible, roadmap D2) and it is fixed with the atomic nft apply, not here:
# the seam step must not change behaviour or the byte-equality gate loses its meaning.
fw_batch_apply() {
	[ -n "$FW_BATCH" ] && bash "$FW_BATCH" 2> /dev/null
	return 0
}

fw_batch_discard() {
	[ -n "$FW_BATCH" ] && rm -f "$FW_BATCH"
	FW_BATCH=""
}

# Append a rendered backend command. Internal; callers use the semantic helpers below.
fw_emit() {
	echo "$1" >> "$FW_BATCH"
}

#----------------------------------------------------------#
#                  Chains and policy                       #
#----------------------------------------------------------#

fw_policy() {
	fw_emit "$FW_IPTABLES -P $1 $2"
}

fw_flush() {
	fw_emit "$FW_IPTABLES -F $1"
}

fw_chain_create() {
	fw_emit "$FW_IPTABLES -N $1"
}

fw_chain_drop() {
	fw_emit "$FW_IPTABLES -X $1"
}

# Live queries, so callers never shell the backend themselves just to look.
fw_policy_get() {
	$FW_IPTABLES -S "$1" 2> /dev/null | sed -n "s/^-P $1 //p"
}

fw_chain_exists() {
	$FW_IPTABLES -n -L "$1" > /dev/null 2>&1
}

#----------------------------------------------------------#
#                    Base INPUT rules                      #
#----------------------------------------------------------#

fw_accept_established() {
	fw_emit "$FW_IPTABLES -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT"
}

fw_accept_source() {
	fw_emit "$FW_IPTABLES -A INPUT -s $1 -j ACCEPT"
}

fw_return_source() {
	fw_emit "$FW_IPTABLES -A $1 -s $2 -j RETURN"
}

fw_chain_tail() {
	fw_emit "$FW_IPTABLES -A $1 -j $2"
}

# Enter an owned chain for every source in a named set.
fw_set_jump() {
	fw_emit "$FW_IPTABLES -A INPUT -m set --match-set $2 src -j $1"
}

# fw_rule <action> <protocol> <port> <source> [type] [conntrack_ftp]
# Renders one rules.conf record. <source> is an IP/CIDR or `ipset:<name>`.
#
# Faithful to the pre-seam construction, including two quirks that must not be "fixed" here:
#   - `type` is the old $TYPE reference, which nothing ever sets (the object model field is COMMENT).
#     So the FTP conntrack branch is reachable only via a literal PORT of 21, and the shipped FTP rule
#     is '21,12000-12100' - meaning that branch and its 20,21,12000:12100 fallback are dead for the
#     default ruleset. Kept verbatim; changing it is a behavioural change and belongs to its own issue.
#   - an empty port or state leaves double spaces in the emitted command. Harmless (the kernel
#     normalises, and the captures compare effective state) but do not "tidy" it into a behaviour change.
fw_rule() {
	local action="$1" protocol="$2" port_val="$3" source="$4" type="${5:-}" conntrack_ftp="${6:-}"
	local proto="-p $protocol" port="--dport $port_val" state="" ip

	if [[ "$source" =~ ^ipset: ]]; then
		# Quoting survives because the batch is re-parsed by bash - see the header note.
		ip="-m set --match-set '${source#ipset:}' src"
	else
		ip="-s $source"
	fi

	[[ "$port_val" =~ ,|-|: ]] && port="-m multiport --dports ${port_val//-/:}"
	{ [ "$port_val" = "0" ] || [ "$protocol" = 'ICMP' ]; } && port=""

	if [ "$type" = "FTP" ] || [ "$port_val" = '21' ]; then
		if [ "$conntrack_ftp" != 'no' ]; then
			state="-m conntrack --ctstate NEW"
		else
			port="-m multiport --dports 20,21,12000:12100"
		fi
	fi

	fw_emit "$FW_IPTABLES -A INPUT $proto $port $ip $state -j $action"
}

#----------------------------------------------------------#
#                     fail2ban jails                       #
#----------------------------------------------------------#

# The port match for a jail jump. Multiport whenever the port list is not a single number.
fw_jail_port_match() {
	if [[ "$1" =~ ,|-|: ]]; then
		echo "-m multiport --dports $1"
	else
		echo "--dport $1"
	fi
}

# Batched jail rebuild (h-update-firewall). The jump is INSERTED, so jails end up above every ACCEPT
# emitted before them - including the conntrack one, which is why a fail2ban ban also kills live
# connections while a set-based DROP further down only blocks new ones.
fw_jail_rebuild() {
	local chain="$1" protocol="$2" port_val="$3"
	fw_emit "$FW_IPTABLES -N fail2ban-$chain"
	fw_emit "$FW_IPTABLES -F fail2ban-$chain"
	fw_emit "$FW_IPTABLES -I fail2ban-$chain -s 0.0.0.0/0 -j RETURN"
	fw_emit "$FW_IPTABLES -I INPUT -p $protocol $(fw_jail_port_match "$port_val") -j fail2ban-$chain"
}

fw_jail_teardown() {
	fw_emit "$FW_IPTABLES -F fail2ban-$1"
	fw_emit "$FW_IPTABLES -X fail2ban-$1"
}

# Live jail attach/detach (fail2ban's actionstart/actionstop paths, which run outside a batch).
#
# The port match expands to two or three words, so it goes through an array rather than an unquoted
# substitution: word splitting is wanted, but it must not depend on the caller's IFS. h-update-firewall
# sets IFS=$'\n' for its object-model loops, and under that an unquoted expansion would hand iptables
# one argument containing spaces instead of separate flags.
fw_jail_attach() {
	local chain="$1" protocol="$2" port_val="$3"
	local IFS=' '
	local -a match
	read -r -a match <<< "$(fw_jail_port_match "$port_val")"
	$FW_IPTABLES -N "fail2ban-$chain" 2> /dev/null || return 1
	$FW_IPTABLES -A "fail2ban-$chain" -j RETURN
	$FW_IPTABLES -I INPUT -p "$protocol" "${match[@]}" -j "fail2ban-$chain"
}

# Note the asymmetry with fw_jail_attach, preserved on purpose: the delete uses a bare --dport, so it
# fails for every multi-port jail (MAIL, WEB, DB, RECIDIVE) and leaks the jump while the chains.conf
# record is already gone. That is roadmap D4 and it is fixed in #496 - the seam step must not change
# behaviour, so the bug is kept here where it is visible rather than buried in the caller.
fw_jail_detach() {
	local chain="$1" protocol="$2" port_val="$3"
	$FW_IPTABLES -D INPUT -p $protocol --dport $port_val -j fail2ban-$chain 2> /dev/null
}

# Is the jail chain present AND reachable from the base chain? Both halves matter: the chain can
# survive while h-update-firewall's flush has dropped the jump, and in that state bans are recorded
# but never enforced. Backend-specific, which is exactly why it lives here.
fw_jail_wired() {
	$FW_IPTABLES -n -L "fail2ban-$1" > /dev/null 2>&1 || return 1
	$FW_IPTABLES -S INPUT 2> /dev/null | grep -q -- "-j fail2ban-$1\$"
}

fw_jail_destroy() {
	$FW_IPTABLES -F fail2ban-$1 2> /dev/null
	$FW_IPTABLES -X fail2ban-$1 2> /dev/null
}

# Live teardown of an owned set-fed chain (CrowdSec L3). Direct, not batched: it runs after the
# marker is gone, so h-update-firewall would no longer emit any of it.
fw_set_chain_destroy() {
	local chain="$1" setname="$2"
	$FW_IPTABLES -D INPUT -m set --match-set "$setname" src -j "$chain" 2> /dev/null || true
	$FW_IPTABLES -F "$chain" 2> /dev/null || true
	$FW_IPTABLES -X "$chain" 2> /dev/null || true
	return 0
}

#----------------------------------------------------------#
#                          Bans                            #
#----------------------------------------------------------#

fw_ban_add() {
	$FW_IPTABLES -I fail2ban-$1 1 -s $2 -j REJECT --reject-with icmp-port-unreachable 2> /dev/null
}

fw_ban_emit() {
	fw_emit "$FW_IPTABLES -I fail2ban-$1 1 -s $2 -j REJECT --reject-with icmp-port-unreachable"
}

# Deleting by rule number, since the ban rule carries no comment to match on. The line-number lookup
# is the fragile part the nft step removes outright (a set element is deleted by value).
fw_ban_delete() {
	local chain="$1" ip="$2" num
	num=$($FW_IPTABLES -L fail2ban-$chain --line-number -n | grep -w "$ip" | awk '{print $1}')
	[ -n "$num" ] && $FW_IPTABLES -D fail2ban-$chain $num 2> /dev/null
	return 0
}

#----------------------------------------------------------#
#                      Persistence                         #
#----------------------------------------------------------#

# Individual fail2ban ban rules are stripped from the dump on purpose: bans are replayed from
# banlist.conf, so persisting them too would double them up after a restore.
fw_save() {
	local dst=/etc/iptables.rules
	[ -d "/etc/sysconfig" ] && dst=/etc/sysconfig/iptables
	/sbin/iptables-save \
		| sed -e 's/[[0-9]\+:[0-9]\+]/[0:0]/g' -e '/^-A fail2ban-[A-Z]\+ -s .\+$/d' > "$dst"
}

fw_boot_unit_path() {
	echo "/lib/systemd/system/hestia-iptables.service"
}

# Written once and left alone afterwards, so a hand-edited unit survives.
fw_boot_unit_write() {
	local sd_unit version
	sd_unit="$(fw_boot_unit_path)"
	[ -e "$sd_unit" ] && return 0
	version="$(iptables --version | head -1 | awk '{print $2}' | cut -f -2 -d .)"
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
		# Dash-prefixed, so a set that fails to load does not fail the unit. That is exactly how a
		# missing set can let iptables-restore reject the whole table and boot the box open, which is
		# what h-check-sys-smoke's check_firewall_sets_bootable guards.
		echo "ExecStartPre=-${HESTIA}/bin/h-update-firewall-ipset load"
		if [ "$version" = "v1.6" ]; then
			echo "ExecStart=/sbin/iptables-restore /etc/iptables.rules"
		else
			echo "ExecStart=/sbin/iptables-restore --wait=10 /etc/iptables.rules"
		fi
		echo ""
		echo "[Install]"
		echo "WantedBy=multi-user.target"
	} >> "$sd_unit"
	systemctl -q daemon-reload
}

# The /etc/sysconfig branch never had a boot unit; only the /etc/iptables.rules layout does.
fw_persist_enable() {
	fw_save
	[ -d "/etc/sysconfig" ] && return 0
	fw_boot_unit_write
	systemctl -q is-enabled hestia-iptables 2> /dev/null || systemctl -q enable hestia-iptables
	return 0
}

fw_persist_disable() {
	fw_save
	[ -d "/etc/sysconfig" ] && return 0
	fw_boot_unit_write
	systemctl -q is-enabled hestia-iptables 2> /dev/null && systemctl -q disable hestia-iptables
	if [ -z "$FIREWALL_SYSTEM" ]; then
		rm -f "$(fw_boot_unit_path)"
		systemctl -q daemon-reload
	fi
	return 0
}
