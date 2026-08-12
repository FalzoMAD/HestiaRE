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
