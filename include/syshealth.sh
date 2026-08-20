#!/bin/bash

#===========================================================================#
#                                                                           #
# Hestia Control Panel - System Health Check and Repair Function Library    #
#                                                                           #
#===========================================================================#

# Regenerate one key registry from the list compiled into this file.
#
# Two holes it closes. conf/defaults/*.conf is written at install time, so on a box installed before
# a key was added the registry is stale and a repair reading it skips exactly the key it exists to
# add. And when the file is missing entirely, the fallback below used to call write_kv_config_file
# with whatever $known_keys happened to hold - empty at that point - which wrote an EMPTY registry
# and made it permanent, silently reducing every later repair to a no-op.
#
# Each format function ends with `unset system`, so callers set $system AFTER this, never before.
#
# Never reports failure. The registry dir is root-owned and every caller runs as root, so a failed
# write means something is wrong elsewhere - and the useful reaction is to carry on with the keys
# already on disk, not to abort a domain add. A non-zero return here would do exactly that in any
# caller running under `set -e`.
syshealth_refresh_registry() {
	case "$1" in
		web) syshealth_update_web_config_format ;;
		mail) syshealth_update_mail_config_format ;;
		mail_accounts) syshealth_update_mail_account_config_format ;;
		user | cron) syshealth_update_user_config_format ;;
		db) syshealth_update_db_config_format ;;
		ip) syshealth_update_ip_config_format ;;
		system) syshealth_update_system_config_format ;;
		# Same reason syshealth_known_keys refuses one: without this an unknown subsystem fell
		# through silently, the registry was never written, and the cat below failed into an empty
		# key list - the vacuous agreement the comment there argues against, reached from here.
		*)
			echo "ERROR: unknown configuration subsystem '$1'" >&2
			return 1
			;;
	esac
}

# Read known configuration keys from $HESTIA/conf/defaults/$system.conf
function read_kv_config_file() {
	local system=$1

	if [ ! -f "$HESTIA/conf/defaults/$system.conf" ]; then
		# A refusal here means the subsystem is unknown, so there is no key list to fall back to.
		# Reading on gave a cat error and an empty answer, which every caller treats as valid.
		syshealth_refresh_registry "$system" || return 1
	fi
	while read -r str; do
		echo "$str"
	done < <(cat $HESTIA/conf/defaults/$system.conf)
	unset system
}

# Write known configuration keys to $HESTIA/conf/defaults/
function write_kv_config_file() {
	# Ensure configuration directory exists
	if [ ! -d "$HESTIA/conf/defaults/" ]; then
		mkdir "$HESTIA/conf/defaults/"
	fi

	# Only on drift. The repairs call this on every domain and every mail account, so writing
	# unconditionally would mean one temp file plus rename per object in a rebuild loop.
	local tmp want conf="$HESTIA/conf/defaults/$system.conf"
	want=$(printf '%s\n' $known_keys)
	# An empty set is never legitimate - every subsystem has keys. Persisting one would turn every
	# later repair into a no-op, and the smoke guard would compare it against the same empty source
	# and agree. Leave whatever is on disk instead.
	[ -n "$want" ] || return 0
	[ -f "$conf" ] && [ "$(cat "$conf")" = "$want" ] && return 0

	# Written to a temp file and moved into place. The old delete-then-append left a window in
	# which the registry was missing or half written, and a repair reading it there would silently
	# use a truncated key list - the same class of quiet wrongness this file is being fixed for.
	# rename(2) within one directory is atomic, so a reader sees either the old list or the new one.
	tmp=$(mktemp "$HESTIA/conf/defaults/.$system.conf.XXXXXX") || return 0
	printf '%s\n' "$want" > "$tmp"
	chmod 664 "$tmp"
	mv -f "$tmp" "$conf" || rm -f "$tmp"
}

# Sanitize configuration input
function sanitize_config_file() {
	local system=$1
	known_keys=$(read_kv_config_file "$system")
	for key in $known_keys; do
		unset $key
	done
}

