#!/bin/bash
# info: reset HestiaRE test VMs — restore from local backup, then unattended install
#
# RUNS ON THE PROXMOX HOST (needs `qm`/`qmrestore` + the local vzdump backups).
# For each VM it: stops it, restores the latest local backup (--force, DESTRUCTIVE),
# starts it, waits until it is reachable, then fetches install.sh and runs the
# fasttrack unattended install (`install.sh <preset> -a`, #198), finishing with
# h-check-sys-smoke.
#
# The backups are expected to be clean-base-OS vzdumps (pre-HestiaRE); the
# restore wipes whatever was there and the script installs fresh. This is a
# DEV/TEST-INFRA tool — not part of the shipped product.
#
# TRANSPORT — how commands get INTO the VM (default: agent):
#   agent  QEMU Guest Agent via `qm guest exec` — NO SSH keys needed. REQUIRES
#          `qemu-guest-agent` installed+running in the base OS image; the script
#          sets `agent: 1` on the VM config automatically before start.
#   ssh    plain SSH (needs the host's key deposited on the VMs, StrictHostKey
#          accept-new). Use `--via ssh` once keys are in place.
#
# Usage (on the Proxmox host, as root):
#   tools/reset-test-vms.sh                 # all VMs, preset 'standard', asks first
#   tools/reset-test-vms.sh -y              # no confirmation prompt
#   tools/reset-test-vms.sh --only 412,413  # subset by VMID
#   tools/reset-test-vms.sh --preset mailonly
#   tools/reset-test-vms.sh --via ssh       # use SSH instead of the guest agent
#   tools/reset-test-vms.sh --no-install    # restore + start only, install manually
#   tools/reset-test-vms.sh --dry-run       # print what would happen, change nothing
#
# Config via env (or edit the defaults below):
#   VM_MAP          "vmid=ip vmid=ip ..."  VMID -> IP (IP only used for --via ssh)
#   PRESET          install preset (standard|compact|latest|singlephp|nomail|mailonly)
#   TRANSPORT       agent | ssh   (default agent)
#   DUMP_DIR        vzdump backup directory (default /var/lib/vz/dump)
#   INSTALL_URL     bootstrap URL
#   INSTALL_TIMEOUT seconds to allow the install to run (default 1800)
#   READY_WAIT      seconds to wait for agent/SSH after start (default 240)
#   SSH_USER        user for --via ssh (default root)
#   SSH_OPTS        extra ssh options for --via ssh

set -uo pipefail

# ── Config / defaults ───────────────────────────────────────────────────────
VM_MAP="${VM_MAP:-412=10.4.4.12 413=10.4.4.13 424=10.4.4.24 426=10.4.4.26}"
PRESET="${PRESET:-standard}"
TRANSPORT="${TRANSPORT:-agent}"
DUMP_DIR="${DUMP_DIR:-/var/lib/vz/dump}"
# hestiare.com/install.sh is the eventual canonical bootstrap, but that host is
# not set up yet — default to the raw install.sh from the public mirror's main
# branch. Override via INSTALL_URL when hestiare.com goes live.
INSTALL_URL="${INSTALL_URL:-https://raw.githubusercontent.com/FalzoMAD/HestiaRE/refs/heads/main/install.sh}"
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-1800}"
READY_WAIT="${READY_WAIT:-240}"
SSH_USER="${SSH_USER:-root}"
SSH_OPTS="${SSH_OPTS:--o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes}"

ASSUME_YES=false
DRY_RUN=false
DO_INSTALL=true
ONLY=""
GUEST_RC=0

# ── Args ────────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
	case "$1" in
		-y | --yes)     ASSUME_YES=true ;;
		--dry-run)      DRY_RUN=true ;;
		--no-install)   DO_INSTALL=false ;;
		--via)          TRANSPORT="$2"; shift ;;
		--via=*)        TRANSPORT="${1#*=}" ;;
		--preset)       PRESET="$2"; shift ;;
		--preset=*)     PRESET="${1#*=}" ;;
		--only)         ONLY="$2"; shift ;;
		--only=*)       ONLY="${1#*=}" ;;
		--dump-dir)     DUMP_DIR="$2"; shift ;;
		--dump-dir=*)   DUMP_DIR="${1#*=}" ;;
		-h | --help)    sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*)              echo "ERROR: unknown argument: $1 (see --help)" >&2; exit 1 ;;
	esac
	shift
done

case "$TRANSPORT" in agent | ssh) ;; *) echo "ERROR: --via must be 'agent' or 'ssh'" >&2; exit 1 ;; esac

