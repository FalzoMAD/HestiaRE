#!/bin/bash
# Everything that has to agree about sieve: engine and both webmail clients are separate addons,
# installable in any order, so the condition lives here once instead of four times.

RC_CONFIG='/etc/roundcube/config.inc.php'
TX_DOMAIN_DIR='/etc/tachyon/data/_data_/_default_/domains'

# From the file, not from this shell - a caller may have just written it. The record and not the
# package: a webmail must not offer a filter screen for a service this host does not run.
webmail_sieve_on() {
	[ "$(sed -n "s/^SIEVE_SYSTEM='\([^']*\)'.*/\1/p" "$HESTIA/conf/hestia.conf" 2> /dev/null)" = 'yes' ]
}

# One derivation, two writers: h-add-sys-roundcube writes this line, the sieve commands rewrite it.
webmail_roundcube_plugins() {
	local list="'password', 'newmail_notifier', 'zipdownload', 'archive'"
	# roundcube-plugins ships managesieve and its stock config points at localhost:4190 already.
	webmail_sieve_on && list="$list, 'managesieve'"
	echo "$list"
}

webmail_roundcube_sieve_apply() {
	[ -f "$RC_CONFIG" ] || return 0
	sed -i "s|^\$config\['plugins'\] = \[.*|\$config['plugins'] = [$(webmail_roundcube_plugins)];|" "$RC_CONFIG"
}

