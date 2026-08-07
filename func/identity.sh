#!/bin/bash

#===========================================================================#
#                                                                           #
# HestiaRE - Deterministic user identity (UID/GID scheme v2)                #
#                                                                           #
# The full identity of a panel user - uid, gid, the companion uid reserved  #
# for rootless Docker, and the subordinate-id base - is a pure function of  #
# the username. A restore on a fresh host therefore reproduces the exact    #
# same identity with no metadata at all, which is what makes user backups   #
# portable once container data (owned by mapped ids) is in play.            #
#                                                                           #
# The backup carries identity.conf for VERIFICATION only; it is never the   #
# source of truth. Restore recomputes and compares.                         #
#                                                                           #
# Scheme v2 (#388, concept addendum 02). v1 mapped the customer to          #
# container uid 0; v2 introduces the companion so stock images that expect  #
# to run as 1000 work unmodified. This library owns the FORMULA only -      #
# creating the companion and writing /etc/subuid belongs to #389.           #
#===========================================================================#

# Interleaved 1000-blocks: customers occupy the odd thousands, and the block
# immediately below each one is reserved for that customer's companion. 16 usable
# blocks of 1000 = 16000 slots.
IDENTITY_SCHEMA_VERSION='2'
IDENTITY_BAND_START=11000
IDENTITY_BLOCK=1000
IDENTITY_STRIDE=2000
IDENTITY_SLOTS=16000
IDENTITY_SUB_START=100000
# 65536 is not a tuning knob: virtually every base image contains nobody (65534),
# and the rootless setup refuses anything smaller.
IDENTITY_SUB_SIZE=65536
# Highest uid the formula can produce (41999). Passed to useradd as -K UID_MAX so an
# explicit, deliberate -u inside the band does not trip the login.defs guard rail that
# exists to keep AUTO-assignment out of it - otherwise every panel user creation prints
# "uid outside of the UID_MIN/UID_MAX range" onto the command's stderr.
IDENTITY_BAND_END=$((IDENTITY_BAND_START + IDENTITY_STRIDE * (IDENTITY_SLOTS / IDENTITY_BLOCK - 1) + IDENTITY_BLOCK - 1))

# Stable hash of the normalised name. SHA-256 because it is identical on every
# platform, unlike crc32 or any language-internal hash. The mask keeps the value
# positive after bash's signed 64-bit conversion.
identity_k() {
	local name="${1,,}" hex
	[ -n "$name" ] || return 1
	hex="$(printf '%s' "$name" | sha256sum | cut -c1-16)"
	echo $(((16#$hex & 0x7FFFFFFFFFFFFFFF) % IDENTITY_SLOTS))
}

identity_uid() {
	local k
	k="$(identity_k "$1")" || return 1
	echo $((IDENTITY_BAND_START + IDENTITY_STRIDE * (k / IDENTITY_BLOCK) + k % IDENTITY_BLOCK))
}

# The companion always sits exactly one block below its customer, which is why the
# band is interleaved rather than contiguous.
identity_companion_uid() {
	local uid
	uid="$(identity_uid "$1")" || return 1
	echo $((uid - IDENTITY_BLOCK))
}

# Disjoint by construction, so no overlap check is needed as long as every entry in
# the band is created by this formula. Overlapping ranges would let one customer own
# files that appear as internal ids inside another customer's containers.
identity_sub_base() {
	local k
	k="$(identity_k "$1")" || return 1
	echo $((IDENTITY_SUB_START + k * IDENTITY_SUB_SIZE))
}

# Owner of a uid, empty when free.
_identity_owner() { getent passwd "$1" 2> /dev/null | cut -d: -f1; }

# Creation-time collision policy: no probing. If the computed identity is taken by a
# different user the NAME is rejected, which keeps UID_PROBE=0 true for every
# regularly created user and the identity purely reproducible from the name. With
# 16000 slots this is rare enough to be an edge case, not a UX problem.
# Both blocks are checked - a free customer uid with an occupied companion block
# would break "enable Docker" later, at a point where renaming is no longer an option.
# Usage: identity_assert_free <user>   -> 0 = usable, 1 = conflict (reason on stdout)
identity_assert_free() {
	local user="$1" uid uid_c owner
	uid="$(identity_uid "$user")" || {
		echo "cannot compute identity for '$user'"
		return 1
	}
	uid_c=$((uid - IDENTITY_BLOCK))

	owner="$(_identity_owner "$uid")"
	if [ -n "$owner" ] && [ "$owner" != "$user" ]; then
		echo "username '$user' maps to uid $uid, which belongs to '$owner' - please choose a different username"
		return 1
	fi

	owner="$(_identity_owner "$uid_c")"
	if [ -n "$owner" ] && [ "$owner" != "$user" ] && [ "$owner" != "${user}-docker" ]; then
		echo "username '$user' reserves companion uid $uid_c, which belongs to '$owner' - please choose a different username"
		return 1
	fi

	# The private group takes the same id (User Private Group, as on Debian/Ubuntu), so a
	# gid collision blocks creation just as a uid collision does.
	owner="$(getent group "$uid" 2> /dev/null | cut -d: -f1)"
	if [ -n "$owner" ] && [ "$owner" != "$user" ]; then
		echo "username '$user' maps to gid $uid, which belongs to group '$owner' - please choose a different username"
		return 1
	fi
	return 0
}

# Written next to user.conf and carried in the backup. Verification artefact: the
# restore recomputes these values and refuses rather than silently creating an
# identity that does not match the name.
# Usage: identity_write_conf <user> <target-dir>
identity_write_conf() {
	local user="$1" dir="$2" uid k
	[ -n "$user" ] && [ -d "$dir" ] || return 1
	k="$(identity_k "$user")" || return 1
	uid="$(identity_uid "$user")" || return 1

	cat > "$dir/identity.conf" << EOF
SCHEMA_VERSION='$IDENTITY_SCHEMA_VERSION'
USERNAME='$user'
UID='$uid'
GID='$uid'
UID_PROBE='0'
COMPANION_UID='$((uid - IDENTITY_BLOCK))'
COMPANION_HOME='.companion'
SUBUID_START='$((IDENTITY_SUB_START + k * IDENTITY_SUB_SIZE))'
SUBUID_COUNT='$IDENTITY_SUB_SIZE'
DOCKER_ROOTLESS='no'
EOF
	chmod 660 "$dir/identity.conf"
}

# Compare a restored identity.conf against what the name computes to now. A mismatch
# means the archive was written under a different scheme or was edited by hand; the
# restore must stop rather than guess which of the two is authoritative.
# Usage: identity_verify_conf <user> <identity.conf>  -> 0 = consistent, 1 = diverged
identity_verify_conf() {
	local user="$1" conf="$2" pinned_uid pinned_schema expect
	[ -f "$conf" ] || return 0
	pinned_uid="$(sed -n "s/^UID='\([0-9]*\)'.*/\1/p" "$conf" | head -n1)"
	pinned_schema="$(sed -n "s/^SCHEMA_VERSION='\([^']*\)'.*/\1/p" "$conf" | head -n1)"
	[ -n "$pinned_uid" ] || return 0

	expect="$(identity_uid "$user")" || return 1
	if [ "$pinned_uid" != "$expect" ]; then
		echo "identity.conf pins uid $pinned_uid (schema ${pinned_schema:-unknown}) but '$user' computes to $expect"
		return 1
	fi
	return 0
}