# The key sets, in one place. The format functions below write them to the registry and the
# smoke guard compares the registry against them, so there is one list per subsystem rather
# than a copy per consumer.
#
# Unknown subsystem is an error, not an empty list. Both callers would otherwise treat the empty
# answer as valid: the writer would persist an empty registry, and the guard would compare it
# against the same empty reference and pass. A ninth subsystem added without a branch here has to
# fail loudly, not vacuously agree with itself.
# The key set per object type. Derived, not remembered: everything a command writes with
# add_object_key or update_object_value belongs here, or the repair functions quietly work against a
# smaller set than the code does - and a record they call healthy is missing fields nobody notices.
syshealth_known_keys() {
	case "$1" in
		web) echo "DOMAIN IP IP6 CUSTOM_DOCROOT CUSTOM_PHPROOT FASTCGI_CACHE FASTCGI_DURATION PROXY_CACHE PROXY_CACHE_DURATION ALIAS TPL SSL SSL_FORCE SSL_HSTS SSL_HOME HTTP3 DOCKER DOCKER_PORT DOCKER_OCTET LETSENCRYPT LETSENCRYPT_FAIL_COUNT WP FTP_USER FTP_MD5 FTP_PATH BACKEND PHP_VERSION PROXY PROXY_EXT STATS STATS_USER STATS_CRYPT U_DISK U_BANDWIDTH REDIRECT REDIRECT_CODE AUTH_USER AUTH_HASH ALLOW_USERS DIR_LIST CROWDSEC BOTLIMIT OFFLINE SUSPENDED TIME DATE" ;;
		mail) echo "DOMAIN ANTIVIRUS ANTISPAM DKIM WEBMAIL SSL LETSENCRYPT LETSENCRYPT_FAIL_COUNT CATCHALL ACCOUNTS RATE_LIMIT REJECT U_SMTP_RELAY U_SMTP_RELAY_HOST U_SMTP_RELAY_PORT U_SMTP_RELAY_USERNAME U_SMTP_RELAY_PASSWORD U_SMTP_RELAY_EXCLUDE U_SPAM_SCORE U_SPAM_REJECT_SCORE U_SPAM_SUBJECT_TAG U_SPAM_WHITELIST U_SPAM_BLACKLIST U_DISK SUSPENDED TIME DATE" ;;
		mail_accounts) echo "ACCOUNT ALIAS AUTOREPLY FWD FWD_ONLY MD5 QUOTA RATE_LIMIT U_DISK SUSPENDED TIME DATE" ;;
		user) echo "NAME PACKAGE CONTACT CRON_REPORTS MD5 RKEY TWOFA QRCODE PHPCLI ROLE SUSPENDED SUSPENDED_USERS SUSPENDED_WEB SUSPENDED_MAIL SUSPENDED_DB SUSPENDED_CRON IP_AVAIL IP_OWNED WEB_TEMPLATE PROXY_TEMPLATE BACKEND_TEMPLATE WEB_DOMAINS WEB_ALIASES MAIL_DOMAINS MAIL_ACCOUNTS RATE_LIMIT DATABASES CRON_JOBS DISK_QUOTA CPU_QUOTA CPU_QUOTA_PERIOD MEMORY_LIMIT SWAP_LIMIT BANDWIDTH SHELL BACKUPS BACKUPS_INCREMENTAL U_USERS U_DISK U_DISK_DIRS U_DISK_WEB U_DISK_MAIL U_DISK_DB U_BANDWIDTH U_WEB_DOMAINS U_WEB_SSL U_WEB_ALIASES U_MAIL_DKIM U_MAIL_ACCOUNTS U_MAIL_DOMAINS U_MAIL_SSL U_DATABASES U_CRON_JOBS U_BACKUPS LANGUAGE THEME NOTIFICATIONS PREF_UI_SORT FILE_MANAGER LOGIN_DISABLED LOGIN_USE_IPLIST LOGIN_ALLOW_IPS DOCKER_BACKUP DOCKER_IP DOCKER_LIMIT TIME DATE" ;;
		cron) echo "JOB MIN HOUR DAY MONTH WDAY CMD SUSPENDED TIME DATE" ;;
		db) echo "DB DBUSER MD5 HOST TYPE CHARSET U_DISK SUSPENDED TIME DATE" ;;
		system) echo "ANTISPAM_SYSTEM ANTIVIRUS_SYSTEM APP_NAME BACKEND_PORT BACKUP_GZIP BACKUP_INCREMENTAL BACKUP_MODE BACKUP_SYSTEM BLOCKLIST_INTERVAL CRON_SYSTEM DB_ADMINER_ALIAS DB_PMA_ALIAS DB_SYSTEM DEBUG_MODE DEMO_MODE DISABLE_IP_CHECK DISK_QUOTA DOCKER_SYSTEM DOMAINDIR_WRITABLE ENFORCE_SUBDOMAIN_OWNERSHIP FILE_MANAGER FILE_MANAGER_PORT FIREWALL_EXTENSION FIREWALL_SYSTEM FROM_EMAIL FROM_NAME FTP_SYSTEM HIDE_DOCS IMAP_SYSTEM INACTIVE_SESSION_TIMEOUT LANGUAGE LOGIN_STYLE MAIL_SYSTEM PHPMYADMIN_KEY PLUGIN_APP_INSTALLER POLICY_BACKUP_SUSPENDED_USERS POLICY_CSRF_STRICTNESS POLICY_SPAM_CUSTOMER_TUNING POLICY_SPAM_REJECT_SCORE_MAX POLICY_SPAM_REJECT_SCORE_MIN POLICY_SPAM_SCORE_MAX POLICY_SPAM_SCORE_MIN POLICY_SYNC_ERROR_DOCUMENTS POLICY_SYNC_SKELETON POLICY_SYSTEM_ENABLE_BACON POLICY_SYSTEM_HIDE_SERVICES POLICY_SYSTEM_PASSWORD_RESET POLICY_SYSTEM_PROTECTED_ADMIN POLICY_USER_CHANGE_THEME POLICY_USER_DELETE_LOGS POLICY_USER_EDIT_DETAILS POLICY_USER_EDIT_WEB_TEMPLATES POLICY_USER_VIEW_LOGS POLICY_USER_VIEW_SUSPENDED PROXY_PORT PROXY_SSL_PORT PROXY_SYSTEM RELEASE_BRANCH RESOURCES_LIMIT ROOT_USER SERVER_SMTP_ADDR SERVER_SMTP_HOST SERVER_SMTP_PASSWD SERVER_SMTP_PORT SERVER_SMTP_SECURITY SERVER_SMTP_USER SIEVE_SYSTEM STATS_SYSTEM SUBJECT_EMAIL THEME TITLE UPDATE_HOSTNAME_SSL UPGRADE_SEND_EMAIL UPGRADE_SEND_EMAIL_LOG USE_SERVER_SMTP VERSION WEB_BACKEND WEBMAIL_ALIAS WEBMAIL_SYSTEM WEB_PORT WEB_RGROUPS WEB_SSL WEB_SSL_PORT WEB_SYSTEM" ;;
		ip) echo "OWNER STATUS NAME U_SYS_USERS U_WEB_DOMAINS INTERFACE NETMASK NAT TIME DATE" ;;
		*) return 1 ;;
	esac
}

