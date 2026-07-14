#!/bin/bash
# info: reset HestiaRE test VMs — restore from local backup, then unattended install
#
# RUNS ON THE PROXMOX HOST (needs `qm`/`qmrestore` + the local vzdump backups).
# For each VM it: stops it, restores the latest local backup (--force, DESTRUCTIVE),
# starts it, waits for SSH, then fetches install.sh and runs the fasttrack
# unattended install (`install.sh <preset> -a`, #198), and finally reports the
# smoke-test result.
#
# The backups are expected to be clean-base-OS vzdumps (pre-HestiaRE); the
# restore wipes whatever HestiaRE install was there and the script installs
# fresh. This is a DEV/TEST-INFRA tool — not part of the shipped product.
#
# Usage (on the Proxmox host, as root):
#   tools/reset-test-vms.sh                 # all VMs, preset 'standard', asks first
#   tools/reset-test-vms.sh -y              # no confirmation prompt
#   tools/reset-test-vms.sh --only 412,413  # subset by VMID
#   tools/reset-test-vms.sh --preset mailonly
#   tools/reset-test-vms.sh --no-install    # restore + start only, install manually
#   tools/reset-test-vms.sh --dry-run       # print what would happen, change nothing
#
# Config via env (or edit the defaults below):
#   VM_MAP        "vmid=ip vmid=ip ..."  VMID -> reachable IP for SSH
#   PRESET        install preset (standard|compact|latest|singlephp|nomail|mailonly)
#   DUMP_DIR      vzdump backup directory (default /var/lib/vz/dump)
#   INSTALL_URL   bootstrap URL (default https://hestiare.com/install.sh)
#   SSH_USER      user to SSH into the VMs as (default root)
#   SSH_OPTS      extra ssh options
#   SSH_WAIT      seconds to wait for SSH after start (default 240)

set -uo pipefail

# ── Config / defaults ───────────────────────────────────────────────────────
VM_MAP="${VM_MAP:-412=10.4.4.12 413=10.4.4.13 424=10.4.4.24 426=10.4.4.26}"
PRESET="${PRESET:-standard}"
DUMP_DIR="${DUMP_DIR:-/var/lib/vz/dump}"
INSTALL_URL="${INSTALL_URL:-https://hestiare.com/install.sh}"
SSH_USER="${SSH_USER:-root}"
SSH_WAIT="${SSH_WAIT:-240}"
SSH_OPTS="${SSH_OPTS:--o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes}"

ASSUME_YES=false
DRY_RUN=false
DO_INSTALL=true
ONLY=""

# ── Args ────────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
	case "$1" in
		-y | --yes)     ASSUME_YES=true ;;
		--dry-run)      DRY_RUN=true ;;
		--no-install)   DO_INSTALL=false ;;
		--preset)       PRESET="$2"; shift ;;
		--preset=*)     PRESET="${1#*=}" ;;
		--only)         ONLY="$2"; shift ;;
		--only=*)       ONLY="${1#*=}" ;;
		--dump-dir)     DUMP_DIR="$2"; shift ;;
		--dump-dir=*)   DUMP_DIR="${1#*=}" ;;
		-h | --help)    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*)              echo "ERROR: unknown argument: $1 (see --help)" >&2; exit 1 ;;
	esac
	shift
done

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

# wait_ssh <ip> — poll until SSH answers or SSH_WAIT elapses
wait_ssh() {
	local ip="$1" waited=0
	# The restored VM keeps its old host key; drop any stale entry just in case.
	ssh-keygen -R "$ip" > /dev/null 2>&1 || true
	while [ "$waited" -lt "$SSH_WAIT" ]; do
		# shellcheck disable=SC2086
		if ssh $SSH_OPTS "$SSH_USER@$ip" true 2> /dev/null; then
			return 0
		fi
		sleep 5
		waited=$((waited + 5))
	done
	return 1
}

# ── Preflight ───────────────────────────────────────────────────────────────
if [ "$DRY_RUN" != true ]; then
	[ "$(id -u)" = "0" ] || die "must run as root on the Proxmox host (qm/qmrestore need root)."
fi
if [ "$DRY_RUN" != true ]; then
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
echo "Preset: $PRESET   Install: $DO_INSTALL   Dump dir: $DUMP_DIR"
if [ "$ASSUME_YES" != true ] && [ "$DRY_RUN" != true ]; then
	printf 'Type "yes" to proceed: '
	read -r _confirm
	[ "$_confirm" = "yes" ] || die "aborted by user."
fi

# ── Per-VM reset ────────────────────────────────────────────────────────────
declare -a RESULTS=()
reset_one() {
	local vmid="$1" ip="$2" bk rc
	log "VM $vmid ($ip): starting reset"

	bk="$(latest_backup "$vmid")"
	[ -n "$bk" ] || { warn "VM $vmid: no backup found in $DUMP_DIR — skipping"; return 1; }
	log "VM $vmid: latest backup = $bk"

	# Stop (ignore error if already stopped)
	log "VM $vmid: stopping"
	run "qm stop $vmid --skiplock 2>/dev/null || true"
	# Wait for it to actually be stopped
	if [ "$DRY_RUN" != true ]; then
		for _ in $(seq 1 24); do
			[ "$(qm status "$vmid" 2>/dev/null | awk '{print $2}')" = "stopped" ] && break
			sleep 5
		done
	fi

	# Restore (destructive, --force overwrites the existing VM)
	log "VM $vmid: restoring from backup (--force)"
	run "qmrestore '$bk' $vmid --force" || { warn "VM $vmid: qmrestore failed"; return 1; }

	# Start
	log "VM $vmid: starting"
	run "qm start $vmid" || { warn "VM $vmid: qm start failed"; return 1; }

	if [ "$DO_INSTALL" != true ]; then
		ok "VM $vmid: restored and started (install skipped)"
		return 0
	fi

	# Wait for SSH
	log "VM $vmid: waiting for SSH on $ip (up to ${SSH_WAIT}s)"
	if [ "$DRY_RUN" = true ]; then
		echo "  (dry-run) would wait for ssh $SSH_USER@$ip, then run install.sh $PRESET -a"
		return 0
	fi
	wait_ssh "$ip" || { warn "VM $vmid: SSH did not come up within ${SSH_WAIT}s"; return 1; }

	# Fetch + run the unattended install
	log "VM $vmid: fetching install.sh and running '$PRESET -a'"
	# shellcheck disable=SC2086
	ssh $SSH_OPTS "$SSH_USER@$ip" \
		"curl -fsSL '$INSTALL_URL' -o /root/install.sh && bash /root/install.sh '$PRESET' -a"
	rc=$?
	[ "$rc" -eq 0 ] || { warn "VM $vmid: install.sh exited $rc"; return 1; }

	# Smoke test
	log "VM $vmid: running smoke test"
	# shellcheck disable=SC2086
	if ssh $SSH_OPTS "$SSH_USER@$ip" "/usr/local/hestia/bin/h-check-sys-smoke"; then
		ok "VM $vmid: install + smoke PASSED"
	else
		warn "VM $vmid: smoke test reported failures (see output above)"
		return 1
	fi
	return 0
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
echo "=== reset summary ==="
fail=0
for r in "${RESULTS[@]}"; do
	echo "  $r"
	case "$r" in *FAILED) fail=1 ;; esac
done
[ "$fail" -eq 0 ] || exit 1
exit 0
