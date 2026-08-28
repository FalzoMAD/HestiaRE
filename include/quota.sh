#!/bin/bash
# Project quota for /home (#211): classification, arming, enforcement witness.
#
# Quota is base behaviour, not a module: the installer arms whenever the filesystem
# under /home supports it, without asking. The capability lives in the hestia.conf
# key PROJECT_QUOTA = active | pending:<reason> | none:<reason>. The key is written
# from MEASUREMENT (quota_enforce_probe), never from classification alone - the
# class only picks the arming path. Measured liars this design routes around:
#   - remount with prjquota: rc=0, option visible in findmnt, quotaon -pP says "on",
#     and nothing is enforced (ext4 AND xfs, both measured)
#   - ext4 features quota,project: settable on an UNMOUNTED fs only, so an existing
#     root fs is armed by a one-shot initramfs premount hook across the reboot the
#     installer demands anyway
#   - quotaon -P activates ext4 enforcement without any mount option, but it is
#     RUNTIME state: the persistent boot unit re-applies it on every boot
#   - root bypasses ext4 project quota (restore never dies on it); XFS enforces
#     against root too - which is why the probe writes as uid 65534

# Throwaway project id for the witness - outside any real customer UID band.
QUOTA_PROBE_PRJID=999999
QUOTA_ARM_STATUS=/run/hestia-quota-arm.status
QUOTA_UNIT='hestia-quota-on.service'
QUOTA_HOOK=/etc/initramfs-tools/hooks/hestia-quota
QUOTA_PREMOUNT=/etc/initramfs-tools/scripts/local-premount/hestia-quota
QUOTA_GRUB_DROPIN=/etc/default/grub.d/hestia-quota.cfg

# Fills QUOTA_MNT / QUOTA_DEV / QUOTA_FSTYPE for the mount that carries /home.
quota_home_fs() {
	local homedir="${HOMEDIR:-/home}"
	read -r QUOTA_MNT QUOTA_DEV QUOTA_FSTYPE < <(findmnt -no TARGET,SOURCE,FSTYPE -T "$homedir" 2> /dev/null)
	[ -n "$QUOTA_MNT" ]
}

# One oracle, two callers (installer/boot flip + smoke): does this filesystem
# ENFORCE project quota right now? Writes as uid 65534 - root legitimately
# bypasses ext4 project quota, a root writer would prove nothing. Positive
# control in the same run: the same writer must pass once the cap is lifted.
# On failure QUOTA_PROBE_REASON names why. Cleanup runs from a trap: an aborted
# probe must not leave a capped project directory under /home.
quota_enforce_probe() {
	local mnt="$1" out
	QUOTA_PROBE_REASON=''
	[ -d "$mnt" ] || {
		QUOTA_PROBE_REASON="mountpoint $mnt missing"
		return 1
	}
	out=$(
		dir=$(mktemp -d "$mnt/.hestia-qprobe.XXXXXX") || {
			echo "mktemp failed on $mnt"
			exit 1
		}
		trap 'setquota -P '"$QUOTA_PROBE_PRJID"' 0 0 0 0 "$mnt" 2> /dev/null; rm -rf "$dir"' EXIT INT TERM
		chattr -p "$QUOTA_PROBE_PRJID" +P "$dir" 2> /dev/null || {
			echo "no project id support (chattr -p refused)"
			exit 1
		}
		chown 65534:65534 "$dir" && chmod 700 "$dir"
		setquota -P "$QUOTA_PROBE_PRJID" 0 4 0 0 "$mnt" 2> /dev/null || {
			echo "setquota -P refused"
			exit 1
		}
		if setpriv --reuid 65534 --regid 65534 --clear-groups \
			dd if=/dev/zero of="$dir/probe" bs=64k count=4 > /dev/null 2>&1; then
			echo "cap not enforced (write passed the 4KB hard limit)"
			exit 1
		fi
		rm -f "$dir/probe"
		setquota -P "$QUOTA_PROBE_PRJID" 0 0 0 0 "$mnt" 2> /dev/null
		if ! setpriv --reuid 65534 --regid 65534 --clear-groups \
			dd if=/dev/zero of="$dir/probe" bs=64k count=4 > /dev/null 2>&1; then
			echo "positive control failed (write blocked with cap lifted)"
			exit 1
		fi
		exit 0
	) && return 0
	QUOTA_PROBE_REASON="${out:-unknown}"
	return 1
}