# Update list of known keys for web.conf files
function syshealth_update_web_config_format() {

	# WEB DOMAINS
	# Create array of known keys in configuration file
	system="web"
	known_keys=$(syshealth_known_keys web)
	write_kv_config_file
	unset system
	unset known_keys
}

# Update list of known keys for mail.conf files
function syshealth_update_mail_config_format() {

	# MAIL DOMAINS
	# Create array of known keys in configuration file
	system="mail"
	known_keys=$(syshealth_known_keys mail)
	write_kv_config_file
	unset system
	unset known_keys
}

function syshealth_update_mail_account_config_format() {
	# MAIL ACCOUNTS
	system="mail_accounts"
	known_keys=$(syshealth_known_keys mail_accounts)
	write_kv_config_file
	unset system
	unset known_keys
}

# Update list of known keys for user.conf files
function syshealth_update_user_config_format() {

	# USER CONFIGURATION
	# Create array of known keys in configuration file
	system="user"
	known_keys=$(syshealth_known_keys user)
	write_kv_config_file
	unset system
	unset known_keys

	# CRON JOB CONFIGURATION
	# Create array of known keys in configuration file
	system="cron"
	known_keys=$(syshealth_known_keys cron)
	write_kv_config_file
	unset system
	unset known_keys
}

# Update list of known keys for db.conf files
function syshealth_update_db_config_format() {

	# DATABASE CONFIGURATION
	# Create array of known keys in configuration file
	system="db"
	known_keys=$(syshealth_known_keys db)
	write_kv_config_file
	unset system
	unset known_keys
}

# Update list of known keys for ip.conf files
function syshealth_update_ip_config_format() {

	# IP ADDRESS
	# Create array of known keys in configuration file
	system="ip"
	known_keys=$(syshealth_known_keys ip)
	write_kv_config_file
	unset system
	unset known_keys
}

