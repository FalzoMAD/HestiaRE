#!/bin/bash
# Customer PHP CPU cap (#212).
#
# Defense in depth, not a per-customer limit: all customer php-fpm masters share one
# slice, so a hammered site or a runaway PHP loop cannot take panel, mail, database
# and ssh down with it. Separating customers from each other would need a slice per
# pool - the predecessor tried it on user-<uid>.slice, which php-fpm never enters.
#
# The panel PHP is a different master (hestia-php.service, /etc/php/hestia) and stays
# outside. The per-user filemanager pools (fm-<user>.conf) live in the customer master
# and are inside the cap - they are that customer's own load.
#
# Every dash in the name is a level, so the cgroup is
# hestia.slice/hestia-customer.slice/hestia-customer-php.slice; systemd creates both
# parents implicitly and neither carries a limit of its own.
#
# The value is computed at boot, see sbin/hestia-customer-php-limit.

CUSTOMER_PHP_SLICE='hestia-customer-php.slice'
CUSTOMER_PHP_LIMIT_UNIT='hestia-customer-php-limit.service'
CUSTOMER_PHP_DROPIN='hestia-slice.conf'

# Derived from what is on disk, never a list: a version installed later must not fall
# out of the cap because nobody remembered to add it here. "hestia" is the panel master.
customer_php_versions() {
	local d ver
	for d in /etc/php/*/fpm; do
		[ -d "$d" ] || continue
		ver=$(basename "$(dirname "$d")")
		[ "$ver" = 'hestia' ] && continue
		[ -f "/lib/systemd/system/php$ver-fpm.service" ] \
			|| [ -f "/usr/lib/systemd/system/php$ver-fpm.service" ] || continue
		echo "$ver"
	done
}

# Wants= as well as After=: with ordering alone, a master started outside the boot
# transaction would come up before the cap was ever computed.
customer_php_slice_dropin() {
	local version="$1" dir="/etc/systemd/system/php$1-fpm.service.d"
	[ -n "$version" ] || return 1
	mkdir -p "$dir" || return 1
	cat > "$dir/$CUSTOMER_PHP_DROPIN" <<- DROPIN
		# Written by customer_php_limit_apply (include/limits.sh). Do not edit.
		[Unit]
		Wants=$CUSTOMER_PHP_LIMIT_UNIT
		After=$CUSTOMER_PHP_LIMIT_UNIT

		[Service]
		Slice=$CUSTOMER_PHP_SLICE
	DROPIN
	chmod 644 "$dir/$CUSTOMER_PHP_DROPIN"
}

# The LIVE cgroup, never the Slice property: the property reads the new value the moment
# the drop-in is written, while the running master stays in its old cgroup until it is
# restarted. Comparing configuration against configuration is how a whole fleet reported
# itself capped with every master still in system.slice.
customer_php_in_slice() {
	case "$(systemctl show -p ControlGroup --value "php$1-fpm" 2> /dev/null)" in
		*/"$CUSTOMER_PHP_SLICE"/*) return 0 ;;
	esac
	return 1
}

# The enforced value, from the cgroup the kernel actually reads. Empty means uncapped, in
# both of its shapes: an inactive slice has no directory, and a slice whose quota was removed
# loses the cpu controller, so cpu.max is gone rather than reading "max".
customer_php_cpu_max() {
	local cg
	cg=$(systemctl show -p ControlGroup --value "$CUSTOMER_PHP_SLICE" 2> /dev/null)
	[ -n "$cg" ] || return 1
	cat "/sys/fs/cgroup$cg/cpu.max" 2> /dev/null
}

customer_php_slice_remove() {
	local dir="/etc/systemd/system/php$1-fpm.service.d"
	[ -n "$1" ] || return 1
	rm -f "$dir/$CUSTOMER_PHP_DROPIN"
	rmdir "$dir" 2> /dev/null
	return 0
}

# One writer for the wiring: the boot unit. This installs only what has to exist before it
# can run - the unit files and the config file - and then lets it do the rest, so there is no
# second copy of the drop-in logic to drift.
#
# Idempotent and safe on a half-built box: the installer calls it while PHP versions are
# still arriving, and h-add-web-php calls it again for each new one.
customer_php_limit_apply() {
	local src="${HESTIA:-/usr/local/hestia}/share/limits"

	[ -d "$src/systemd" ] || {
		echo "Warning: $src/systemd missing - customer PHP cap not installed" >&2
		return 1
	}
	install -m 644 "$src/systemd/$CUSTOMER_PHP_SLICE" "/etc/systemd/system/$CUSTOMER_PHP_SLICE" || return 1
	install -m 644 "$src/systemd/$CUSTOMER_PHP_LIMIT_UNIT" "/etc/systemd/system/$CUSTOMER_PHP_LIMIT_UNIT" || return 1

	# Seeded once. The file is the admin's, and an update that rewrote it would silently undo
	# a deliberate value.
	[ -f /etc/hestia/limits.conf ] || install -m 644 "$src/limits.conf" /etc/hestia/limits.conf

	systemctl daemon-reload
	systemctl enable "$CUSTOMER_PHP_LIMIT_UNIT" > /dev/null 2>&1
	# restart, not start: it is RemainAfterExit, so a start on an already-finished unit does
	# nothing at all - and doing the work again is the point of every caller.
	systemctl restart "$CUSTOMER_PHP_LIMIT_UNIT" > /dev/null 2>&1
	return 0
}