# Tachyon speaks ManageSieve itself and carries the block already; only 'enabled' is off. One file
# per domain, so the set comes from the directory - default.json included, because Tachyon clones it
# for every domain added later.
webmail_tachyon_sieve_apply() {
	[ -d "$TX_DOMAIN_DIR" ] || return 0
	local want='false' f tmp
	webmail_sieve_on && want='true'
	for f in "$TX_DOMAIN_DIR"/*.json; do
		[ -f "$f" ] || continue
		# Says what happened, not what the file holds - a failing jq would make the content claim
		# just as loudly. jq itself is unguarded: prerequisite and base package, like its other callers.
		if ! jq -e . "$f" > /dev/null 2>&1; then
			echo "Warning!: could not read $f as JSON - left untouched" >&2
			continue
		fi
		# Writing the key into a file without the block would leave host and port unset.
		if ! jq -e 'has("Sieve")' "$f" > /dev/null 2>&1; then
			echo "Warning!: $f has no Sieve block - left untouched" >&2
			continue
		fi
		tmp="$f.hestia.tmp"
		if jq --argjson e "$want" '.Sieve.enabled = $e' "$f" > "$tmp" 2> /dev/null; then
			chown --reference="$f" "$tmp" && chmod --reference="$f" "$tmp" && mv -f "$tmp" "$f"
		else
			rm -f "$tmp"
			echo "Warning!: could not rewrite $f" >&2
		fi
	done
}

# Both clients in line with the record, whichever is installed.
webmail_sieve_apply() {
	webmail_roundcube_sieve_apply
	webmail_tachyon_sieve_apply
}

# --- IMAP-triggered learning -------------------------------------------------------------------

SIEVE_SCRIPT_DIR='/etc/dovecot/sieve'
DOVECOT_MAIL_CONF='/etc/dovecot/conf.d/10-mail.conf'
DOVECOT_IMAP_CONF='/etc/dovecot/conf.d/20-imap.conf'

# The trigger: without imap_sieve the rules in 91-imapsieve.conf are inert. Edited in place because
# a second shipped copy would drift from the list the mail stage owns - cost of that: a mail-stage
# re-run drops the line, and only h-add-sys-sieve puts it back.
sieve_imap_plugin_add() {
	[ -f "$DOVECOT_IMAP_CONF" ] || {
		echo "Warning!: $DOVECOT_IMAP_CONF is not there - IMAP learning stays off" >&2
		return 1
	}
	grep -qE "^[[:space:]]*mail_plugins[[:space:]]*=.*\bimap_sieve\b" "$DOVECOT_IMAP_CONF" && return 0
	sed -i -E "s/^([[:space:]]*mail_plugins[[:space:]]*=.*)$/\1 imap_sieve/" "$DOVECOT_IMAP_CONF"
	# sed exits 0 when its pattern matched nothing. Read back rather than trust that.
	grep -qE "^[[:space:]]*mail_plugins[[:space:]]*=.*\bimap_sieve\b" "$DOVECOT_IMAP_CONF" || {
		echo "Warning!: no active mail_plugins line in $DOVECOT_IMAP_CONF - IMAP learning stays off" >&2
		return 1
	}
}

sieve_imap_plugin_del() {
	[ -f "$DOVECOT_IMAP_CONF" ] || return 0
	sed -i -E "s/^([[:space:]]*mail_plugins[[:space:]]*=.*)[[:space:]]imap_sieve\b(.*)$/\1\2/" "$DOVECOT_IMAP_CONF"
}

# How the learner reaches the rspamd controller socket. Granted where dovecot already grants groups,
# so no login ever holds it - and a customer cannot use it either, because `pipe` sits in
# sieve_global_extensions, which dovecot offers to global scripts only.
sieve_mail_group_add() {
	[ -f "$DOVECOT_MAIL_CONF" ] || return 0
	getent group _rspamd-ctrl > /dev/null 2>&1 || {
		echo "Warning!: group _rspamd-ctrl is missing - IMAP learning stays off" >&2
		return 0
	}
	grep -qE "^[[:space:]]*mail_access_groups[[:space:]]*=.*\b_rspamd-ctrl\b" "$DOVECOT_MAIL_CONF" && return 0
	sed -i -E "s/^([[:space:]]*mail_access_groups[[:space:]]*=[^#]*[^[:space:]])[[:space:]]*$/\1 _rspamd-ctrl/" \
		"$DOVECOT_MAIL_CONF"
	# Same as above: an empty setting matches nothing and sed still exits 0.
	grep -qE "^[[:space:]]*mail_access_groups[[:space:]]*=.*\b_rspamd-ctrl\b" "$DOVECOT_MAIL_CONF" || {
		echo "Warning!: could not extend mail_access_groups in $DOVECOT_MAIL_CONF - IMAP learning stays off" >&2
		return 1
	}
}

sieve_mail_group_del() {
	[ -f "$DOVECOT_MAIL_CONF" ] || return 0
	sed -i -E "s/^([[:space:]]*mail_access_groups[[:space:]]*=.*)[[:space:]]_rspamd-ctrl\b(.*)$/\1\2/" \
		"$DOVECOT_MAIL_CONF"
}

# The scripts and the pipe program.
sieve_learn_install() {
	local src="$HESTIA/share/dovecot/sieve-learn"
	[ -d "$src" ] || return 0
	mkdir -p "$SIEVE_SCRIPT_DIR"
	cp -f "$src"/*.sieve "$SIEVE_SCRIPT_DIR/"
	cp -f "$src/hestia-rspamd-learn" "$SIEVE_SCRIPT_DIR/"
	chmod 755 "$SIEVE_SCRIPT_DIR/hestia-rspamd-learn"
	chmod 644 "$SIEVE_SCRIPT_DIR"/*.sieve
}

# Compiled because the imap process runs as the customer and cannot write .svbin into a root-owned
# directory. AFTER the dovecot restart because sievec resolves sieve plugins through the RUNNING
# server: before it the same file fails with "unknown Sieve capability 'vnd.dovecot.pipe'", even
# though doveconf already lists the settings.
sieve_learn_compile() {
	local f out rc=0
	for f in "$SIEVE_SCRIPT_DIR"/report-*.sieve; do
		[ -f "$f" ] || continue
		# Not silenced: a warning that hides the compiler's reason is a warning nobody can act on.
		if ! out=$(sievec "$f" 2>&1); then
			echo "Warning!: sievec could not compile $f: ${out:-no output}" >&2
			rc=1
		fi
	done
	return $rc
}

sieve_learn_remove() {
	rm -f "$SIEVE_SCRIPT_DIR"/report-spam.sieve "$SIEVE_SCRIPT_DIR"/report-spam.svbin \
		"$SIEVE_SCRIPT_DIR"/report-ham.sieve "$SIEVE_SCRIPT_DIR"/report-ham.svbin \
		"$SIEVE_SCRIPT_DIR"/hestia-rspamd-learn
}