# Repair web domain configuration
function syshealth_repair_web_config() {
	syshealth_refresh_registry 'web'
	system="web"
	sanitize_config_file "$system"
	get_domain_values 'web'
	prev="DOMAIN"
	for key in $known_keys; do
		# "${!key}", not "$key": the loop variable holds the key NAME and is never empty, so the
		# check was constant-false and this function repaired nothing since it was written (#559).
		# The indirect expansion asks what was meant - is that key absent from the record?
		if [ -z "${!key}" ]; then
			add_object_key 'web' 'DOMAIN' "$domain" "$key" "$prev"
		fi
		prev=$key
	done
}

# Bring a user.conf up to the current key set. Sibling of the web/mail repairs, which user.conf
# never had - so a key added to the list above reached existing customers only if someone happened
# to rebuild or restore them (#559). update_user_value is no help there: it rewrites an existing
# line and does nothing at all when the key is absent.
#
# Not add_object_key: that one edits a single-line record in place, while user.conf is one key per
# line. Inserted before TIME= rather than appended, so the key never sits on the last line - a record
# without a TIME= line gains nothing, the known limit of this shape (#433).
# syshealth_user_key_default KEY - the value a missing key should get, in REPLY.
#
# Returns 1 when the key must NOT be inserted: it belongs to the package block and this customer's
# package cannot answer. Empty is worse than absent there - an empty limit reads as zero and locks
# the customer out of their own package (is_package_full).
#
# Block membership is read off default.pkg rather than listed, so a package gaining a field needs no
# edit here. The named defaults are the ones no package file carries; they mirror h-add-user.
syshealth_user_key_default() {
	local _key="$1"
	REPLY=$(package_key_value "$_key")
	[ -n "$REPLY" ] && return 0
	if grep -q "^${_key}='" "$CONF_DIR/packages/default.pkg" 2> /dev/null; then
		return 1
	fi
	case "$_key" in
		ROLE) REPLY='user' ;;
		PREF_UI_SORT) REPLY='name' ;;
		LOGIN_DISABLED | LOGIN_USE_IPLIST | NOTIFICATIONS) REPLY='no' ;;
		*) REPLY='' ;;
	esac
	return 0
}

syshealth_repair_user_config() {
	local key line pending i seen_dup='' missing='' add=() lines=()
	[ -f "$USER_DATA/user.conf" ] || return 0
	syshealth_refresh_registry 'user'
	sanitize_config_file 'user'

	for key in $(read_kv_config_file 'user'); do
		grep -q "^${key}='" "$USER_DATA/user.conf" && continue
		# A real default, not '': an empty limit is zero to every reader, not "no limit".
		if ! syshealth_user_key_default "$key"; then
			missing="$missing $key"
			continue
		fi
		# The value lands inside KEY='...' on its own line: a quote closes it early, a newline
		# splits it, and either way two readers disagree about the record.
		case "$REPLY" in
			*"'"* | *$'\n'*)
				echo "Warning!: the package value for $key cannot be written as a record field - left out"
				continue
				;;
		esac
		add+=("${key}='${REPLY}'")
	done
	[ -z "$missing" ] || echo "Warning!: package '$(sed -n "s/^PACKAGE='\(.*\)'$/\1/p" "$USER_DATA/user.conf" | head -n1)' cannot supply${missing} - left out rather than guessed"

	# Also the pass that drops a key appearing twice: bare sed addresses put it there
	# (/MAIL_ACCOUNTS/ matches U_MAIL_ACCOUNTS too), and the loop above skips a key that is
	# present however often it is present, so those lines never leave on their own.
	mapfile -t lines < "$USER_DATA/user.conf"
	declare -A _cnt=() _last=()
	for i in "${!lines[@]}"; do
		key="${lines[$i]%%=*}"
		case "${lines[$i]}" in "$key='"*) ;; *) continue ;; esac
		_cnt[$key]=$((${_cnt[$key]:-0} + 1))
		_last[$key]=$i
	done
	for key in "${!_cnt[@]}"; do
		[ "${_cnt[$key]}" -gt 1 ] || continue
		seen_dup="$seen_dup $key"
		# The last wins because source_conf does, and that is what nearly every reader uses.
		echo "Warning!: user.conf had ${_cnt[$key]} lines for $key - keeping line $((_last[$key] + 1)), the value source_conf was already using"
	done

	# printf, never sed's i command: the value is data here, and i eats a backslash in it and wants
	# the text escaped for its own syntax on top.
	if [ -n "$seen_dup" ] || [ ${#add[@]} -gt 0 ]; then
		{
			for i in "${!lines[@]}"; do
				line="${lines[$i]}"
				key="${line%%=*}"
				case "$line" in "$key='"*)
					if [ -n "${_last[$key]:-}" ] && [ "${_last[$key]}" != "$i" ]; then continue; fi
					;;
				esac
				case "$line" in
					TIME=*)
						for pending in "${add[@]}"; do printf '%s\n' "$pending"; done
						add=()
						;;
				esac
				printf '%s\n' "$line"
			done
			# No TIME= line: append rather than lose them.
			for pending in "${add[@]}"; do printf '%s\n' "$pending"; done
		} > "$USER_DATA/user.conf.repair" && mv -f "$USER_DATA/user.conf.repair" "$USER_DATA/user.conf"
		chmod 660 "$USER_DATA/user.conf"
	fi
	# Sourced last: sanitize_config_file cleared these from the environment, so reading before the
	# repair would leave every key it just inserted unset as a shell variable, and a caller testing
	# ${KEY+x} would get the opposite of what the file says.
	source_conf "$USER_DATA/user.conf"
}