# ── Helpers ─────────────────────────────────────────────────────────────────
log()  { echo "[ * ] $*"; }
ok()   { echo "[ OK ] $*"; }
warn() { echo "[ ! ] $*" >&2; }
die()  { echo "[FAIL] $*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = true ]; then echo "  (dry-run) $*"; else eval "$@"; fi; }

# latest_backup <vmid> — newest vzdump archive for this VMID, or empty
latest_backup() {
	local vmid="$1"
	ls -1t "$DUMP_DIR"/vzdump-qemu-"$vmid"-*.vma.zst \
		"$DUMP_DIR"/vzdump-qemu-"$vmid"-*.vma.gz \
		"$DUMP_DIR"/vzdump-qemu-"$vmid"-*.vma.lzo \
		"$DUMP_DIR"/vzdump-qemu-"$vmid"-*.vma 2> /dev/null | head -n 1
}

# wait_ready <vmid> <ip> — poll until the VM answers (agent ping or SSH)
wait_ready() {
	local vmid="$1" ip="$2" waited=0
	if [ "$TRANSPORT" = ssh ]; then
		ssh-keygen -R "$ip" > /dev/null 2>&1 || true
	fi
	while [ "$waited" -lt "$READY_WAIT" ]; do
		if [ "$TRANSPORT" = agent ]; then
			qm agent "$vmid" ping > /dev/null 2>&1 && return 0
		else
			# shellcheck disable=SC2086
			ssh $SSH_OPTS "$SSH_USER@$ip" true 2> /dev/null && return 0
		fi
		sleep 5
		waited=$((waited + 5))
	done
	return 1
}

# remote_run <vmid> <ip> <timeout> <shell-command> — run inside the guest.
# Sets GUEST_RC to the command's exit code. Returns 0 if it completed (regardless
# of GUEST_RC), 1 if the transport failed / timed out.
remote_run() {
	local vmid="$1" ip="$2" timeout="$3" cmd="$4"
	GUEST_RC=0
	if [ "$TRANSPORT" = ssh ]; then
		# shellcheck disable=SC2086
		timeout "$timeout" ssh $SSH_OPTS "$SSH_USER@$ip" "$cmd"
		GUEST_RC=$?
		return 0
	fi
	# agent: start async, then poll exec-status until it exits.
	local pid js waited=0
	pid=$(qm guest exec "$vmid" --synchronous 0 -- bash -lc "$cmd" 2> /dev/null \
		| grep -oE '"pid"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
	[ -n "$pid" ] || { warn "VM $vmid: guest agent did not accept the command (agent not installed/running?)"; return 1; }
	while [ "$waited" -lt "$timeout" ]; do
		js=$(qm guest exec-status "$vmid" "$pid" 2> /dev/null)
		if echo "$js" | grep -qE '"exited"[[:space:]]*:[[:space:]]*(1|true)'; then
			GUEST_RC=$(echo "$js" | grep -oE '"exitcode"[[:space:]]*:[[:space:]]*-?[0-9]+' | grep -oE '\-?[0-9]+' | tail -1)
			GUEST_RC=${GUEST_RC:-0}
			return 0
		fi
		sleep 5
		waited=$((waited + 5))
	done
	warn "VM $vmid: guest command did not finish within ${timeout}s"
	return 1
}

# ── Preflight ───────────────────────────────────────────────────────────────
if [ "$DRY_RUN" != true ]; then
	[ "$(id -u)" = "0" ] || die "must run as root on the Proxmox host (qm/qmrestore need root)."
	command -v qm > /dev/null 2>&1 || die "'qm' not found — is this a Proxmox VE host?"
	command -v qmrestore > /dev/null 2>&1 || die "'qmrestore' not found — is this a Proxmox VE host?"
fi

# Build the working list of "vmid ip" pairs, honouring --only.
declare -a TARGETS=()
for pair in $VM_MAP; do
	vmid="${pair%%=*}"; ip="${pair#*=}"
	[ "$vmid" = "$ip" ] && die "bad VM_MAP entry '$pair' (expected vmid=ip)."
	if [ -n "$ONLY" ]; then
		case ",$ONLY," in *",$vmid,"*) ;; *) continue ;; esac
	fi
	TARGETS+=("$vmid=$ip")
done
[ "${#TARGETS[@]}" -gt 0 ] || die "no target VMs (check --only / VM_MAP)."

echo "About to RESET these test VMs (restore from latest local backup — DESTROYS current state):"
for t in "${TARGETS[@]}"; do
	vmid="${t%%=*}"; ip="${t#*=}"
	bk="$(latest_backup "$vmid")"
	printf '   VM %-5s  ip %-12s  backup: %s\n' "$vmid" "$ip" "${bk:-<NONE FOUND>}"
