#!/bin/bash

#===========================================================================#
#                                                                           #
# HestiaRE - Panel user identity allocation                                 #
#                                                                           #
# Allocation, not derivation: the username hash only picks where to start   #
# looking, and the first free slot is that user's uid from then on.         #
#                                                                           #
# Backups carry no authoritative identity; restores allocate fresh. What    #
# makes that work is tar resolving ownership by NAME on extract - create    #
# the account first, unpack second, and files land on the new uid by        #
# themselves (measured: uid 5001 -> 5099 once the name maps there).         #
#                                                                           #
# Therefore: h-backup-user must NEVER gain --numeric-owner, which pins the  #
# archived numbers and kills this. A restore under a different username has #
# no local name to resolve to and is the one case still needing a chown.    #
#                                                                           #
# Layout: customers in the odd thousands (11000-41999), each companion in   #
# the block below (10000-40999). Subordinate ranges are disjoint by         #
# construction - overlap would let one customer own files that appear as    #
# internal ids in another's containers.                                     #
#===========================================================================#

IDENTITY_BAND_START=11000
IDENTITY_BLOCK=1000
IDENTITY_STRIDE=2000
IDENTITY_SLOTS=16000
IDENTITY_SUB_START=100000
# Not a knob: base images contain nobody (65534); the rootless setup refuses less.
IDENTITY_SUB_SIZE=65536
# For useradd -K UID_MAX, else the login.defs guard rail warns about our own -u.
IDENTITY_BAND_END=$((IDENTITY_BAND_START + IDENTITY_STRIDE * (IDENTITY_SLOTS / IDENTITY_BLOCK - 1) + IDENTITY_BLOCK - 1))
IDENTITY_MAX_PROBE=64

# SHA-256 is identical on every platform, unlike crc32 or a language's own hash; the
# mask keeps the value positive after bash's signed 64-bit conversion.
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

# Inverse of identity_uid_from_k. Nothing stores the slot, so enabling Docker for an
# existing customer recovers it from the uid to place the subordinate range. Empty when
# the uid is not a customer slot (a companion uid lands in the gap and is rejected).
identity_k_from_uid() {
	local uid="$1" d b r
	[ "$uid" -ge "$IDENTITY_BAND_START" ] 2> /dev/null || return 1
	d=$((uid - IDENTITY_BAND_START))
	b=$((d / IDENTITY_STRIDE))
	r=$((d % IDENTITY_STRIDE))
	[ "$r" -lt "$IDENTITY_BLOCK" ] || return 1
	echo $((b * IDENTITY_BLOCK + r))
}

# Both blocks: a free customer uid over an occupied companion block would only break
# "enable Docker" later, when moving the account is no longer cheap.
_identity_slot_free() {
	local uid="$1"
	getent passwd "$uid" > /dev/null 2>&1 && return 1
	getent passwd $((uid - IDENTITY_BLOCK)) > /dev/null 2>&1 && return 1
	getent group "$uid" > /dev/null 2>&1 && return 1
	return 0
}

# Usage: identity_allocate <user>  ->  "<uid> <companion_uid> <k>" on stdout
# Probing is deterministic, but nothing may depend on that.
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
