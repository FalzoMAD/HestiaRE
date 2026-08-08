#!/bin/bash

#===========================================================================#
#                                                                           #
# HestiaRE - Panel user identity allocation                                 #
#                                                                           #
# Allocates a uid/gid inside the panel band, plus the companion uid that    #
# rootless Docker needs (#389). This is ALLOCATION, not derivation: the     #
# hash of the username only picks where to start looking. Whatever was free #
# at creation time is that user's uid from then on, as in classic HestiaCP. #
#                                                                           #
# Backups deliberately carry no authoritative identity and restores do not  #
# try to reproduce one. Portability comes from tar resolving ownership by   #
# NAME on extract: create the account first with any free uid, unpack       #
# second, and the files land on the new uid by themselves. Verified - a     #
# file archived under uid 5001 extracts as 5099 once the name maps there.   #
#                                                                           #
# What that implies for the code:                                           #
#   - h-backup-user must never gain --numeric-owner. It pins the archived   #
#     numbers and destroys exactly this property (measured).                #
#   - A restore under a DIFFERENT username has no local name to resolve to  #
#     and falls back to the archived numbers. That is the one remaining     #
#     case needing a chown, for customer and companion alike.               #
#   - HestiaCP archives need no special path: their uids are sequential and #
#     outside our band, and get discarded like any other.                   #
#                                                                           #
# Layout: customers in the odd thousands (11000-41999), each companion in   #
# the interleaved block immediately below (10000-40999). Subordinate ranges #
# are disjoint by construction - overlapping them would let one customer    #
# own files that appear as internal ids in another's containers.            #
#===========================================================================#

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
# Only reached if the band is genuinely crowded; a collision just costs one more probe.
IDENTITY_MAX_PROBE=64

# Slot for a username at probe n. SHA-256 because it is identical on every platform,
# unlike crc32 or a language's own hash. The mask keeps the value positive after bash's
# signed 64-bit conversion.
identity_k() {
	local name="${1,,}" probe="${2:-0}" hex
	[ -n "$name" ] || return 1
	[ "${probe:-0}" -gt 0 ] 2> /dev/null && name="$name:$probe"
	hex="$(printf '%s' "$name" | sha256sum | cut -c1-16)"
	echo $(((16#$hex & 0x7FFFFFFFFFFFFFFF) % IDENTITY_SLOTS))
}

identity_uid_from_k() {
	echo $((IDENTITY_BAND_START + IDENTITY_STRIDE * ($1 / IDENTITY_BLOCK) + $1 % IDENTITY_BLOCK))
}

identity_sub_base_from_k() { echo $((IDENTITY_SUB_START + $1 * IDENTITY_SUB_SIZE)); }

# Both blocks are checked: a free customer uid over an occupied companion block would
# only break "enable Docker" later, when moving the account is no longer cheap.
_identity_slot_free() {
	local uid="$1"
	getent passwd "$uid" > /dev/null 2>&1 && return 1
	getent passwd $((uid - IDENTITY_BLOCK)) > /dev/null 2>&1 && return 1
	getent group "$uid" > /dev/null 2>&1 && return 1
	return 0
}

# Usage: identity_allocate <user>  ->  "<uid> <companion_uid> <k>" on stdout
# Probing is username-only and deterministic, so the same box lands on the same answer
# twice - but nothing is allowed to depend on that.
identity_allocate() {
	local user="$1" probe=0 k uid
	[ -n "$user" ] || return 1
	while [ "$probe" -le "$IDENTITY_MAX_PROBE" ]; do
		k="$(identity_k "$user" "$probe")" || return 1
		uid="$(identity_uid_from_k "$k")"
		if _identity_slot_free "$uid"; then
			echo "$uid $((uid - IDENTITY_BLOCK)) $k"
			return 0
		fi
		probe=$((probe + 1))
	done
	return 1
}