quota_set_key() {
	"$BIN/h-change-sys-config-value" 'PROJECT_QUOTA' "$1" > /dev/null 2>&1 \
		|| sed -i "s|^PROJECT_QUOTA=.*|PROJECT_QUOTA='$1'|" "$HESTIA/conf/hestia.conf"
}

quota_install_unit() {
	install -m 644 "$HESTIA/share/quota/systemd/$QUOTA_UNIT" "/etc/systemd/system/$QUOTA_UNIT" || return 1
	systemctl daemon-reload
	systemctl enable "$QUOTA_UNIT" > /dev/null 2>&1
}

quota_install_initramfs_hook() {
	# copy_exec pair: e2fsck ships in the initramfs, tune2fs does NOT (measured
	# deb13+ub24) - without the hook the premount step dies on command-not-found
	# and the box stays pending forever, silently.
	install -m 755 "$HESTIA/share/quota/initramfs/hestia-quota.hook" "$QUOTA_HOOK" || return 1
	install -m 755 "$HESTIA/share/quota/initramfs/hestia-quota.premount" "$QUOTA_PREMOUNT" || return 1
	update-initramfs -u > /dev/null 2>&1
}

quota_remove_initramfs_hook() {
	[ -f "$QUOTA_HOOK" ] || [ -f "$QUOTA_PREMOUNT" ] || return 0
	rm -f "$QUOTA_HOOK" "$QUOTA_PREMOUNT"
	update-initramfs -u > /dev/null 2>&1
}

# Installer entry point. Must run before any customer user exists: the
# separate-/home paths need the mount free for umount.
quota_arm() {
	local reason
	if ! quota_home_fs; then
		quota_set_key "none:home-mount-unresolved"
		echo "[ ! ] project quota: cannot resolve the /home mount - not armed"
		return 0
	fi

	# Already enforcing (pre-armed image, re-run): measure first, classify never.
	if quota_enforce_probe "$QUOTA_MNT"; then
		[ "$QUOTA_FSTYPE" = 'ext4' ] && quota_install_unit
		quota_set_key "active"
		echo "[ OK ] project quota enforcing on $QUOTA_MNT ($QUOTA_FSTYPE)"
		return 0
	fi

	case "$QUOTA_FSTYPE" in
		ext4)
			if tune2fs -l "$QUOTA_DEV" 2> /dev/null | grep -q '^Filesystem features:.*project'; then
				# features already on disk, enforcement just not activated
				quotaon -P "$QUOTA_MNT" > /dev/null 2>&1
				quota_install_unit
				if quota_enforce_probe "$QUOTA_MNT"; then
					quota_set_key "active"
					echo "[ OK ] project quota activated on $QUOTA_MNT (ext4)"
				else
					quota_set_key "none:${QUOTA_PROBE_REASON// /-}"
					echo "[ ! ] project quota: features present but probe failed: $QUOTA_PROBE_REASON"
				fi
			elif [ "$QUOTA_MNT" = '/' ]; then
				# root fs: features are settable unmounted only - one-shot premount
				# hook across the reboot the installer demands anyway
				if quota_install_initramfs_hook && quota_install_unit; then
					quota_set_key "pending:reboot"
					echo "[ * ] project quota: armed via initramfs one-shot - active after the reboot"
				else
					quota_set_key "none:initramfs-hook-install-failed"
					echo "[ ! ] project quota: could not install the initramfs hook - not armed"
				fi
			else
				# separate /home: arm online, the mount is free at this install stage
				if ! umount "$QUOTA_MNT" 2> /dev/null; then
					quota_set_key "none:home-umount-failed"
					echo "[ ! ] project quota: $QUOTA_MNT is busy - not armed"
					return 0
				fi
				e2fsck -p "$QUOTA_DEV" > /dev/null 2>&1
				rc=$?
				if [ "$rc" -gt 1 ]; then
					mount "$QUOTA_MNT" 2> /dev/null
					quota_set_key "none:e2fsck-rc$rc"
					echo "[ ! ] project quota: e2fsck on $QUOTA_DEV returned $rc - not armed"
					return 0
				fi
				tune2fs -O quota,project "$QUOTA_DEV" > /dev/null 2>&1
				mount "$QUOTA_MNT" || mount "$QUOTA_DEV" "$QUOTA_MNT"
				quotaon -P "$QUOTA_MNT" > /dev/null 2>&1
				quota_install_unit
				if quota_enforce_probe "$QUOTA_MNT"; then
					quota_set_key "active"
					echo "[ OK ] project quota activated on $QUOTA_MNT (ext4, separate)"
				else
					quota_set_key "none:${QUOTA_PROBE_REASON// /-}"
					echo "[ ! ] project quota: armed but probe failed: $QUOTA_PROBE_REASON"
				fi
			fi
			;;
		xfs)
			if [ "$QUOTA_MNT" = '/' ]; then
				# xfs quota is mount-option-only and remount is a silent no-op
				# (measured) - the root fs needs rootflags at the original mount
				if grep -rqs 'rootflags=' /etc/default/grub /etc/default/grub.d/ 2> /dev/null; then
					quota_set_key "pending:manual-rootflags-conflict"
					echo "[ ! ] project quota: rootflags already set in GRUB config - add prjquota by hand"
					return 0
				fi
				mkdir -p /etc/default/grub.d
				printf '%s\n' \
					'# HestiaRE (#211): xfs project quota is mount-time-only; the root fs needs it' \
					'# on the kernel command line. Removed together with h-* quota arming.' \
					'GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX rootflags=prjquota"' \
					> "$QUOTA_GRUB_DROPIN"
				if update-grub > /dev/null 2>&1 && quota_install_unit; then
					quota_set_key "pending:reboot"
					echo "[ * ] project quota: rootflags=prjquota staged - active after the reboot"
				else
					rm -f "$QUOTA_GRUB_DROPIN"
					quota_set_key "none:update-grub-failed"
					echo "[ ! ] project quota: update-grub failed - not armed"
				fi
			else
				if ! umount "$QUOTA_MNT" 2> /dev/null; then
					quota_set_key "none:home-umount-failed"
					echo "[ ! ] project quota: $QUOTA_MNT is busy - not armed"
					return 0
				fi
				# persist the option in fstab (4th field), then a FRESH mount - the
				# only mount that enforces on xfs
				awk -v mnt="$QUOTA_MNT" 'BEGIN { OFS="\t" }
					$1 !~ /^#/ && $2 == mnt && $4 !~ /prjquota/ { $4 = $4",prjquota" } { print }' \
					/etc/fstab > /etc/fstab.hestia-quota && mv /etc/fstab.hestia-quota /etc/fstab
				mount "$QUOTA_MNT" || mount -o prjquota "$QUOTA_DEV" "$QUOTA_MNT"
				if quota_enforce_probe "$QUOTA_MNT"; then
					quota_set_key "active"
					echo "[ OK ] project quota activated on $QUOTA_MNT (xfs)"
				else
					quota_set_key "none:${QUOTA_PROBE_REASON// /-}"
					echo "[ ! ] project quota: armed but probe failed: $QUOTA_PROBE_REASON"
				fi
			fi
			;;
		*)
			quota_set_key "none:fs-${QUOTA_FSTYPE:-unknown}"
			echo "[ * ] project quota: $QUOTA_FSTYPE carries no project quota - not armed (named, not half-supported)"
			;;
	esac
	return 0
}