done
echo "Preset: $PRESET   Transport: $TRANSPORT   Install: $DO_INSTALL   Dump dir: $DUMP_DIR"
[ "$TRANSPORT" = agent ] && echo "Note: transport 'agent' needs qemu-guest-agent in the base image."
if [ "$ASSUME_YES" != true ] && [ "$DRY_RUN" != true ]; then
	printf 'Type "yes" to proceed: '
	read -r _confirm
	[ "$_confirm" = "yes" ] || die "aborted by user."
fi

# ── Per-VM reset ────────────────────────────────────────────────────────────
declare -a RESULTS=()
reset_one() {
	local vmid="$1" ip="$2" bk

	log "VM $vmid ($ip): starting reset"
	bk="$(latest_backup "$vmid")"
	[ -n "$bk" ] || { warn "VM $vmid: no backup found in $DUMP_DIR — skipping"; return 1; }
	log "VM $vmid: latest backup = $bk"

	# Stop (ignore error if already stopped), then wait for it to be stopped
	log "VM $vmid: stopping"
	run "qm stop $vmid --skiplock 2>/dev/null || true"
	if [ "$DRY_RUN" != true ]; then
		for _ in $(seq 1 24); do
			[ "$(qm status "$vmid" 2>/dev/null | awk '{print $2}')" = "stopped" ] && break
			sleep 5
		done
	fi

	# Restore (destructive, --force overwrites the existing VM)
	log "VM $vmid: restoring from backup (--force)"
	run "qmrestore '$bk' $vmid --force" || { warn "VM $vmid: qmrestore failed"; return 1; }

	# Ensure the guest-agent channel exists (idempotent) when using it
	if [ "$TRANSPORT" = agent ]; then
		log "VM $vmid: enabling guest-agent channel (agent=1)"
		run "qm set $vmid --agent 1 >/dev/null"
	fi

	# Start
	log "VM $vmid: starting"
	run "qm start $vmid" || { warn "VM $vmid: qm start failed"; return 1; }

	if [ "$DO_INSTALL" != true ]; then
		ok "VM $vmid: restored and started (install skipped)"
		return 0
	fi
	if [ "$DRY_RUN" = true ]; then
		echo "  (dry-run) would wait for $TRANSPORT, then run install.sh $PRESET -a + smoke"
		return 0
	fi

	# Wait until reachable
	log "VM $vmid: waiting for $TRANSPORT (up to ${READY_WAIT}s)"
	wait_ready "$vmid" "$ip" || { warn "VM $vmid: $TRANSPORT not reachable within ${READY_WAIT}s"; return 1; }

	# Fetch + run the unattended install (output to a log inside the VM)
	log "VM $vmid: installing ('$PRESET -a', up to ${INSTALL_TIMEOUT}s)"
	remote_run "$vmid" "$ip" "$INSTALL_TIMEOUT" \
		"curl -fsSL '$INSTALL_URL' -o /root/install.sh && bash /root/install.sh '$PRESET' -a >/root/install.log 2>&1" \
		|| { warn "VM $vmid: install transport failed"; return 1; }
	if [ "${GUEST_RC:-1}" -ne 0 ]; then
		warn "VM $vmid: install.sh exited $GUEST_RC (inspect /root/install.log in the VM, e.g. qm guest exec $vmid -- tail -n 40 /root/install.log)"
		return 1
	fi

	# Smoke test
	log "VM $vmid: running smoke test"
	remote_run "$vmid" "$ip" 180 \
		"/usr/local/hestia/bin/h-check-sys-smoke >/root/smoke.log 2>&1" \
		|| { warn "VM $vmid: smoke transport failed"; return 1; }
	if [ "${GUEST_RC:-1}" -eq 0 ]; then
		ok "VM $vmid: install + smoke PASSED"
		return 0
	else
		warn "VM $vmid: smoke reported failures (qm guest exec $vmid -- cat /root/smoke.log)"
		return 1
	fi
}

for t in "${TARGETS[@]}"; do
	vmid="${t%%=*}"; ip="${t#*=}"
	echo "──────────────────────────────────────────────────────────────"
	if reset_one "$vmid" "$ip"; then
		RESULTS+=("$vmid: OK")
	else
		RESULTS+=("$vmid: FAILED")
	fi
done

# ── Summary ─────────────────────────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────────"
echo "=== reset summary (transport: $TRANSPORT, preset: $PRESET) ==="
fail=0
for r in "${RESULTS[@]}"; do
	echo "  $r"
	case "$r" in *FAILED) fail=1 ;; esac
done
[ "$fail" -eq 0 ] || exit 1
exit 0
