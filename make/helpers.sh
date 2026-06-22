# Sourced by make recipes — spinner + apt wrapper
# Requires: LOG env var (exported from Makefile)

_hestia_spin_pid=""

_hestia_spin_start() {
    ( s='/-\|'
      i=0
      while true; do
          printf '\r  %s ' "${s:$((i % 4)):1}" >&2
          sleep 0.15
          i=$((i + 1))
      done
    ) &
    _hestia_spin_pid=$!
}

_hestia_spin_stop() {
    [ -n "$_hestia_spin_pid" ] || return 0
    kill "$_hestia_spin_pid" 2>/dev/null || true
    wait "$_hestia_spin_pid" 2>/dev/null || true
    printf '\r\033[K' >&2
    _hestia_spin_pid=""
}

# stdout (verbose package text) → log only
# stderr (apt errors/warnings)  → terminal + log
# spinner runs while apt executes for visual liveness
# Usage: hestia_apt [apt-get args...]
hestia_apt() {
    _hestia_spin_start
    local _rc=0
    DEBIAN_FRONTEND=noninteractive apt-get "$@" \
        1>> "${LOG}" \
        2> >(tee -a "${LOG}" >&2) || _rc=$?
    _hestia_spin_stop
    return $_rc
}
