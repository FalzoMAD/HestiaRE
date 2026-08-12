# Shared companion lifecycle. The rootless daemon runs as its own account under
# user@<uid>.service with linger, so stopping it is more than one command and the
# order matters - callers that get it wrong leave processes holding the home.

# Stop a customer's companion and wait for its processes to go.
# Usage: companion_stop <companion account>   ->  0 even when the account is gone
companion_stop() {
	local companion="$1" companion_uid
	companion_uid="$(id -u "$companion" 2> /dev/null)" || return 0
	[ -n "$companion_uid" ] || return 0

	# linger first: it restarts the manager otherwise
	loginctl disable-linger "$companion" > /dev/null 2>&1
	loginctl terminate-user "$companion" > /dev/null 2>&1
	systemctl stop "user@${companion_uid}.service" "user-runtime-dir@${companion_uid}.service" > /dev/null 2>&1
	local _
	for _ in $(seq 1 20); do
		pgrep -u "$companion_uid" > /dev/null 2>&1 || break
		sleep 1
	done
	pkill -KILL -u "$companion_uid" > /dev/null 2>&1
	return 0
}

# Preset -> systemd properties for a companion slice. Percentages are native systemd syntax
# (of physical RAM, and 100% CPUQuota is one core), so a package value maps 1:1 with no maths.
# Empty output means "no cap" - the caller clears the properties then.
# Usage: docker_slice_properties <unlimited|low|medium|high>
docker_slice_properties() {
	case "$1" in
		low) echo "MemoryMax=10% CPUQuota=50% TasksMax=512" ;;
		medium) echo "MemoryMax=25% CPUQuota=100% TasksMax=1024" ;;
		high) echo "MemoryMax=50% CPUQuota=200% TasksMax=2048" ;;
		*) echo "" ;;
	esac
}

# Cap the companion slice, which is where the daemon AND every container of that customer live -
# their own user slice never sees them. Enforced against the customer's own daemon, so no compose
# file can talk its way out. A missing companion is not an error: docker is simply not enabled.
# Usage: docker_slice_apply <user> <preset>
docker_slice_apply() {
	local user="$1" preset="${2:-unlimited}" companion_uid slice props prop
	companion_uid="$(id -u "${user}-docker" 2> /dev/null)" || return 0
	[ -n "$companion_uid" ] || return 0
	slice="user-${companion_uid}.slice"

	props="$(docker_slice_properties "$preset")"
	if [ -z "$props" ]; then
		systemctl set-property "$slice" MemoryMax= CPUQuota= TasksMax= > /dev/null 2>&1
		return 0
	fi
	# shellcheck disable=SC2086  # each property is its own argument on purpose
	systemctl set-property "$slice" $props > /dev/null 2>&1
	for prop in $props; do
		[ "$(systemctl show "$slice" -p "${prop%%=*}" --value 2> /dev/null)" = 'infinity' ] \
			&& echo "Warning: ${prop%%=*} did not take on $slice" >&2
	done
	return 0
}
