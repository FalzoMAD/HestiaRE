#!/bin/bash

#===========================================================================#
#                                                                           #
# HestiaRE - Deterministic user identity (UID/GID scheme v2)                #
#                                                                           #
# This header is the rationale for the whole scheme; the functions below    #
# only implement it.                                                        #
#                                                                           #
# A panel user's uid, gid, the companion uid reserved for rootless Docker   #
# and the subordinate-id base are a pure function of the username. A        #
# restore on a fresh host therefore reproduces the identity with no         #
# metadata at all - which is what makes backups portable once container     #
# data owned by mapped ids lives in a home directory.                       #
#                                                                           #
# identity.conf is a VERIFICATION artefact, never the source of truth: the  #
# restore recomputes from the name and refuses on divergence.               #
#                                                                           #
# No probing at creation. A name whose uid, companion uid or gid is already #
# taken is rejected outright, which keeps UID_PROBE at 0 and the identity   #
# reproducible from the name alone.                                         #
#                                                                           #
# Layout: customers in the odd thousands (11000-41999), each companion in   #
# the interleaved block immediately below (10000-40999), 16000 slots.       #
# Sub-ranges are disjoint by construction - overlapping them would let one  #
# customer own files that appear as internal ids in another's containers.   #
#                                                                           #
# Formula only. Creating the companion and writing /etc/subuid is #389.     #
#===========================================================================#

IDENTITY_SCHEMA_VERSION='2'
IDENTITY_BAND_START=11000
IDENTITY_BLOCK=1000
IDENTITY_STRIDE=2000
IDENTITY_SLOTS=16000
IDENTITY_SUB_START=100000
# Not a tuning knob: base images contain nobody (65534) and the rootless setup
# refuses anything smaller.
IDENTITY_SUB_SIZE=65536
# Passed to useradd as -K UID_MAX: the login.defs guard rail keeps AUTO-assignment out
# of the band, and without this every creation warns about our own deliberate -u.
IDENTITY_BAND_END=$((IDENTITY_BAND_START + IDENTITY_STRIDE * (IDENTITY_SLOTS / IDENTITY_BLOCK - 1) + IDENTITY_BLOCK - 1))

# SHA-256 because it is identical on every platform, unlike crc32 or a language's own
# hash. The mask keeps the value positive after bash's signed 64-bit conversion.
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

identity_companion_uid() {
	local uid
	uid="$(identity_uid "$1")" || return 1
	echo $((uid - IDENTITY_BLOCK))
}

identity_sub_base() {
	local k
	k="$(identity_k "$1")" || return 1
	echo $((IDENTITY_SUB_START + k * IDENTITY_SUB_SIZE))
}

_identity_owner() { getent passwd "$1" 2> /dev/null | cut -d: -f1; }

# Both blocks are checked: a free customer uid with an occupied companion block would
# only break "enable Docker" later, when renaming is no longer an option.
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

	# Private group takes the same id (User Private Group), so a gid clash blocks too.
	owner="$(getent group "$uid" 2> /dev/null | cut -d: -f1)"
	if [ -n "$owner" ] && [ "$owner" != "$user" ]; then
		echo "username '$user' maps to gid $uid, which belongs to group '$owner' - please choose a different username"
		return 1
	fi
	return 0
}

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

# A mismatch means a different scheme or a hand-edited archive; which one is
# authoritative is not ours to guess.
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