function syshealth_repair_mail_config() {
	syshealth_refresh_registry 'mail'
	system="mail"
	sanitize_config_file "$system"
	get_domain_values 'mail'
	prev="DOMAIN"
	for key in $known_keys; do
		if [ -z "${!key}" ]; then
			add_object_key 'mail' 'DOMAIN' "$domain" "$key" "$prev"
		fi
		prev=$key
	done
}

function syshealth_repair_mail_account_config() {
	syshealth_refresh_registry 'mail_accounts'
	system="mail_accounts"
	sanitize_config_file "$system"
	get_object_values "mail/$domain" 'ACCOUNT' "$account"
	# Anchor the first insert, as the web and mail siblings do: without it $prev carries over from a
	# previous call, and add_object_key would anchor the new key on some other object's last field.
	prev="ACCOUNT"
	for key in $known_keys; do
		if [ -z "${!key}" ]; then
			add_object_key "mail/$domain" 'ACCOUNT' "$account" "$key" "$prev"
		fi
		prev=$key
	done
}

# Reachable as `h-update-sys-defaults system`, unlike its siblings which the no-arg form also calls.
# The list had drifted 43 keys behind what the panel and the addons actually write (every POLICY_*, the
# SMTP settings, ROOT_USER, DEMO_MODE), so the defaults file it generates described a configuration the
# product stopped having. Keep it in step with the keys written via wcv / h-change-sys-config-value.
function syshealth_update_system_config_format() {
	# SYSTEM CONFIGURATION
	# Create array of known keys in configuration file
	system="system"
	known_keys=$(syshealth_known_keys system)
	write_kv_config_file
	unset system
	unset known_keys
}

# Restore System Configuration
# Replaces $HESTIA/conf/hestia.conf with "known good defaults" file ($HESTIA/conf/defaults/hestia.conf)
function syshealth_restore_system_config() {
	if [ -f "$HESTIA/conf/defaults/hestia.conf" ]; then
		mv $HESTIA/conf/hestia.conf $HESTIA/conf/hestia.conf.old
		cp $HESTIA/conf/defaults/hestia.conf $HESTIA/conf/hestia.conf
		rm -f $HESTIA/conf/hestia.conf.old
	else
		echo "ERROR: System default configuration file not found, aborting."
		exit 1
	fi
}

function check_key_exists() {
	grep -e "^$1=" $HESTIA/conf/hestia.conf
}

# Restore one system config key to its default.
#
# The key holding no value is the same problem as the key being absent: h-list-sys-config emits
# every key of its fixed set, so both reach the panel as "" - and an empty value reads as the
# PERMISSIVE side at the gates that consume it (POLICY_SYSTEM_PASSWORD_RESET as "not no",
# POLICY_SYSTEM_PROTECTED_ADMIN as "not yes"). Checking presence alone let that through.
#
# The decision needs no table of keys: each call carries its own default, and an empty value is
# only repaired when that default is not empty. Nine keys here default to '' on purpose (the SMTP
# relay fields, FROM_NAME/FROM_EMAIL, PHPMYADMIN_KEY) and drop out by themselves.
#
# What it does NOT cover, and must not: a key that h-delete-sys-* empties deliberately. Repairing
# those would re-register a component that was just removed. Two exist, they pass 'keyonly' and
# name the command that clears them.
# The decision, separate from the write: a block that needs its own command (LANGUAGE) asks the same
# question rather than carrying a second copy of the rule.
function key_needs_default() {
	local key="$1" default="$2" mode="${3:-}" line value
	# Not `| head -1`: that SIGPIPEs the grep, which is inert today and stops being inert the moment
	# a sourcing script runs under `set -o pipefail`. The first line is taken with an expansion.
	line=$(check_key_exists "$key")
	line="${line%%$'\n'*}"
	[ -z "$line" ] && return 0
	[ "$mode" = "keyonly" ] && return 1
	[ -z "$default" ] && return 1
	value="${line#*=}"
	value="${value#\'}"
	value="${value%\'}"
	[ -z "$value" ]
}

