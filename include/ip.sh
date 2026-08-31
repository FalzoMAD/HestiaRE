#!/bin/bash

#===========================================================================#
#                                                                           #
# Hestia Control Panel - IP/Network Function Library                        #
#                                                                           #
#===========================================================================#

# Global definitions
REGEX_IPV4="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}$"

# RFC-5952 form at the ENTRY of every writer: two spellings of one address must not become
# two objects. Non-v6 passes through; a php backend that does not answer returns rc 1 with
# no output - a silent raw-spelling fallback would recreate the very double object.
ip6_canonical() {
	local out
	case "$1" in
		*:*) ;;
		*)
			echo "$1"
			return 0
			;;
	esac
	out=$($HESTIA_PHP -r '$b = @inet_pton($argv[1]); echo $b === false || strlen($b) !== 16 ? $argv[1] : inet_ntop($b);' "$1" 2> /dev/null)
	[ -n "$out" ] || return 1
	echo "$out"
}

# Check ip ownership
is_ip_owner() {
	owner=$(grep 'OWNER=' $CONF_DIR/ips/$ip | cut -f 2 -d \')
	if [ "$owner" != "$user" ]; then
		check_result "$E_FORBIDEN" "$ip is not owned by $user"
	fi
}

# Check if ip address is free
is_ip_free() {
	if [ -e "$CONF_DIR/ips/$ip" ]; then
		check_result "$E_EXISTS" "$ip is already exists"
	fi
}

# Check ip address specific value
is_ip_key_empty() {
	key="$1"
	# source_conf, not `eval $(cat ...)`: the old form executed the whole IP conf as bash, so any content
	# in it ran (the GHSA-xffx class). Callers pass a single '$VARNAME', so strip the $ and deref safely.
	[ -e "$CONF_DIR/ips/$ip" ] && source_conf "$CONF_DIR/ips/$ip"
	local varname="${key#\$}"
	value="${!varname}"
	if [ -n "$value" ] && [ "$value" != '0' ]; then
		key="$(echo $key | sed -e "s/\$U_//")"
		check_result "$E_EXISTS" "IP is in use / $key = $value"
	fi
}

# Update ip address value
update_ip_value() {
	key="$1"
	value="$2"
	# local empty = all lines; a foreign global would silently narrow the sed to one line
	local str_number=""
	conf="$CONF_DIR/ips/$ip"
	# See is_ip_key_empty: source_conf instead of eval-ing the file content as bash.
	[ -e "$conf" ] && source_conf "$conf"
	c_key=$(echo "${key//$/}")
	local varname="${key#\$}"
	old="${!varname}"
	old=$(echo "$old" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e 's/\//\\\//g')
	new=$(echo "$value" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e 's/\//\\\//g')
	sed -i "$str_number s/$c_key='${old//\*/\\*}'/$c_key='${new//\*/\\*}'/g" \
		$conf
}

# New method that is improved on a later date we need to check if we can improve it for other locations
update_ip_value_new() {
	key="$1"
	value="$2"
	conf="$CONF_DIR/ips/$ip"
	check_ckey=$(grep "^$key='" $conf)
	if [ -z "$check_ckey" ]; then
		echo "$key='$value'" >> $conf
	else
		sed -i "s|^$key=.*|$key='$value'|g" $conf
	fi
}

# Get ip name
get_ip_alias() {
	ip_name=$(grep "NAME=" $CONF_DIR/ips/$local_ip | cut -f 2 -d \')
	if [ -n "$ip_name" ]; then
		echo "${1//./-}.$ip_name"
	fi
}

# Increase ip value
increase_ip_value() {
	sip=${1-$ip}
	USER=${2-$user}
	web_key='U_WEB_DOMAINS'
	usr_key='U_SYS_USERS'
	current_web=$(grep "$web_key=" $CONF_DIR/ips/$sip | cut -f 2 -d \')
	current_usr=$(grep "$usr_key=" $CONF_DIR/ips/$sip | cut -f 2 -d \')
	if [ -z "$current_web" ]; then
		echo "Error: Parsing error"
		log_event "$E_PARSING" "$ARGUMENTS"
		exit "$E_PARSING"
	fi
	new_web=$((current_web + 1))
	if [ -z "$current_usr" ]; then
		new_usr="$USER"
	else
		check_usr=$(echo -e "${current_usr//,/\\n}" | grep -x "$USER")
		if [ -z "$check_usr" ]; then
			new_usr="$current_usr,$USER"
		else
			new_usr="$current_usr"
		fi
	fi

	# Make sure users list does not contain duplicates
	new_usr=$(echo "$new_usr" \
		| sed "s/,/\n/g" \
		| sort -u \
		| sed ':a;N;$!ba;s/\n/,/g')

	sed -i "s/$web_key='$current_web'/$web_key='$new_web'/g" \
		$CONF_DIR/ips/$sip
	sed -i "s/$usr_key='$current_usr'/$usr_key='$new_usr'/g" \
		$CONF_DIR/ips/$sip
}

# Decrease ip value
decrease_ip_value() {
	sip=${1-$ip}
	local user=${2-$user}
	web_key='U_WEB_DOMAINS'
	usr_key='U_SYS_USERS'

	current_web=$(grep "$web_key=" $CONF_DIR/ips/$sip | cut -f 2 -d \')
	current_usr=$(grep "$usr_key=" $CONF_DIR/ips/$sip | cut -f 2 -d \')

	if [ -z "$current_web" ]; then
		check_result $E_PARSING "Parsing error"
	fi

	new_web=$((current_web - 1))
	# One counting rule: the authority's check mode answers whether the user still holds
	# this address. Fail-safe: an oracle that answers nothing must not evict anyone.
	local recount_out recount
	recount_out=$("$BIN/h-update-sys-ip-counters" "$sip" check 2> /dev/null)
	recount=$(sed -n "s/^U_SYS_USERS='\(.*\)'\$/\1/p" <<< "$recount_out")
	check_ip=1
	if grep -q "^U_SYS_USERS=" <<< "$recount_out"; then
		if grep -qx "$user" <<< "${recount//,/$'\n'}"; then check_ip=1; else check_ip=0; fi
	fi
	if [[ $check_ip = 0 ]]; then
		new_usr=$(echo "$current_usr" \
			| sed "s/,/\n/g" \
			| sed "s/^$user$//g" \
			| sed "/^$/d" \
			| sort -u \
			| sed ':a;N;$!ba;s/\n/,/g')
	else
		new_usr="$current_usr"
	fi

	sed -i "s/$web_key='$current_web'/$web_key='$new_web'/g" \
		$CONF_DIR/ips/$sip
	sed -i "s/$usr_key='$current_usr'/$usr_key='$new_usr'/g" \
		$CONF_DIR/ips/$sip
}

# Get ip address value
get_ip_value() {
	key="$1"
	# See is_ip_key_empty: source_conf instead of eval-ing the file content as bash.
	[ -e "$CONF_DIR/ips/$ip" ] && source_conf "$CONF_DIR/ips/$ip"
	local varname="${key#\$}"
	value="${!varname}"
	echo "$value"
}

# Get real ip address
get_real_ip() {
	if [ -e "$CONF_DIR/ips/$1" ]; then
		echo "$1"
	else
		nat=$(grep -H "^NAT='$1'" $CONF_DIR/ips/* | head -n1)
		if [ -n "$nat" ]; then
			echo "$nat" | sed "s|:NAT=.*||; s|^$CONF_DIR/ips/||"
		fi
	fi
}

# Convert CIDR to netmask
convert_cidr() {
	set -- $((5 - ($1 / 8))) 255 255 255 255 \
		$(((255 << (8 - ($1 % 8))) & 255)) 0 0 0
	if [[ $1 -gt 1 ]]; then
		shift $1
	else
		shift
	fi
	echo ${1-0}.${2-0}.${3-0}.${4-0}
}

# Convert netmask to CIDR
convert_netmask() {
	nbits=0
	IFS=.
	for dec in $1; do
		case $dec in
			255) let nbits+=8 ;;
			254) let nbits+=7 ;;
			252) let nbits+=6 ;;
			248) let nbits+=5 ;;
			240) let nbits+=4 ;;
			224) let nbits+=3 ;;
			192) let nbits+=2 ;;
			128) let nbits+=1 ;;
			0) ;;
		esac
	done
	echo "$nbits"
}

# Calculate broadcast address
get_broadcast() {
	OLD_IFS=$IFS
	IFS=.
	typeset -a I=($1)
	typeset -a N=($2)
	IFS=$OLD_IFS

	echo "$((${I[0]} | (255 ^ ${N[0]}))).$((${I[1]} | (255 ^ ${N[1]}))).$((${I[2]} | (255 ^ ${N[2]}))).$((${I[3]} | (255 ^ ${N[3]})))"
}

# Get user ips (dedicated + shared), optionally filtered to one family ($1 = 4|6, empty = both).
# Cut at the literal ':KEY='/'-KEY=' boundary, never at the first colon: a v6 filename carries
# colons, and the old cut/REGEX_IPV4 pair made every v6 IP object invisible to every consumer.
get_user_ips() {
	# Per-file, per-key reads (key order is not a contract). Two passes, dedicated first:
	# get_user_ip takes head -n1, and glob order would hand a shared address to a customer
	# who owns a dedicated one.
	local family="$1" pass f addr f_owner f_status
	for pass in own shared; do
		for f in "$CONF_DIR"/ips/*; do
			[ -f "$f" ] || continue
			addr=${f##*/}
			if [ -n "$family" ] && [ "$(ip_family "$addr")" != "$family" ]; then
				continue
			fi
			f_owner=$(grep -m1 "^OWNER=" "$f" | cut -f 2 -d \')
			if [ "$pass" = 'own' ]; then
				[ "$f_owner" = "$user" ] && echo "$addr"
			else
				[ "$user" = "$ROOT_USER" ] && continue
				if [ "$f_owner" = "$ROOT_USER" ]; then
					f_status=$(grep -m1 "^STATUS=" "$f" | cut -f 2 -d \')
					[ "$f_status" = 'shared' ] && echo "$addr"
				fi
			fi
		done
	done
	return 0
}

# v4 preferred (existing boxes behave unchanged); only a v4-less box falls through to v6.
get_user_ip() {
	ip=$(get_user_ips 4 | head -n1)
	[ -z "$ip" ] && ip=$(get_user_ips 6 | head -n1)
	if [ -z "$ip" ]; then
		check_result $E_NOTEXIST "no IP is available"
	fi
	local_ip=$ip
	nat=$(grep "^NAT" $CONF_DIR/ips/$ip | cut -f 2 -d \')
	if [ -n "$nat" ]; then
		ip=$nat
	fi
}

# First v6 of the user into $ip6; rc 1 when none - callers decide, nothing aborts.
get_user_ip6() {
	ip6=$(get_user_ips 6 | head -n1)
	[ -n "$ip6" ]
}

# Validate ip address
is_ip_valid() {
	local_ip="$1"
	if [ ! -e "$CONF_DIR/ips/$1" ]; then
		nat=$(grep -H "^NAT='$1'" $CONF_DIR/ips/*)
		if [ -z "$nat" ]; then
			check_result "$E_NOTEXIST" "IP $1 doesn't exist"
		else
			nat=$(echo "$nat" | sed "s|:NAT=.*||; s|^$CONF_DIR/ips/||")
			local_ip=$nat
		fi
	fi
	if [ -n "$2" ]; then
		if [ -z "$nat" ]; then
			ip_data=$(cat $CONF_DIR/ips/$1)
		else
			ip_data=$(cat $CONF_DIR/ips/$nat)
		fi
		ip_owner=$(echo "$ip_data" | grep OWNER= | cut -f2 -d \')
		ip_status=$(echo "$ip_data" | grep STATUS= | cut -f2 -d \')
		if [ "$ip_owner" != "$user" ] && [ "$ip_status" = 'dedicated' ]; then
			check_result "$E_FORBIDEN" "$user user can't use IP $1"
		fi
		get_user_owner
		if [ "$ip_owner" != "$user" ] && [ "$ip_owner" != "$owner" ]; then
			check_result "$E_FORBIDEN" "$user user can't use IP $1"
		fi
	fi
}
