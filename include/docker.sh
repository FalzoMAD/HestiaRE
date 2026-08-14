#!/bin/bash

# Shared companion lifecycle. The rootless daemon runs as its own account under
# user@<uid>.service with linger, so stopping it is more than one command and the
# order matters - callers that get it wrong leave processes holding the home.
# Every function here takes the CUSTOMER, never the companion account: the naming
# convention lives in companion_name and nowhere else.

# Usage: companion_name <user>   ->  the customer's companion account name
companion_name() {
	echo "${1}-docker"
}

# Stop a customer's companion and wait for its processes to go.
# Usage: companion_stop <user>  ->  1 if anything is still running, so a caller that is
# about to write into the companion home can refuse. Linger is NOT touched: that is an
# autostart property, not part of stopping, and only the delete path wants it gone.
companion_stop() {
	local companion companion_uid _
	companion="$(companion_name "$1")"
	companion_uid="$(id -u "$companion" 2> /dev/null)" || return 0
	[ -n "$companion_uid" ] || return 0
	if [ "$(id -u)" != '0' ]; then
		echo "ERROR: stopping the companion needs root" >&2
		return 1
	fi

	loginctl terminate-user "$companion" > /dev/null 2>&1
	systemctl stop "user@${companion_uid}.service" "user-runtime-dir@${companion_uid}.service" > /dev/null 2>&1
	for _ in $(seq 1 20); do
		pgrep -u "$companion_uid" > /dev/null 2>&1 || break
		sleep 1
	done
	pkill -KILL -u "$companion_uid" > /dev/null 2>&1
	sleep 1
	# A KILL does not clear an uninterruptible process, and "stopped" has to mean stopped -
	# the whole point of the caller stopping first is that nothing writes to the home.
	if pgrep -u "$companion_uid" > /dev/null 2>&1; then
		echo "ERROR: companion $companion still has processes ($(pgrep -u "$companion_uid" | tr '\n' ' '))" >&2
		return 1
	fi
	return 0
}

# Autostart, separate from stopping: the delete path wants it gone, a restore does not.
# Usage: companion_disable_linger <user>
companion_disable_linger() {
	loginctl disable-linger "$(companion_name "$1")" > /dev/null 2>&1
	return 0
}

# Preset -> systemd properties for a companion slice. Percentages are native systemd syntax
# (of physical RAM, and 100% CPUQuota is one core), so a package value maps 1:1 with no maths.
# Usage: docker_slice_properties <unlimited|low|medium|high>  ->  1 on an unknown preset,
# which must not read as "no cap": a typo would silently uncap the customer.
docker_slice_properties() {
	case "$1" in
		unlimited | '') echo "" ;;
		low) echo "MemoryMax=10% CPUQuota=50% TasksMax=512" ;;
		medium) echo "MemoryMax=25% CPUQuota=100% TasksMax=1024" ;;
		high) echo "MemoryMax=50% CPUQuota=200% TasksMax=2048" ;;
		*) return 1 ;;
	esac
}

# Cap the companion slice, which is where the daemon AND every container of that customer live -
# their own user slice never sees them. Enforced against the customer's own daemon, so no compose
# file can talk its way out. A missing companion is not an error: docker is simply not enabled.
# Usage: docker_slice_apply <user> <preset>
docker_slice_apply() {
	local user="$1" preset="${2:-unlimited}" companion_uid slice props prop name shown
	companion_uid="$(id -u "$(companion_name "$user")" 2> /dev/null)" || return 0
	[ -n "$companion_uid" ] || return 0
	slice="user-${companion_uid}.slice"

	if ! props="$(docker_slice_properties "$preset")"; then
		echo "Warning: unknown docker resource preset '$preset' for $user - slice left as it is" >&2
		return 1
	fi
	if [ -z "$props" ]; then
		systemctl set-property "$slice" MemoryMax= CPUQuota= TasksMax= > /dev/null 2>&1
		return 0
	fi
	# shellcheck disable=SC2086  # each property is its own argument on purpose
	systemctl set-property "$slice" $props > /dev/null 2>&1
	for prop in $props; do
		name="${prop%%=*}"
		# CPUQuota is write-only: systemd reports it back as CPUQuotaPerSecUSec
		[ "$name" = 'CPUQuota' ] && name='CPUQuotaPerSecUSec'
		shown="$(systemctl show "$slice" -p "$name" --value 2> /dev/null)"
		case "$shown" in
			'' | infinity) echo "Warning: ${prop%%=*} did not take on $slice" >&2 ;;
		esac
	done
	return 0
}

# Drop a companion's cap and the drop-in systemd persisted for it. The uid is reused by a later
# customer's companion, and an inherited limit with no visible cause is worse than no limit.
# Usage: docker_slice_clear <user>
docker_slice_clear() {
	local companion_uid
	companion_uid="$(id -u "$(companion_name "$1")" 2> /dev/null)" || return 0
	[ -n "$companion_uid" ] || return 0
	systemctl set-property "user-${companion_uid}.slice" MemoryMax= CPUQuota= TasksMax= > /dev/null 2>&1
	rm -rf "/etc/systemd/system.control/user-${companion_uid}.slice.d"
	systemctl daemon-reload > /dev/null 2>&1
	return 0
}
