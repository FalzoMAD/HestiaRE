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
	esac
}

# Read known configuration keys from $HESTIA/conf/defaults/$system.conf
function read_kv_config_file() {
	local system=$1

	if [ ! -f "$HESTIA/conf/defaults/$system.conf" ]; then
		syshealth_refresh_registry "$system"
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
syshealth_known_keys() {
	case "$1" in
		web) echo "DOMAIN IP IP6 CUSTOM_DOCROOT CUSTOM_PHPROOT FASTCGI_CACHE FASTCGI_DURATION ALIAS TPL SSL SSL_FORCE SSL_HSTS SSL_HOME LETSENCRYPT FTP_USER FTP_MD5 FTP_PATH BACKEND PROXY PROXY_EXT STATS STATS_USER STATS_CRYPT U_DISK U_BANDWIDTH REDIRECT REDIRECT_CODE AUTH_USER AUTH_HASH DIR_LIST SUSPENDED TIME DATE" ;;
		mail) echo "DOMAIN ANTIVIRUS ANTISPAM DKIM WEBMAIL SSL LETSENCRYPT CATCHALL ACCOUNTS RATE_LIMIT REJECT U_DISK SUSPENDED TIME DATE" ;;
		mail_accounts) echo "ACCOUNT ALIAS AUTOREPLY FWD FWD_ONLY MD5 QUOTA RATE_LIMIT U_DISK SUSPENDED TIME DATE" ;;
		user) echo "NAME PACKAGE CONTACT CRON_REPORTS MD5 RKEY TWOFA QRCODE PHPCLI ROLE SUSPENDED SUSPENDED_USERS SUSPENDED_WEB SUSPENDED_MAIL SUSPENDED_DB SUSPENDED_CRON IP_AVAIL IP_OWNED U_USERS U_DISK U_DISK_DIRS U_DISK_WEB U_DISK_MAIL U_DISK_DB U_BANDWIDTH U_WEB_DOMAINS U_WEB_SSL U_WEB_ALIASES U_MAIL_DKIM U_MAIL_ACCOUNTS U_MAIL_DOMAINS U_MAIL_SSL U_DATABASES U_CRON_JOBS U_BACKUPS LANGUAGE THEME NOTIFICATIONS PREF_UI_SORT FILE_MANAGER DOCKER_BACKUP TIME DATE" ;;
		cron) echo "JOB MIN HOUR DAY MONTH WDAY CMD SUSPENDED TIME DATE" ;;
		db) echo "DB DBUSER MD5 HOST TYPE CHARSET U_DISK SUSPENDED TIME DATE" ;;
		system) echo "ANTISPAM_SYSTEM ANTIVIRUS_SYSTEM APP_NAME BACKEND_PORT BACKUP_GZIP BACKUP_INCREMENTAL BACKUP_MODE BACKUP_SYSTEM BLOCKLIST_INTERVAL CRON_SYSTEM DB_ADMINER_ALIAS DB_PMA_ALIAS DB_SYSTEM DEBUG_MODE DEMO_MODE DISABLE_IP_CHECK DISK_QUOTA DOMAINDIR_WRITABLE ENFORCE_SUBDOMAIN_OWNERSHIP FILE_MANAGER FILE_MANAGER_PORT FIREWALL_EXTENSION FIREWALL_SYSTEM FROM_EMAIL FROM_NAME FTP_SYSTEM HIDE_DOCS IMAP_SYSTEM INACTIVE_SESSION_TIMEOUT LANGUAGE LOGIN_STYLE MAIL_SYSTEM PHPMYADMIN_KEY PLUGIN_APP_INSTALLER POLICY_BACKUP_SUSPENDED_USERS POLICY_CSRF_STRICTNESS POLICY_SPAM_CUSTOMER_TUNING POLICY_SPAM_REJECT_SCORE_MAX POLICY_SPAM_REJECT_SCORE_MIN POLICY_SPAM_SCORE_MAX POLICY_SPAM_SCORE_MIN POLICY_SYNC_ERROR_DOCUMENTS POLICY_SYNC_SKELETON POLICY_SYSTEM_ENABLE_BACON POLICY_SYSTEM_HIDE_SERVICES POLICY_SYSTEM_PASSWORD_RESET POLICY_SYSTEM_PROTECTED_ADMIN POLICY_USER_CHANGE_THEME POLICY_USER_DELETE_LOGS POLICY_USER_EDIT_DETAILS POLICY_USER_EDIT_WEB_TEMPLATES POLICY_USER_VIEW_LOGS POLICY_USER_VIEW_SUSPENDED PROXY_PORT PROXY_SSL_PORT PROXY_SYSTEM RELEASE_BRANCH RESOURCES_LIMIT ROOT_USER SERVER_SMTP_ADDR SERVER_SMTP_HOST SERVER_SMTP_PASSWD SERVER_SMTP_PORT SERVER_SMTP_SECURITY SERVER_SMTP_USER SIEVE_SYSTEM STATS_SYSTEM SUBJECT_EMAIL THEME TITLE UPDATE_HOSTNAME_SSL UPGRADE_SEND_EMAIL UPGRADE_SEND_EMAIL_LOG USE_SERVER_SMTP VERSION WEB_BACKEND WEBMAIL_ALIAS WEBMAIL_SYSTEM WEB_PORT WEB_RGROUPS WEB_SSL WEB_SSL_PORT WEB_SYSTEM" ;;
		ip) echo "OWNER STATUS NAME U_SYS_USERS U_WEB_DOMAINS INTERFACE NETMASK NAT TIME DATE" ;;
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
syshealth_repair_user_config() {
	local key
	[ -f "$USER_DATA/user.conf" ] || return 0
	syshealth_refresh_registry 'user'
	sanitize_config_file 'user'
	for key in $(read_kv_config_file 'user'); do
		grep -q "^${key}='" "$USER_DATA/user.conf" && continue
		sed -i "/^TIME=/i ${key}=''" "$USER_DATA/user.conf"
	done
	# Sourced last, not before the loop: sanitize_config_file clears the keys from the environment,
	# so re-reading first would load the pre-repair state and leave every key inserted below unset as
	# a shell variable. Callers testing ${KEY+x} would then get the opposite of what the file says.
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

# Repair System Configuration
# Adds missing variables to $HESTIA/conf/hestia.conf with safe default values
function syshealth_repair_system_config() {
	# Release branch
	if [[ -z $(check_key_exists 'RELEASE_BRANCH') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: RELEASE_BRANCH ('release')"
		$BIN/h-change-sys-config-value 'RELEASE_BRANCH' 'release'
	fi
	# Webmail alias
	if [ -n "$IMAP_SYSTEM" ]; then
		if [[ -z $(check_key_exists 'WEBMAIL_ALIAS') ]]; then
			echo "[ ! ] Adding missing variable to hestia.conf: WEBMAIL_ALIAS ('webmail')"
			$BIN/h-change-sys-config-value 'WEBMAIL_ALIAS' 'webmail'
		fi
	fi

	# phpMyAdmin alias (PostgreSQL uses Adminer, wired up by h-add-sys-adminer)
	if [ -n "$DB_SYSTEM" ]; then
		if echo "$DB_SYSTEM" | grep -qw 'mysql'; then
			if [[ -z $(check_key_exists 'DB_PMA_ALIAS') ]]; then
				echo "[ ! ] Adding missing variable to hestia.conf: DB_PMA_ALIAS ('phpmyadmin)"
				$BIN/h-change-sys-config-value 'DB_PMA_ALIAS' 'phpmyadmin'
			fi
		fi
	fi

	# Backup compression level
	if [[ -z $(check_key_exists 'BACKUP_GZIP') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: BACKUP_GZIP ('4')"
		$BIN/h-change-sys-config-value 'BACKUP_GZIP' '4'
	fi

	# Theme
	if [[ -z $(check_key_exists 'THEME') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: THEME ('dark')"
		$BIN/h-change-sys-config-value 'THEME' 'dark'
	fi

	# Default language
	if [[ -z $(check_key_exists 'LANGUAGE') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: LANGUAGE ('en')"
		$BIN/h-change-sys-language 'LANGUAGE' 'en'
	fi

	# Disk Quota
	if [[ -z $(check_key_exists 'DISK_QUOTA') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: DISK_QUOTA ('no')"
		$BIN/h-change-sys-config-value 'DISK_QUOTA' 'no'
	fi

	# CRON daemon
	if [[ -z $(check_key_exists 'CRON_SYSTEM') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: CRON_SYSTEM ('cron')"
		$BIN/h-change-sys-config-value 'CRON_SYSTEM' 'cron'
	fi

	# Backend port
	if [[ -z $(check_key_exists 'BACKEND_PORT') ]]; then
		ORIGINAL_PORT=$(sed -ne "/listen/{s/.*listen[^0-9]*\([0-9][0-9]*\)[ \t]*ssl\;/\1/p;q}" "$HESTIA/nginx/conf/nginx.conf")
		echo "[ ! ] Adding missing variable to hestia.conf: BACKEND_PORT ('$ORIGINAL_PORT')"
		$BIN/h-change-sys-config-value 'BACKEND_PORT' $ORIGINAL_PORT
	fi

	# Upgrade: Send email notification
	if [[ -z $(check_key_exists 'UPGRADE_SEND_EMAIL') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: UPGRADE_SEND_EMAIL ('true')"
		$BIN/h-change-sys-config-value 'UPGRADE_SEND_EMAIL' 'true'
	fi

	# Upgrade: Send email notification
	if [[ -z $(check_key_exists 'UPGRADE_SEND_EMAIL_LOG') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: UPGRADE_SEND_EMAIL_LOG ('false')"
		$BIN/h-change-sys-config-value 'UPGRADE_SEND_EMAIL_LOG' 'false'
	fi

	# Support for ZSTD / GZIP Change
	if [[ -z $(check_key_exists 'BACKUP_MODE') ]]; then
		echo "[ ! ] Setting zstd backup compression type as default..."
		$BIN/h-change-sys-config-value "BACKUP_MODE" "zstd"
	fi

	# Login style switcher
	if [[ -z $(check_key_exists 'LOGIN_STYLE') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: LOGIN_STYLE ('default')"
		$BIN/h-change-sys-config-value "LOGIN_STYLE" "default"
	fi

	# Webmail clients
	if [[ -z $(check_key_exists 'WEBMAIL_SYSTEM') ]]; then
		if [ -d "/var/lib/roundcube" ]; then
			echo "[ ! ] Adding missing variable to hestia.conf: WEBMAIL_SYSTEM ('roundcube')"
			$BIN/h-change-sys-config-value "WEBMAIL_SYSTEM" "roundcube"
		else
			echo "[ ! ] Adding missing variable to hestia.conf: WEBMAIL_SYSTEM ('')"
			$BIN/h-change-sys-config-value "WEBMAIL_SYSTEM" ""
		fi
	fi

	# Inactive session timeout
	if [[ -z $(check_key_exists 'INACTIVE_SESSION_TIMEOUT') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: INACTIVE_SESSION_TIMEOUT ('60')"
		$BIN/h-change-sys-config-value "INACTIVE_SESSION_TIMEOUT" "60"
	fi

	# Enforce subdomain ownership
	if [[ -z $(check_key_exists 'ENFORCE_SUBDOMAIN_OWNERSHIP') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: ENFORCE_SUBDOMAIN_OWNERSHIP ('yes')"
		$BIN/h-change-sys-config-value "ENFORCE_SUBDOMAIN_OWNERSHIP" "yes"
	fi

	# Debug mode
	if [[ -z $(check_key_exists 'DEBUG_MODE') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: DEBUG_MODE ('false')"
		$BIN/h-change-sys-config-value "DEBUG_MODE" "false"
	fi
	# Quick install plugin
	if [[ -z $(check_key_exists 'PLUGIN_APP_INSTALLER') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: PLUGIN_APP_INSTALLER ('true')"
		$BIN/h-change-sys-config-value "PLUGIN_APP_INSTALLER" "true"
	fi
	# Enable preview mode
	if [[ -z $(check_key_exists 'POLICY_SYSTEM_ENABLE_BACON') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_SYSTEM_ENABLE_BACON ('false')"
		$BIN/h-change-sys-config-value "POLICY_SYSTEM_ENABLE_BACON" "false"
	fi
	# Hide system services
	if [[ -z $(check_key_exists 'POLICY_SYSTEM_HIDE_SERVICES') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_SYSTEM_HIDE_SERVICES ('no')"
		$BIN/h-change-sys-config-value "POLICY_SYSTEM_HIDE_SERVICES" "no"
	fi
	# Password reset
	if [[ -z $(check_key_exists 'POLICY_SYSTEM_PASSWORD_RESET') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_SYSTEM_PASSWORD_RESET ('no')"
		$BIN/h-change-sys-config-value "POLICY_SYSTEM_PASSWORD_RESET" "no"
	fi

	# Theme editor
	if [[ -z $(check_key_exists 'POLICY_USER_CHANGE_THEME') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_USER_CHANGE_THEME ('yes')"
		$BIN/h-change-sys-config-value "POLICY_USER_CHANGE_THEME" "yes"
	fi
	# Per-domain spam tuning for customers (#318): feature toggle and the
	# allowed threshold ranges (points) for non-admin users
	if [[ -z $(check_key_exists 'POLICY_SPAM_CUSTOMER_TUNING') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_SPAM_CUSTOMER_TUNING ('yes')"
		$BIN/h-change-sys-config-value "POLICY_SPAM_CUSTOMER_TUNING" "yes"
	fi
	if [[ -z $(check_key_exists 'POLICY_SPAM_SCORE_MIN') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_SPAM_SCORE_MIN ('3.0')"
		$BIN/h-change-sys-config-value "POLICY_SPAM_SCORE_MIN" "3.0"
	fi
	if [[ -z $(check_key_exists 'POLICY_SPAM_SCORE_MAX') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_SPAM_SCORE_MAX ('10.0')"
		$BIN/h-change-sys-config-value "POLICY_SPAM_SCORE_MAX" "10.0"
	fi
	if [[ -z $(check_key_exists 'POLICY_SPAM_REJECT_SCORE_MIN') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_SPAM_REJECT_SCORE_MIN ('8.0')"
		$BIN/h-change-sys-config-value "POLICY_SPAM_REJECT_SCORE_MIN" "8.0"
	fi
	if [[ -z $(check_key_exists 'POLICY_SPAM_REJECT_SCORE_MAX') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_SPAM_REJECT_SCORE_MAX ('20.0')"
		$BIN/h-change-sys-config-value "POLICY_SPAM_REJECT_SCORE_MAX" "20.0"
	fi
	# Protect admin user
	if [[ -z $(check_key_exists 'POLICY_SYSTEM_PROTECTED_ADMIN') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_SYSTEM_PROTECTED_ADMIN ('no')"
		$BIN/h-change-sys-config-value "POLICY_SYSTEM_PROTECTED_ADMIN" "no"
	fi
	# Allow user delete logs
	if [[ -z $(check_key_exists 'POLICY_USER_DELETE_LOGS') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_USER_DELETE_LOGS ('yes')"
		$BIN/h-change-sys-config-value "POLICY_USER_DELETE_LOGS" "yes"
	fi
	# Allow users to delete details
	if [[ -z $(check_key_exists 'POLICY_USER_EDIT_DETAILS') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_USER_EDIT_DETAILS ('yes')"
		$BIN/h-change-sys-config-value "POLICY_USER_EDIT_DETAILS" "yes"
	fi
	# Allow users to edit web templates
	if [[ -z $(check_key_exists 'POLICY_USER_EDIT_WEB_TEMPLATES') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_USER_EDIT_WEB_TEMPLATES ('yes')"
		$BIN/h-change-sys-config-value "POLICY_USER_EDIT_WEB_TEMPLATES" "yes"
	fi
	# View user logs
	if [[ -z $(check_key_exists 'POLICY_USER_VIEW_LOGS') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_USER_VIEW_LOGS ('yes')"
		$BIN/h-change-sys-config-value "POLICY_USER_VIEW_LOGS" "yes"
	fi
	# Allow users to login (read only) when suspended
	if [[ -z $(check_key_exists 'POLICY_USER_VIEW_SUSPENDED') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_USER_VIEW_SUSPENDED ('no')"
		$BIN/h-change-sys-config-value "POLICY_USER_VIEW_SUSPENDED" "no"
	fi
	# PHPMyadmin SSO key
	if [[ -z $(check_key_exists 'PHPMYADMIN_KEY') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: PHPMYADMIN_KEY ('')"
		$BIN/h-change-sys-config-value "PHPMYADMIN_KEY" ""
	fi
	# Use SMTP server for hestia internal mail
	if [[ -z $(check_key_exists 'USE_SERVER_SMTP') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: USE_SERVER_SMTP ('')"
		$BIN/h-change-sys-config-value "USE_SERVER_SMTP" "false"
	fi

	if [[ -z $(check_key_exists 'SERVER_SMTP_PORT') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: SERVER_SMTP_PORT ('')"
		$BIN/h-change-sys-config-value "SERVER_SMTP_PORT" ""
	fi

	if [[ -z $(check_key_exists 'SERVER_SMTP_HOST') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: SERVER_SMTP_HOST ('')"
		$BIN/h-change-sys-config-value "SERVER_SMTP_HOST" ""
	fi

	if [[ -z $(check_key_exists 'SERVER_SMTP_SECURITY') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: SERVER_SMTP_SECURITY ('')"
		$BIN/h-change-sys-config-value "SERVER_SMTP_SECURITY" ""
	fi

	if [[ -z $(check_key_exists 'SERVER_SMTP_USER') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: SERVER_SMTP_USER ('')"
		$BIN/h-change-sys-config-value "SERVER_SMTP_USER" ""
	fi

	if [[ -z $(check_key_exists 'SERVER_SMTP_PASSWD') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: SERVER_SMTP_PASSWD ('')"
		$BIN/h-change-sys-config-value "SERVER_SMTP_PASSWD" ""
	fi

	if [[ -z $(check_key_exists 'SERVER_SMTP_ADDR') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: SERVER_SMTP_ADDR ('')"
		$BIN/h-change-sys-config-value "SERVER_SMTP_ADDR" ""
	fi
	if [[ -z $(check_key_exists 'POLICY_CSRF_STRICTNESS') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_CSRF_STRICTNESS ('')"
		$BIN/h-change-sys-config-value "POLICY_CSRF_STRICTNESS" "1"
	fi

	if [[ -z $(check_key_exists 'DISABLE_IP_CHECK') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: DISABLE_IP_CHECK ('no')"
		$BIN/h-change-sys-config-value "DISABLE_IP_CHECK" "no"
	fi
	if [[ -z $(check_key_exists 'APP_NAME') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: APP_NAME ('Hestia Control Panel')"
		$BIN/h-change-sys-config-value "APP_NAME" "Hestia Control Panel"
	fi
	if [[ -z $(check_key_exists 'FROM_NAME') ]]; then
		# Default is always APP_NAME
		echo "[ ! ] Adding missing variable to hestia.conf: FROM_NAME ('')"
		$BIN/h-change-sys-config-value "FROM_NAME" ""
	fi
	if [[ -z $(check_key_exists 'FROM_EMAIL') ]]; then
		# Default is always noreply@hostname.com
		echo "[ ! ] Adding missing variable to hestia.conf: FROM_EMAIL ('')"
		$BIN/h-change-sys-config-value "FROM_EMAIL" ""
	fi
	if [[ -z $(check_key_exists 'SUBJECT_EMAIL') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: SUBJECT_EMAIL ('{{subject}}')"
		$BIN/h-change-sys-config-value "SUBJECT_EMAIL" "{{subject}}"
	fi

	if [[ -z $(check_key_exists 'BACKUP_INCREMENTAL') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: BACKUP_INCREMENTAL ('no')"
		$BIN/h-change-sys-config-value "BACKUP_INCREMENTAL" "no"
	fi

	if [[ -z $(check_key_exists 'TITLE') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: TITLE ('{{page}} - {{hostname}} - {{appname}}')"
		$BIN/h-change-sys-config-value "TITLE" "{{page}} - {{hostname}} - {{appname}}"
	fi

	if [[ -z $(check_key_exists 'HIDE_DOCS') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: HIDE_DOCS ('no')"
		$BIN/h-change-sys-config-value "HIDE_DOCS" "no"
	fi

	if [[ -z $(check_key_exists 'POLICY_SYNC_ERROR_DOCUMENTS') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_SYNC_ERROR_DOCUMENTS ('yes')"
		$BIN/h-change-sys-config-value "POLICY_SYNC_ERROR_DOCUMENTS" "yes"
	fi

	if [[ -z $(check_key_exists 'POLICY_SYNC_SKELETON') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_SYNC_SKELETON ('yes')"
		$BIN/h-change-sys-config-value "POLICY_SYNC_SKELETON" "yes"
	fi
	if [[ -z $(check_key_exists 'POLICY_BACKUP_SUSPENDED_USERS') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: POLICY_BACKUP_SUSPENDED_USERS ('no')"
		$BIN/h-change-sys-config-value "POLICY_BACKUP_SUSPENDED_USERS" "no"
	fi
	if [[ -z $(check_key_exists 'ROOT_USER') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: ROOT_USER ('admin')"
		$BIN/h-change-sys-config-value "ROOT_USER" "admin"
	fi
	if [[ -z $(check_key_exists 'DOMAINDIR_WRITABLE') ]]; then
		echo "[ ! ] Adding missing variable to hestia.conf: DOMAINDIR_WRITABLE ('no')"
		$BIN/h-change-sys-config-value "DOMAINDIR_WRITABLE" "no"
	fi

	# TRUNCATE, and remove unconditionally below: with `touch` plus `>>`, a .new file left behind by a
	# run that found nothing to fix was appended to on the next one - so a key deleted in the meantime
	# came back from the stale copy. Reproduced: delete a key, run twice, the key returns.
	: > "$HESTIA/conf/hestia.conf.new"
	while IFS='= ' read -r lhs rhs; do
		if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
			# The old patterns were inert: '^' is literal in a shell pattern, and *( ) needs extglob.
			rhs="${rhs%%#*}"             # Del inline right comments
			rhs="${rhs%"${rhs##*[! ]}"}" # Del trailing spaces
			rhs="${rhs%\'}"              # Del closing string quote
			rhs="${rhs#\'}"              # Del opening string quote
		fi
		check_ckey=$(grep "^$lhs='" "$HESTIA/conf/hestia.conf.new")
		if [ -z "$check_ckey" ]; then
			echo "$lhs='$rhs'" >> "$HESTIA/conf/hestia.conf.new"
		else
			sed -i "s|^$lhs=.*|$lhs='$rhs'|g" "$HESTIA/conf/hestia.conf.new"
		fi
	done < "$HESTIA/conf/hestia.conf"

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