function repair_key() {
	local key="$1" default="$2" mode="${3:-}"
	key_needs_default "$key" "$default" "$mode" || return 0
	if [ -z "$(check_key_exists "$key")" ]; then
		echo "[ ! ] Adding missing variable to hestia.conf: $key ('$default')"
	else
		echo "[ ! ] Setting empty value in hestia.conf: $key ('$default')"
	fi
	$BIN/h-change-sys-config-value "$key" "$default"
}

# Repair System Configuration
# Adds missing variables to $HESTIA/conf/hestia.conf with safe default values
function syshealth_repair_system_config() {
	# Release branch
	repair_key 'RELEASE_BRANCH' 'release'
	# Webmail alias
	if [ -n "$IMAP_SYSTEM" ]; then
		repair_key 'WEBMAIL_ALIAS' 'webmail'
	fi

	# phpMyAdmin alias (PostgreSQL uses Adminer, wired up by h-add-sys-adminer).
	#
	# Decided by what is on disk, not by a default. keyonly covers the DELETED case - the key is
	# empty and must stay empty - but an ABSENT key is repaired, and on a box that never installed
	# phpMyAdmin that wrote an alias for something that is not there. Same damage as re-registering
	# a removed component, only entered from the other end. The marker is the one
	# h-delete-sys-phpmyadmin uses to decide the same question.
	if [ -n "$DB_SYSTEM" ] && echo "$DB_SYSTEM" | grep -qw 'mysql'; then
		if [ -f "/usr/share/phpmyadmin/index.php" ] || [ -f "/etc/phpmyadmin/config-db.php" ]; then
			repair_key 'DB_PMA_ALIAS' 'phpmyadmin' 'keyonly'
		else
			repair_key 'DB_PMA_ALIAS' '' 'keyonly'
		fi
	fi

	# Backup compression level
	repair_key 'BACKUP_GZIP' '4'

	# Theme
	repair_key 'THEME' 'dark'

	# Default language
	# Its own command, so it asks the shared question instead of repeating the rule.
	if key_needs_default 'LANGUAGE' 'en'; then
		echo "[ ! ] Setting missing value in hestia.conf: LANGUAGE ('en')"
		$BIN/h-change-sys-language 'LANGUAGE' 'en'
	fi

	# Disk Quota
	repair_key 'DISK_QUOTA' 'no'

	# CRON daemon
	repair_key 'CRON_SYSTEM' 'cron'

	# BACKEND_PORT has no repair here on purpose. It used to scrape the port out of
	# $HESTIA/nginx/conf/nginx.conf - the hestia-nginx that Caddy replaced, so that file does not
	# exist and the sed produced nothing; h-add-firewall-chain hit the same dead path once. The
	# value is written at install time (include/helper.sh, _wcv BACKEND_PORT), and every consumer
	# already falls back to 8083. Left in, the block would go from never firing to writing an empty
	# value the moment the key turns up empty.

	# Upgrade: Send email notification
	# Was in the key registry with no repair behind it, so absent everywhere - and both readers gate
	# on == "yes", so the panel never took over its own LE certificate.
	repair_key 'UPDATE_HOSTNAME_SSL' 'yes'

	repair_key 'UPGRADE_SEND_EMAIL' 'true'

	# Upgrade: Send email notification
	repair_key 'UPGRADE_SEND_EMAIL_LOG' 'false'

	# Support for ZSTD / GZIP Change
	repair_key 'BACKUP_MODE' 'zstd'

	# Login style switcher
	repair_key 'LOGIN_STYLE' 'default'

	# Webmail clients
	# Presence only, and not repair_key: the delete commands empty this key deliberately, so a repair
	# keyed on emptiness would advertise a webmail that is no longer installed. When the key is
	# genuinely absent the value is assembled from what is on disk - both clients, not just
	# roundcube: a tachyon box with no key was answered with '' and lost its webmail that way.
	# Markers taken from the delete commands, which decide the same question.
	if [[ -z $(check_key_exists 'WEBMAIL_SYSTEM') ]]; then
		found=""
		[ -d "/var/lib/roundcube" ] && found="roundcube"
		[ -f "/var/lib/tachyon/data/VERSION" ] && found="${found:+$found,}tachyon"
		echo "[ ! ] Adding missing variable to hestia.conf: WEBMAIL_SYSTEM ('$found')"
		$BIN/h-change-sys-config-value "WEBMAIL_SYSTEM" "$found"
		unset found
	fi

	# Inactive session timeout
	repair_key 'INACTIVE_SESSION_TIMEOUT' '60'

	# Enforce subdomain ownership
	repair_key 'ENFORCE_SUBDOMAIN_OWNERSHIP' 'yes'

	# Debug mode
	repair_key 'DEBUG_MODE' 'false'
	# Quick install plugin
	repair_key 'PLUGIN_APP_INSTALLER' 'true'
	# Enable preview mode
	repair_key 'POLICY_SYSTEM_ENABLE_BACON' 'false'
	# Hide system services
	repair_key 'POLICY_SYSTEM_HIDE_SERVICES' 'no'
	# Password reset
	repair_key 'POLICY_SYSTEM_PASSWORD_RESET' 'no'

	# Theme editor. Was the one key with a hand-written emptiness check and an installer seed beside
	# it; both are the general rule now, so the seed is gone and this reads like its 48 neighbours.
	repair_key 'POLICY_USER_CHANGE_THEME' 'yes'
	# Per-domain spam tuning for customers (#318): feature toggle and the
	# allowed threshold ranges (points) for non-admin users
	repair_key 'POLICY_SPAM_CUSTOMER_TUNING' 'yes'
	repair_key 'POLICY_SPAM_SCORE_MIN' '3.0'
	repair_key 'POLICY_SPAM_SCORE_MAX' '10.0'
	repair_key 'POLICY_SPAM_REJECT_SCORE_MIN' '8.0'
	repair_key 'POLICY_SPAM_REJECT_SCORE_MAX' '20.0'
	# Protect admin user. 'yes' here, not the inherited 'no': the installer has always written 'yes'
	# and this was the one key with two homes that disagreed. Harmless while the repair only fired on
	# an absent key - the installer had already set it - but repairing an EMPTY value to 'no' would
	# have switched the protection off. Where the two disagree, the closed side wins.
	repair_key 'POLICY_SYSTEM_PROTECTED_ADMIN' 'yes'
	# Allow user delete logs
	repair_key 'POLICY_USER_DELETE_LOGS' 'yes'
	# Allow users to delete details
	repair_key 'POLICY_USER_EDIT_DETAILS' 'yes'
	# Allow users to edit web templates
	repair_key 'POLICY_USER_EDIT_WEB_TEMPLATES' 'no'
	# View user logs
	repair_key 'POLICY_USER_VIEW_LOGS' 'yes'
	# Allow users to login (read only) when suspended
	repair_key 'POLICY_USER_VIEW_SUSPENDED' 'no'
	# PHPMyadmin SSO key
	repair_key 'PHPMYADMIN_KEY' ''
	# Use SMTP server for hestia internal mail
	repair_key 'USE_SERVER_SMTP' 'false'

	repair_key 'SERVER_SMTP_PORT' ''

	repair_key 'SERVER_SMTP_HOST' ''

	repair_key 'SERVER_SMTP_SECURITY' ''

	repair_key 'SERVER_SMTP_USER' ''

	repair_key 'SERVER_SMTP_PASSWD' ''

	repair_key 'SERVER_SMTP_ADDR' ''
	repair_key 'POLICY_CSRF_STRICTNESS' '1'

	repair_key 'DISABLE_IP_CHECK' 'no'
	repair_key 'APP_NAME' 'Hestia Control Panel'
	# Empty default on purpose: FROM_NAME falls back to APP_NAME and FROM_EMAIL to noreply@hostname
	# where they are read. repair_key only fills an empty value when the default is not empty, so
	# these two are added when absent and then left alone.
	repair_key 'FROM_NAME' ''
	repair_key 'FROM_EMAIL' ''
	repair_key 'SUBJECT_EMAIL' '{{subject}}'

	repair_key 'BACKUP_INCREMENTAL' 'no'

	repair_key 'TITLE' '{{page}} - {{hostname}} - {{appname}}'

	repair_key 'HIDE_DOCS' 'no'

	repair_key 'POLICY_SYNC_ERROR_DOCUMENTS' 'yes'

	repair_key 'POLICY_SYNC_SKELETON' 'yes'
	repair_key 'POLICY_BACKUP_SUSPENDED_USERS' 'no'
	repair_key 'ROOT_USER' 'admin'
	repair_key 'DOMAINDIR_WRITABLE' 'no'

	# Deduplicate by key, keeping the LAST occurrence - which is what the sed here used to do.
	#
	# The value is carried across VERBATIM. The previous loop rebuilt each line from a parsed value
	# and cut everything after the first '#' to strip an inline comment, which silently truncated any
	# value that legitimately contains one: SERVER_SMTP_PASSWD, PHPMYADMIN_KEY, every generated
	# secret. cmp then found a difference by construction and copied the truncated file over the
	# real one. Reproduced: 'p4ss#w0rd!x' came out as 'p4ss'. It also fed the value through a sed
	# replacement, where a '|' or '&' in a password rewrites the expression. An inline comment can
	# only be recognised after the closing quote, never at the first '#', so this no longer tries.
	#
	# TRUNCATE, and remove unconditionally below: with `touch` plus `>>`, a .new file left behind by a
	# run that found nothing to fix was appended to on the next one - so a key deleted in the meantime
	# came back from the stale copy. Reproduced: delete a key, run twice, the key returns.
	local -A conf_last=()
	local -a conf_order=()
	local conf_line conf_key
	: > "$HESTIA/conf/hestia.conf.new"
	while IFS= read -r conf_line || [ -n "$conf_line" ]; do
		# Blank and comment lines are dropped, as before. hestia.conf is generated and holds none.
		[[ $conf_line =~ ^[[:space:]]*(#|$) ]] && continue
		conf_key="${conf_line%%=*}"
		[ "$conf_key" = "$conf_line" ] && continue
		[ -n "${conf_last[$conf_key]:-}" ] || conf_order+=("$conf_key")
		conf_last[$conf_key]="$conf_line"
	done < "$HESTIA/conf/hestia.conf"
	for conf_key in "${conf_order[@]}"; do
		printf '%s\n' "${conf_last[$conf_key]}" >> "$HESTIA/conf/hestia.conf.new"
	done

	if ! cmp --silent "$HESTIA/conf/hestia.conf" "$HESTIA/conf/hestia.conf.new"; then
		echo "[ ! ] Duplicated keys found repair config"
		cp "$HESTIA/conf/hestia.conf.new" "$HESTIA/conf/hestia.conf"
	fi
	rm -f "$HESTIA/conf/hestia.conf.new"

	source_conf "$HESTIA/conf/hestia.conf"
}

# Repair System Cron Jobs
# Add default cron jobs to "hestia" user account's cron tab
function syshealth_repair_system_cronjobs() {
	min=$(gen_pass '012345' '2')
	hour=$(gen_pass '1234567' '1')
	echo "MAILTO=$email" > /var/spool/cron/crontabs/hestia
	echo "CONTENT_TYPE=\"text/plain; charset=utf-8\"" >> /var/spool/cron/crontabs/hestia
	echo "*/2 * * * * sudo /usr/local/hestia/bin/h-update-sys-queue restart" >> /var/spool/cron/crontabs/hestia
	echo "10 00 * * * sudo /usr/local/hestia/bin/h-update-sys-queue daily" >> /var/spool/cron/crontabs/hestia
	echo "15 02 * * * sudo /usr/local/hestia/bin/h-update-sys-queue disk" >> /var/spool/cron/crontabs/hestia
	echo "10 00 * * * sudo /usr/local/hestia/bin/h-update-sys-queue traffic" >> /var/spool/cron/crontabs/hestia
	echo "30 03 * * * sudo /usr/local/hestia/bin/h-update-sys-queue webstats" >> /var/spool/cron/crontabs/hestia
	echo "*/5 * * * * sudo /usr/local/hestia/bin/h-update-sys-queue backup" >> /var/spool/cron/crontabs/hestia
	echo "10 05 * * * sudo /usr/local/hestia/bin/h-backup-users" >> /var/spool/cron/crontabs/hestia
	echo "20 00 * * * sudo /usr/local/hestia/bin/h-update-user-stats" >> /var/spool/cron/crontabs/hestia
	echo "*/5 * * * * sudo /usr/local/hestia/bin/h-update-sys-rrd" >> /var/spool/cron/crontabs/hestia
	echo "$min $hour * * * sudo /usr/local/hestia/bin/h-update-letsencrypt-ssl" >> /var/spool/cron/crontabs/hestia
}