# Boot unit body (sbin/hestia-quota-boot). Two jobs:
#   1. ext4: quotaon -P on every boot - enforcement is runtime state, nothing
#      else restores it after a reboot (measured; the second-reboot case).
#   2. while the key says pending: run the probe once, flip to active on green
#      (ext4: drop the one-shot initramfs hook; xfs: the unit removes itself -
#      the mount option persists on its own. That self-teardown is the one path
#      without self-healing; the smoke check owns catching a lost GRUB drop-in).
quota_boot_apply() {
	local state="${PROJECT_QUOTA%%:*}" reason
	quota_home_fs || return 0
	[ "$QUOTA_FSTYPE" = 'ext4' ] && quotaon -P "$QUOTA_MNT" > /dev/null 2>&1
	[ "$state" = 'pending' ] || return 0

	if quota_enforce_probe "$QUOTA_MNT"; then
		quota_set_key "active"
		quota_remove_initramfs_hook
		if [ "$QUOTA_FSTYPE" = 'xfs' ]; then
			systemctl disable "$QUOTA_UNIT" > /dev/null 2>&1
			rm -f "/etc/systemd/system/$QUOTA_UNIT"
			systemctl daemon-reload
		fi
		"$BIN/h-log-action" "system" "Info" "System" "Project quota enforcement is active." > /dev/null 2>&1
	else
		# surface the premount hook's own reason if it left one - a forever-pending
		# box without a stated why is the forbidden state
		reason="$(cat "$QUOTA_ARM_STATUS" 2> /dev/null)"
		reason="${reason:-$QUOTA_PROBE_REASON}"
		quota_set_key "pending:${reason// /-}"
		"$BIN/h-log-action" "system" "Warning" "System" "Project quota still pending: $reason" > /dev/null 2>&1
	fi
	return 0
}
