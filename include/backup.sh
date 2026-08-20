#!/bin/bash

#===========================================================================#
#                                                                           #
# Hestia Control Panel - Backup Function Library                            #
#                                                                           #
#===========================================================================#

# Archived record lines are edited AS TEXT, never re-emitted from a list of known keys: a list
# silently drops fields it has not heard of, and the field ORDER is load-bearing (botpolicy.sh
# matches DOMAIN first, BOTLIMIT behind it). A value with a literal ' is not representable.

# Is this line exactly a sequence of KEY='VALUE', separated by single spaces?
#
# Not optional: the archived line lands in a live *.conf, and not every reader goes through the PHP
# tokenizer - botpolicy and crowdsec parse it with sed on quote boundaries, get_object_value with
# grep/cut, the listers splice it into JSON. $ stays allowed, the crypt hashes carry it. Banning '
# is also what lets record_set_field find a field by a plain " KEY='" search.
record_line_valid() {
	local _line="$1" _rest _q="'" _dq='"' _bt='`' _bs='\'
	local -A _seen_key=()
	[ -n "$_line" ] || return 1
	# A newline would make the "one record per line" assumption a lie for every reader below.
	[[ "$_line" == *$'\n'* ]] && return 1
	local _re="^([A-Z][A-Z0-9_]*)=${_q}([^${_q}${_dq}${_bt}${_bs}]*)${_q}( |$)"
	# Trailing blanks are trimmed rather than rejected: some writers emit one and it carries
	# nothing. Everything else has to match the grammar exactly.
	_rest="${_line%"${_line##*[! ]}"}"
	while [ -n "$_rest" ]; do
		[[ "$_rest" =~ $_re ]] || return 1
		# A repeated key is refused: the readers disagree about which wins - eval keeps the last,
		# sed and grep -o the first - so one line would carry two truths, invisibly.
		[ -z "${_seen_key[${BASH_REMATCH[1]}]:-}" ] || return 1
		_seen_key[${BASH_REMATCH[1]}]=1
		_rest="${_rest#"${BASH_REMATCH[0]}"}"
	done
	return 0
}

# The keys of a record line, one per line, in the order they appear.
record_keys() {
	grep -o "[A-Z][A-Z0-9_]*='" <<< "$1" | sed "s/='$//"
}

# record_set_field VAR KEY VALUE - replace KEY's value in the record held in VAR, keeping its
# position; append the field at the end when it is not there yet.
record_set_field() {
	local -n _rec_ref="$1"
	local _key="$2" _val="$3" _pre _post
	if [[ "$_rec_ref" == "$_key='"* ]]; then
		_pre=''
		_post="${_rec_ref#"$_key='"}"
	elif [[ "$_rec_ref" == *" $_key='"* ]]; then
		_pre="${_rec_ref%%" $_key='"*}"
		_post="${_rec_ref#*" $_key='"}"
	else
		# No separator in front of the first field: a leading blank is what record_line_valid
		# refuses, and a helper must not be able to build what the gate beside it rejects.
		if [ -z "$_rec_ref" ]; then
			_rec_ref="$_key='$_val'"
		else
			_rec_ref="$_rec_ref $_key='$_val'"
		fi
		return
	fi
	_post="${_post#*\'}"
	if [ -z "$_pre" ]; then
		_rec_ref="$_key='$_val'$_post"
	else
		_rec_ref="$_pre $_key='$_val'$_post"
	fi
}

# restore_parse_record KEYVAR LINE - parse a record and remember, in KEYVAR, which keys it set.
#
# The cleanup between two objects is derived from what LAST parsed, at every parse site: a hand
# list covers less the moment another branch parses a record, and reads as complete either way.
restore_parse_record() {
	local -n _keys_ref="$1"
	_keys_ref="$(record_keys "$2" | tr '\n' ' ')"
	parse_object_kv_list "$2"
}

# restore_forget_record KEYVAR - unset every key the last record set, then clear the register.
restore_forget_record() {
	local -n _keys_ref="$1"
	local _k
	for _k in $_keys_ref; do unset -v "$_k"; done
	_keys_ref=''
}

# record_del_field VAR KEY - remove KEY from the record held in VAR.
record_del_field() {
	local -n _rec_ref="$1"
	local _key="$2" _pre _post
	if [[ "$_rec_ref" == "$_key='"* ]]; then
		_post="${_rec_ref#"$_key='"}"
		_post="${_post#*\'}"
		_rec_ref="${_post# }"
	elif [[ "$_rec_ref" == *" $_key='"* ]]; then
		_pre="${_rec_ref%%" $_key='"*}"
		_post="${_rec_ref#*" $_key='"}"
		_post="${_post#*\'}"
		_rec_ref="$_pre$_post"
	fi
}

# Read the archive ONCE, before anything is written. backup_probe collects what is IN the archive
# and gives the same answer everywhere; backup_report compares that against THIS host and says what
# will be lost. Everything is derived from the archive and from this host's own state - a list kept
# in step by hand is what made the restore lose fields silently.

# The one container directory an archive may carry its records in. Vesta's './vesta' is refused
# outright rather than threaded through every path join, so this is a constant.
BACKUP_CONTAINER='hestia'

# The text identifying a queued job - command plus the arguments that tell it apart. One per
# queueable command.
QUEUE_JOB=''

# queue_drop_job PIPE - remove the first line QUEUE_JOB prefixes.
#
# A prefix, not an identity: two restores of one archive for one customer differ only in their
# selectors, and either may go. The prefix must end at a word boundary or it also matches a longer
# token (a.tar would take a.tar.gz, u1 would take u12), so it is padded here rather than left to
# each caller.
#
# Deleting a line does not stop it running in the pass already under way: sed -i writes a new inode
# and the running bash finishes the one it opened.
queue_drop_job() {
	local _pipe="$1" _job="$QUEUE_JOB" _n
	[ -n "$_job" ] || return 0
	[ -f "$_pipe" ] || return 0
	case "$_job" in *"'" | *" ") ;; *) _job="$_job " ;; esac
	_n=$(grep -nF -m1 -- "$_job" "$_pipe" 2> /dev/null | cut -d: -f1)
	[ -n "$_n" ] || return 0
	sed -i "${_n}d" "$_pipe"
}

# The origin line's format number. One definition for the writer and the reader.
BACKUP_ORIGIN_FORMAT='1'

# backup_write_origin PATH - state who produced this archive. Forensics only: web-system stays the
# source for the web model, and nothing detects by this.
backup_write_origin() {
	printf "PRODUCER='hestiare' VERSION='%s' FORMAT='%s' BACKUP_MODE='%s' CREATED='%s'\n" \
		"${VERSION//\'/}" "$BACKUP_ORIGIN_FORMAT" "${BACKUP_MODE//\'/}" "$(date '+%F %T')" > "$1"
}

# The codec follows BACKUP_MODE when writing, but the member's own suffix when reading: an archive
# written on a zstd box gets restored on whatever box holds it, whose mode is none of its business.
backup_codec_suffix() {
	if [ "$BACKUP_MODE" = 'zstd' ]; then echo 'zst'; else echo 'gz'; fi
}
# -q on both: pzstd reports every file's size on stderr, which in a restore log reads like an error.
backup_compress() {
	if [ "$BACKUP_MODE" = 'zstd' ]; then pzstd -q -"${BACKUP_GZIP:-4}" -; else gzip -"${BACKUP_GZIP:-4}" -; fi
}
backup_decompress() {
	case "$1" in
		*.zst) pzstd -q -dc -- "$1" ;;
		*) gzip -dc -- "$1" ;;
	esac
}

# backup_dump_complete FILE - does this compressed dump end in mysqldump's completion marker?
#
# The exit status of `mysqldump | compress > file` is the COMPRESSOR's, so a dump that died halfway
# writes a truncated file and reports success. Measured: a killed dump has no trailing marker. Read
# before loading as well as after writing, because the restore drops the target first - a truncated
# dump must never be what a DROP is followed by.
backup_dump_complete() {
	[ -s "$1" ] || return 1
	backup_decompress "$1" 2> /dev/null | tail -n 2 | grep -q '^-- Dump completed'
}

# backup_origin_field KEY - one field out of the probed origin line, or nothing.
#
# NOT read with parse_object_kv_list: that assigns into the caller's scope, and VERSION and
# BACKUP_MODE are live config variables here - the marker would decide something through the back
# door. The leading space lets the first field match; no field name is a suffix of another.
backup_origin_field() {
	sed -n "s/.*[[:space:]]$1='\([^']*\)'.*/\1/p" <<< " $PROBE_ORIGIN"
}

# backup_probe ARCHIVE WORKDIR - describe an archive. Sets PROBE_* and extracts the record members
# into WORKDIR, so the caller can read them without unpacking the archive again.
backup_probe() {
	local _arc="$1" _wd="$2" _members _dir

	PROBE_MODE='gzip'
	PROBE_VESTA='no'
	PROBE_WEB='' PROBE_MAIL='' PROBE_DB='' PROBE_UDIR='' PROBE_DNS='' PROBE_TPL=''
	PROBE_CRON='no' PROBE_PACKAGES='' PROBE_WEB_SYSTEM='' PROBE_PROXY_SYSTEM=''
	PROBE_ORIGIN='' PROBE_RECORDS="$_wd"

	[ -f "$_arc" ] || return 1
	_members=$(tar -tf "$_arc" 2> /dev/null) || return 1
	[ -n "$_members" ] || return 1

	# Feature detection, never a marker: no archive written so far carries an origin line, so keying
	# on one would be deciding by its absence. Vesta is detected only in order to REFUSE it, and the
	# refusal is the caller's - a probe describes, it does not decide.
	if grep -qx './vesta/' <<< "$_members" || grep -qx './vesta' <<< "$_members"; then
		PROBE_VESTA='yes'
	fi
	grep -qx './.zstd' <<< "$_members" && PROBE_MODE='zstd'

	# Names from the member paths, one pass per subsystem: the archive is compressed, so per-object
	# extraction would walk it N times. One name per LINE - a home entry can be called "my documents".
	PROBE_WEB=$(sed -n 's|^\./web/\([^/]*\)/'"$BACKUP_CONTAINER"'/web\.conf$|\1|p' <<< "$_members" | sort -u)
	PROBE_MAIL=$(sed -n 's|^\./mail/\([^/]*\)/'"$BACKUP_CONTAINER"'/mail\.conf$|\1|p' <<< "$_members" | sort -u)
	PROBE_DB=$(sed -n 's|^\./db/\([^/]*\)/'"$BACKUP_CONTAINER"'/db\.conf$|\1|p' <<< "$_members" | sort -u)
	# Two expressions, not one alternation: | is the delimiter, so \| inside the pattern would be an
	# escaped delimiter and match nothing. Greedy \(.*\) so a name with a dot of its own survives.
	PROBE_UDIR=$(sed -n -e 's|^\./user_dir/\(.*\)\.tar\.gz$|\1|p' -e 's|^\./user_dir/\(.*\)\.tar\.zst$|\1|p' \
		<<< "$_members" | sort -u)
	# dns/ is the one we never write and never restore. Zones by NAME, because for somebody moving
	# off HestiaCP the count is not the answer to the question they are actually asking.
	PROBE_DNS=$(sed -n 's|^\./dns/\([^/]*\)/.*|\1|p' <<< "$_members" | sort -u)
	# Custom templates: archived by HestiaCP, never read back here, so they are a loss to name.
	PROBE_TPL=$(sed -n 's|^\./web/\([^/]*\)/template/.*|\1|p' <<< "$_members" | sort -u)
	grep -qx "\./cron/cron\.conf" <<< "$_members" && PROBE_CRON='yes'
	PROBE_PACKAGES=$(sed -n "s|^\./$BACKUP_CONTAINER/packages/\(.*\)\.pkg$|\1|p" <<< "$_members" | sort -u)

	# One extraction for every record member. A pattern that matches nothing is not an error: an
	# archive without a mail section is a fact to report, not a failure to read.
	mkdir -p "$_wd" || return 1
	tar -xf "$_arc" -C "$_wd" --wildcards --no-wildcards-match-slash \
		"./$BACKUP_CONTAINER/user.conf" "./$BACKUP_CONTAINER/web-system" "./$BACKUP_CONTAINER/origin" \
		2> /dev/null || true
	tar -xf "$_arc" -C "$_wd" --wildcards \
		"./$BACKUP_CONTAINER/packages/*" "./web/*/$BACKUP_CONTAINER/web.conf" \
		"./mail/*/$BACKUP_CONTAINER/mail.conf" "./db/*/$BACKUP_CONTAINER/db.conf" \
		"./cron/cron.conf" 2> /dev/null || true

	_dir="$_wd/$BACKUP_CONTAINER"
	if [ -f "$_dir/web-system" ]; then
		PROBE_WEB_SYSTEM=$(sed -n "s/.*WEB_SYSTEM='\([^']*\)'.*/\1/p" "$_dir/web-system")
		PROBE_PROXY_SYSTEM=$(sed -n "s/.*PROXY_SYSTEM='\([^']*\)'.*/\1/p" "$_dir/web-system")
	fi
	[ -f "$_dir/origin" ] && PROBE_ORIGIN=$(head -n1 "$_dir/origin")
	return 0
}

# backup_report_count LIST - how many entries a probe list holds (it is newline separated, and an
# empty string is zero entries, not one).
backup_report_count() {
	[ -n "$1" ] || {
		echo 0
		return
	}
	grep -c . <<< "$1"
}

# Keys this host can put into a KIND record. Three sources, because each alone shrinks in a way
# that makes the report lie: the registry lags reality, the live records show only what a customer
# HAPPENS to use right now, and what the commands can add is the only population-independent one.
# PHP_PROFILE is archive-only by design and named here so it does not read as unknown.
backup_local_keys() {
	local _kind="$1" _f
	# A missing user directory is not "no keys" - it is the wrong place, and the caller would get a
	# smaller reference set with no sign of it. The other two sources cannot stand in for it: the
	# registry only knows what this version compiled in, and the command sweep only what a command
	# can add.
	if [ ! -d "$CONF_DIR/users" ]; then
		echo "Warning!: $CONF_DIR/users is not there - the live-record key source read nothing" >&2
	fi
	{
		syshealth_known_keys "$_kind" 2> /dev/null | tr ' ' '\n'
		for _f in "$CONF_DIR"/users/*/"$_kind.conf"; do
			[ -f "$_f" ] || continue
			grep -o "[A-Z][A-Z0-9_]*='" "$_f" | sed "s/='$//"
		done
		# What any command on this box could add to such a record, independent of who uses it today.
		grep -ho "add_object_key[^#]*'\([A-Z][A-Z0-9_]*\)'[[:space:]]*'" "$BIN"/h-* 2> /dev/null \
			| grep -o "'[A-Z][A-Z0-9_]*'" | tr -d "'"
		[ "$_kind" = web ] && echo PHP_PROFILE
	} 2> /dev/null | sed '/^$/d' | sort -u
}

# backup_report - what this host will NOT be able to restore from the probed archive. Every line is
# derived. An empty report is PRINTED, never left as silence: "nothing falls away" and "the probe
# read nothing" have to look different.
backup_report() {
	local _found=0 _n _obj _rec _keys _unknown _tpl _eff _ver _missing _pkg _local _hostkeys _installed
	local _o_mode _o_fmt _o_who _prot _dom _file _bl _e

	echo "-- ARCHIVE --"
	printf '   %s compressed\n' "$PROBE_MODE"
	# Nothing below is printed for a Vesta archive: every count is derived from ./hestia, so it would
	# read 0 web, 0 mail and then "nothing falls away" about a file this host will not read at all.
	if [ "$PROBE_VESTA" = 'yes' ]; then
		printf '   VESTA archive - HestiaRE does not restore these, and this one will be refused\n'
		return 0
	fi
	# "home entries", not directories: h-backup-user walks `ls -a`, so plain files are in there too.
	printf '   objects: %s web, %s mail, %s database, %s home entr%s, cron %s\n' \
		"$(backup_report_count "$PROBE_WEB")" "$(backup_report_count "$PROBE_MAIL")" \
		"$(backup_report_count "$PROBE_DB")" "$(backup_report_count "$PROBE_UDIR")" \
		"$([ "$(backup_report_count "$PROBE_UDIR")" = 1 ] && echo y || echo ies)" "$PROBE_CRON"
	# The origin line describes, never decides: on a disagreement the members are what the restore
	# acts on, and the disagreement is worth printing.
	if [ -n "$PROBE_ORIGIN" ]; then
		_o_mode=$(backup_origin_field BACKUP_MODE)
		_o_fmt=$(backup_origin_field FORMAT)
		printf '   origin: %s %s, format %s, written %s\n' \
			"$(backup_origin_field PRODUCER)" "$(backup_origin_field VERSION)" \
			"${_o_fmt:-?}" "$(backup_origin_field CREATED)"
		if [ -n "$_o_mode" ] && [ "$_o_mode" != "$PROBE_MODE" ]; then
			printf '   origin says %s compression, the archive is %s - the contents decide\n' \
				"$_o_mode" "$PROBE_MODE"
		fi
		if [ -n "$_o_fmt" ] && [ "$_o_fmt" != "$BACKUP_ORIGIN_FORMAT" ]; then
			printf '   origin format %s, this host knows %s - read as far as the members allow\n' \
				"$_o_fmt" "$BACKUP_ORIGIN_FORMAT"
		fi
		# A producer nobody here writes is what a forensic marker is for. Said, not acted on.
		_o_who=$(backup_origin_field PRODUCER)
		if [ "$_o_who" != 'hestiare' ]; then
			printf '   origin names a producer this host does not write: %s\n' "${_o_who:-none at all}"
		fi
	else
		printf '   origin: not stated - recognised by its contents\n'
	fi

	echo "-- WHAT THIS HOST CANNOT RESTORE --"

	# Named rather than counted: for a migration this is the question actually being asked.
	if [ -n "$PROBE_DNS" ]; then
		_found=1
		printf '   %s DNS zone(s), which this host does not serve at all (#58) - the records are in\n' \
			"$(backup_report_count "$PROBE_DNS")"
		printf '   the archive and stay there, nothing here reads them:\n'
		sed 's/^/      /' <<< "$PROBE_DNS"
	fi

	if [ -n "$PROBE_TPL" ]; then
		_found=1
		printf '   custom web template(s) for %s domain(s) - this host renders from its own set\n' \
			"$(backup_report_count "$PROBE_TPL")"
	fi

	# Protections a domain asks for that this host cannot render. The field itself survives the
	# restore - it is the customer's setting and takes effect if the module arrives later - but a
	# protection that is silently inactive belongs in the report. Both questions are asked of the
	# renderers' own predicates, so the report cannot claim a capability the renderer disagrees with.
	type crowdsec_domain_capable > /dev/null 2>&1 || source "$HESTIA/include/crowdsec.sh"
	type botpolicy_family_enabled > /dev/null 2>&1 || source "$HESTIA/include/botpolicy.sh"
	_prot=''
	while IFS= read -r _dom; do
		[ -n "$_dom" ] || continue
		_file=$(backup_record_file web "$_dom")
		[ -s "$_file" ] || continue
		_rec=$(head -n1 "$_file")
		if [ "$(sed -n "s/.*CROWDSEC='\([^']*\)'.*/\1/p" <<< "$_rec")" = 'yes' ] \
			&& ! crowdsec_domain_capable; then
			_prot="$_prot$_dom: CrowdSec"$'\n'
		fi
		_bl=$(sed -n "s/.*BOTLIMIT='\([^']*\)'.*/\1/p" <<< "$_rec")
		for _e in ${_bl//,/ }; do
			botpolicy_family_enabled "${_e%%:*}" || _prot="$_prot$_dom: bot family ${_e%%:*}"$'\n'
		done
	done <<< "$PROBE_WEB"
	if [ -n "$_prot" ]; then
		_found=1
		printf '   protection(s) restored as a setting but inactive here, because this host cannot render them:\n'
		sed '/^$/d;s/^/      /' <<< "$_prot"
	fi

	# A section this host has no subsystem for is dropped in full. With the count: "mail is skipped"
	# and "your 40 mail domains are skipped" are different sentences.
	for _n in web:WEB_SYSTEM:PROBE_WEB mail:MAIL_SYSTEM:PROBE_MAIL db:DB_SYSTEM:PROBE_DB cron:CRON_SYSTEM:PROBE_CRON; do
		_obj="${_n%%:*}"
		_rec="${_n#*:}"
		_keys="${_rec#*:}"
		_rec="${_rec%%:*}"
		[ -n "${!_rec}" ] && continue
		if [ "$_obj" = cron ]; then
			[ "$PROBE_CRON" = 'yes' ] || continue
			_found=1
			printf '   the cron section, because this host has no CRON_SYSTEM\n'
		else
			_n=$(backup_report_count "${!_keys}")
			[ "$_n" -gt 0 ] || continue
			_found=1
			printf '   %s %s object(s), because this host has no %s\n' "$_n" "$_obj" "$_rec"
		fi
	done

	# Finer than the section check above: a host can have a DB_SYSTEM and still not the engine one
	# database was dumped from, and the import has no default branch to survive that.
	if [ -n "$DB_SYSTEM" ]; then
		while IFS= read -r _obj; do
			[ -n "$_obj" ] || continue
			_eff=$(backup_db_type "$_obj")
			backup_db_type_supported "$_eff" && continue
			_found=1
			if [ -n "$_eff" ]; then
				printf '   database %s, a %s dump, and this host runs %s\n' "$_obj" "$_eff" "$DB_SYSTEM"
			else
				printf '   database %s, whose record names no engine at all\n' "$_obj"
			fi
		done <<< "$PROBE_DB"
	fi

	[ "$_found" -eq 0 ] && printf '   nothing - every object in this archive has a home on this host\n'

	echo "-- WHAT WILL BE REWRITTEN --"
	_found=0

	# A different web model on the archive side means custom includes may not apply.
	if [ -n "$PROBE_WEB" ]; then
		if [ -z "$PROBE_WEB_SYSTEM" ]; then
			_found=1
			printf '   web model unknown (archive predates it) - review the restored vhosts by hand\n'
		elif [ "$PROBE_WEB_SYSTEM" != "$WEB_SYSTEM" ] || [ "$PROBE_PROXY_SYSTEM" != "$PROXY_SYSTEM" ]; then
			_found=1
			printf '   web model %s/%s -> %s/%s, so custom includes may not apply\n' \
				"${PROBE_WEB_SYSTEM:-none}" "${PROBE_PROXY_SYSTEM:-none}" \
				"${WEB_SYSTEM:-none}" "${PROXY_SYSTEM:-none}"
		fi
	fi

	# accept_web_template is asked, not re-implemented, and the PHP versions come from
	# backup_php_missing: a second copy of either is how a report and a gate come to disagree.
	backup_php_missing "$PROBE_WEB"
	_missing="$BACKUP_PHP_MISSING"
	while IFS= read -r _obj; do
		[ -n "$_obj" ] || continue
		_rec=$(head -n1 "$(backup_record_file web "$_obj")" 2> /dev/null) || continue
		[ -n "$_rec" ] || continue
		for _n in TPL:web PROXY:proxy; do
			_tpl=$(sed -n "s/.*[[:space:]]${_n%%:*}='\([^']*\)'.*/\1/p" <<< " $_rec")
			[ -n "$_tpl" ] || continue
			read -r _eff _ < <(accept_web_template "${_n#*:}" "$_tpl" 2> /dev/null)
			# An empty answer is not a remap to nothing: a role this model lacks must print no line.
			[ -n "$_eff" ] || continue
			[ "$_eff" = "$_tpl" ] && continue
			_found=1
			printf '   %s: %s template %s -> %s\n' "$_obj" "${_n#*:}" "$_tpl" "$_eff"
		done
	done <<< "$PROBE_WEB"
	if [ -n "$_missing" ]; then
		_found=1
		printf '   PHP %s is not installed here - those domains would move to the default (%s)\n' \
			"$_missing" "$(multiphp_default_version 2> /dev/null)"
	fi

	# Record keys this host neither knows nor writes - three-way, so our own newer fields do not read
	# as foreign.
	for _n in web mail db; do
		_hostkeys=" $(backup_local_keys "$_n" | tr '\n' ' ') "
		_unknown=''
		_keys="PROBE_${_n^^}"
		while IFS= read -r _obj; do
			[ -n "$_obj" ] || continue
			_rec=$(head -n1 "$(backup_record_file "$_n" "$_obj")" 2> /dev/null) || continue
			while IFS= read -r _tpl; do
				[ -n "$_tpl" ] || continue
				[[ "$_hostkeys" == *" $_tpl "* ]] && continue
				[[ " $_unknown " == *" $_tpl "* ]] && continue
				_unknown="$_unknown $_tpl"
			done < <(record_keys "$_rec")
		done <<< "${!_keys}"
		if [ -n "$_unknown" ]; then
			_found=1
			printf '   %s records carry key(s) this host does not use:%s\n' "$_n" "$_unknown"
		fi
	done

	# Package limits from a box with subsystems this one lacks. Derived by comparing key sets, so a
	# future divergence shows up without an edit here.
	for _pkg in $PROBE_PACKAGES; do
		[ -f "$PROBE_RECORDS/$BACKUP_CONTAINER/packages/$_pkg.pkg" ] || continue
		_local=" $(cat "$CONF_DIR/packages/"*.pkg 2> /dev/null | grep -o "^[A-Z][A-Z0-9_]*=" | tr -d '=' | sort -u | tr '\n' ' ') "
		_unknown=$(grep -o "^[A-Z][A-Z0-9_]*=" "$PROBE_RECORDS/$BACKUP_CONTAINER/packages/$_pkg.pkg" | tr -d '=' | sort -u \
			| while IFS= read -r _tpl; do [[ "$_local" == *" $_tpl "* ]] || printf ' %s' "$_tpl"; done)
		if [ -n "$_unknown" ]; then
			_found=1
			printf '   package %s sets limit(s) this host has no subsystem for:%s\n' "$_pkg" "$_unknown"
		fi
	done

	[ "$_found" -eq 0 ] && printf '   nothing - every value comes back exactly as it was archived\n'
	return 0
}

# backup_db_type OBJECT - the engine a database record asks for (mysql, pgsql), or nothing.
backup_db_type() {
	local _rec
	_rec=$(head -n1 "$(backup_record_file db "$1")" 2> /dev/null) || return 0
	sed -n "s/.*[[:space:]]TYPE='\([^']*\)'.*/\1/p" <<< " $_rec"
}

# backup_db_type_supported TYPE - can this host serve that engine? DB_SYSTEM is a COMMA LIST
# ('pgsql,mysql' on a HestiaCP box), so asking whether it is merely set says yes to a postgres dump
# on a box without postgres.
backup_db_type_supported() {
	[ -n "$1" ] || return 1
	[[ ",${DB_SYSTEM}," == *",$1,"* ]]
}

# Consent to write. A restore either has it for everything it plans, or it has not started: a gate
# inside a section leaves a half-made customer behind when it refuses.
#
# Three ways: a SELECTOR naming objects (the selection IS the consent for that section), a CONSENT
# argument, or a prompt where there is a TTY. An argument and not an environment prefix, because the
# queue line is run by bash and an env prefix there is operator input inside an executed command
# line (GHSA-2xw3); a closed set and not a character class, because a character class is what
# quietly admitted a pipe once.
#
# Consenting to a section implies the account, and no OTHER section.
RESTORE_CONSENT_TOKENS='all web mail db cron udir leftovers php-fallback'

# restore_consent_parse LIST [TOKENSET] - validate a comma list against a closed set and remember
# it. An unknown token is refused, never dropped: a silently ignored typo authorises less than it
# looks. TOKENSET is a parameter because the server restore consents to COMPONENTS, not to sections;
# same mechanism and same wording, a different closed set.
restore_consent_parse() {
	local _item _set="${2:-$RESTORE_CONSENT_TOKENS}"
	RESTORE_CONSENT=' '
	[ -n "$1" ] || return 0
	for _item in ${1//,/ }; do
		[ -n "$_item" ] || continue
		case " $_set " in
			*" $_item "*) RESTORE_CONSENT="$RESTORE_CONSENT$_item " ;;
			*) return 1 ;;
		esac
	done
	return 0
}

# restore_consent_has TOKEN - named directly, or through 'all'? 'all' covers the SECTIONS and
# deliberately not php-fallback: moving a customer's domains onto another PHP version is a change to
# what they run, not part of "restore everything".
restore_consent_has() {
	[ "$1" = 'php-fallback' ] || case "${RESTORE_CONSENT:- }" in
		*" all "*) return 0 ;;
	esac
	case "${RESTORE_CONSENT:- }" in
		*" $1 "*) return 0 ;;
	esac
	return 1
}

# restore_consent_selector SELECTOR - does it name specific objects? Empty and '*' mean the whole
# section, which is the case that needs asking; 'no' means the section is off.
restore_consent_selector() {
	case "$1" in
		'' | '*' | 'no') return 1 ;;
		*) return 0 ;;
	esac
}

# restore_consent_ask TOKEN QUESTION - 0 if this run may write TOKEN, 1 if not.
restore_consent_ask() {
	local _ans
	restore_consent_has "$1" && return 0
	# A prompt only where somebody can answer: `read` on a queue's stdin eats the next pipe line.
	if [ -t 0 ]; then
		read -r -p "$2 [y/N] " _ans
		case "$_ans" in
			y | Y)
				RESTORE_CONSENT="$RESTORE_CONSENT$1 "
				return 0
				;;
		esac
	fi
	return 1
}

# backup_php_missing DOMAIN-LIST - sets BACKUP_PHP_MISSING (archived PHP versions this host lacks)
# and BACKUP_PHP_UNREADABLE (domains whose archived record could not be read).
#
# One derivation, two readers: the report asks about the whole archive, the consent step about the
# domains this run would touch - so the list is a parameter, not a default.
#
# Results in globals, NOT on stdout: inside `x=$(...)` this runs in a subshell and the unreadable
# register never reaches the caller, leaving the check that reads it unable to fire.
backup_php_missing() {
	local _list="$1" _dom _rec _ver _missing='' _installed _file
	BACKUP_PHP_UNREADABLE=''
	BACKUP_PHP_MISSING=''
	[ -n "$WEB_BACKEND" ] || return 0
	_installed=" $($BIN/h-list-sys-php plain 2> /dev/null | tr '\n' ' ') "
	while IFS= read -r _dom; do
		[ -n "$_dom" ] || continue
		# A record that is not there is a broken assumption, not a domain without a version: read as
		# the latter it reports "nothing missing" and waves the run onto the default PHP.
		_file=$(backup_record_file web "$_dom")
		if [ ! -s "$_file" ]; then
			BACKUP_PHP_UNREADABLE="$BACKUP_PHP_UNREADABLE $_dom"
			continue
		fi
		_rec=$(head -n1 "$_file")
		_ver=$(sed -n "s/.*PHP_VERSION='\([^']*\)'.*/\1/p" <<< "$_rec")
		[ -z "$_ver" ] && _ver=$(sed -n "s/.*BACKEND='PHP-\([0-9]*\)_\([0-9]*\)'.*/\1.\2/p" <<< "$_rec")
		{ [ -z "$_ver" ] || [ "$_ver" = 'none' ]; } && continue
		[[ "$_installed" == *" $_ver "* ]] || _missing="$_missing $_ver"
	done <<< "$_list"
	BACKUP_PHP_MISSING=$(tr ' ' '\n' <<< "$_missing" | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ $//')
}

# What the restore cannot put back but the archive still holds. Same derivation as the loss report,
# so the two cannot drift: whatever the report names is either carried out here or has a reason
# printed next to it (a rewritten template is a remap, not a loss - nothing to hand over).
#
# Sets LEFTOVERS_PATTERNS (tar wildcards) and LEFTOVERS_SUMMARY (one line each).
backup_leftovers_plan() {
	local _obj _eff
	LEFTOVERS_PATTERNS=''
	LEFTOVERS_SUMMARY=''
	# Each line is <mode>TAB<pattern>. 'w' means tar may read it as a wildcard, 'x' means literally.
	# Only OUR patterns are wildcards; anything carrying a name out of the archive is literal, or a
	# database called x* extracts xyz along with it - measured, and xyz was one this host can restore.
	_lo() {
		LEFTOVERS_PATTERNS="$LEFTOVERS_PATTERNS$1"$'\t'"$2"$'\n'
		LEFTOVERS_SUMMARY="$LEFTOVERS_SUMMARY$3"$'\n'
	}

	[ -n "$PROBE_DNS" ] && _lo w './dns/*' "$(backup_report_count "$PROBE_DNS") DNS zone(s), records and zone files"
	[ -n "$PROBE_TPL" ] && _lo w './web/*/template/*' "custom web template(s) for $(backup_report_count "$PROBE_TPL") domain(s)"

	[ -z "$WEB_SYSTEM" ] && [ -n "$PROBE_WEB" ] && _lo w './web/*' "$(backup_report_count "$PROBE_WEB") web object(s), no WEB_SYSTEM here"
	[ -z "$MAIL_SYSTEM" ] && [ -n "$PROBE_MAIL" ] && _lo w './mail/*' "$(backup_report_count "$PROBE_MAIL") mail object(s), no MAIL_SYSTEM here"
	[ "$PROBE_CRON" = 'yes' ] && [ -z "$CRON_SYSTEM" ] && _lo w './cron/*' "the cron section, no CRON_SYSTEM here"

	if [ -z "$DB_SYSTEM" ]; then
		[ -n "$PROBE_DB" ] && _lo w './db/*' "$(backup_report_count "$PROBE_DB") database(s), no DB_SYSTEM here"
	else
		# Per object: a host can have a DB_SYSTEM and still not the engine one dump was taken from.
		while IFS= read -r _obj; do
			[ -n "$_obj" ] || continue
			_eff=$(backup_db_type "$_obj")
			backup_db_type_supported "$_eff" && continue
			_lo x "./db/$_obj" "database $_obj, a ${_eff:-nameless} dump this host cannot load"
		done <<< "$PROBE_DB"
	fi
	unset -f _lo
}

# backup_leftovers_export ARCHIVE DEST - hand over what the plan named. Prints what it did.
#
# The destination is the customer's, 0700, and never under web/ - these are their database dumps and
# mail spools, not something a vhost may serve.
backup_leftovers_export() {
	local _arc="$1" _dest="$2" _owner="$3" _mode _pat _why _before _after _i=0
	LEFTOVERS_DONE=''
	LEFTOVERS_FAILED=''
	[ -n "$LEFTOVERS_PATTERNS" ] || return 0
	mkdir -p "$_dest" || return 1
	while IFS=$'\t' read -r _mode _pat; do
		[ -n "$_pat" ] || continue
		_i=$((_i + 1))
		_why=$(sed -n "${_i}p" <<< "$LEFTOVERS_SUMMARY")
		# Counted, not trusted: tar's exit status does not say whether anything landed, so a plan
		# entry that produced no file would otherwise be reported as carried out with only the
		# report in the directory.
		_before=$(find "$_dest" -type f 2> /dev/null | wc -l)
		if [ "$_mode" = 'w' ]; then
			tar -xf "$_arc" -C "$_dest" --wildcards "$_pat" 2> /dev/null
		else
			tar -xf "$_arc" -C "$_dest" --no-wildcards "$_pat" 2> /dev/null
		fi
		_after=$(find "$_dest" -type f 2> /dev/null | wc -l)
		if [ "$_after" -gt "$_before" ]; then
			LEFTOVERS_DONE="$LEFTOVERS_DONE$_why"$'\n'
		else
			LEFTOVERS_FAILED="$LEFTOVERS_FAILED$_why"$'\n'
		fi
	done <<< "$LEFTOVERS_PATTERNS"
	backup_report > "$_dest/loss-report.txt" 2> /dev/null
	# The parent too: mkdir -p made it as root, and a root-owned directory in the customer's home is
	# one they cannot clear out themselves.
	chown "$_owner:$_owner" "$(dirname "$_dest")"
	chmod 0700 "$(dirname "$_dest")"
	chown -R "$_owner:$_owner" "$_dest"
	chmod -R u=rwX,go= "$_dest"
	[ -z "$LEFTOVERS_FAILED" ]
}

#===========================================================================#
#                     Server backup (#710)                                  #
#===========================================================================#
#
# State that belongs to the box rather than to one customer, so no per-user archive can own it: the
# webmail databases hold every mailbox's identities and settings in ONE table set, and copying that
# into a customer's tar would hand them the other customers' rows.
#
# Components are derived from what this box actually has, so a server archive describes the box it
# came from rather than a fixed list somebody has to keep in step.

# sqlite_snapshot FILE DEST - a consistent copy of a live sqlite database.
#
# Not a file copy: these run in WAL mode (measured), so a copy taken mid transaction can miss
# commits that are already durable, or tear. .backup is sqlite's own answer and checkpoints for us.
# Without the client there is no way to do it right - the copy is still taken, because some backup
# beats none, but the caller is told the guarantee is gone.
sqlite_snapshot() {
	command -v sqlite3 > /dev/null 2>&1 || return 2
	sqlite3 "$1" ".backup '$2'" 2> /dev/null || return 1
	sqlite_ok "$2"
}

# sqlite_is_db FILE - does this carry sqlite's file header? Answers "is this ours at all" without
# the client, so a foreign .db lying in the store directory can be named and passed over instead of
# being mistaken for a store that failed.
sqlite_is_db() {
	# 15 bytes, not the header's full 16: the 16th is the NUL terminator, and a command substitution
	# drops it with a warning on stderr. Comparing the 15 printable ones is the same test, quietly.
	[ "$(head -c 15 -- "$1" 2> /dev/null)" = 'SQLite format 3' ]
}

# sqlite_ok FILE - is this a sqlite database that reads back whole? The analogue of the dump
# completeness gate, and the reason the restore can verify BEFORE it overwrites anything.
sqlite_ok() {
	command -v sqlite3 > /dev/null 2>&1 || return 2
	[ "$(sqlite3 "$1" 'PRAGMA integrity_check' 2> /dev/null | head -1)" = 'ok' ]
}

# server_components - one line per component this host can back up: NAME<TAB>WHAT
#
# WHAT is a space separated list of items:  dir:<path> | db:<engine>:<name> | sqlite:<file>.
server_components() {
	local _wm _items _f

	_items=''
	# Only the webmail actually installed: WEBMAIL_SYSTEM is a comma list and either side may be off.
	for _wm in ${WEBMAIL_SYSTEM//,/ }; do
		case "$_wm" in
			roundcube)
				[ -d /etc/roundcube ] && _items="$_items dir:/etc/roundcube"
				backup_db_exists mysql roundcube && _items="$_items db:mysql:roundcube"
				# The sqlite fallback (#584) is the store on a box with no engine, and it holds the
				# same thing the mysql one does - every mailbox's identities, address books and
				# settings. Found by looking, so a box that uses both is covered twice rather than
				# by whichever DSN a config parse would have picked.
				for _f in /var/lib/roundcube/db/*.db; do
					[ -f "$_f" ] && _items="$_items sqlite:$_f"
				done
				;;
			tachyon | snappymail)
				[ -d /etc/tachyon/data ] && _items="$_items dir:/etc/tachyon/data"
				backup_db_exists mysql tachyon && _items="$_items db:mysql:tachyon"
				;;
		esac
	done
	[ -n "$_items" ] && printf 'webmail\t%s\n' "${_items# }"

	[ -f "$HESTIA/conf/hestia.conf" ] && printf 'hestia\tdir:%s\n' "$HESTIA/conf/hestia.conf"
	[ -d "$CONF_DIR/packages" ] && printf 'packages\tdir:%s\n' "$CONF_DIR/packages"

	_items=''
	[ -d "$CONF_DIR/firewall" ] && _items="$_items dir:$CONF_DIR/firewall"
	[ -d /etc/fail2ban/jail.d ] && _items="$_items dir:/etc/fail2ban/jail.d"
	[ -n "$_items" ] && printf 'firewall\t%s\n' "${_items# }"
	return 0
}

# backup_db_exists ENGINE NAME - is that database here? Asked, not assumed from a config key.
backup_db_exists() {
	case "$1" in
		mysql) mysql -N -e 'SHOW DATABASES' 2> /dev/null | grep -qxF "$2" ;;
		*) return 1 ;;
	esac
}

# server_component_items NAME - the items of one component, or nothing if this box has no such one.
server_component_items() {
	server_components | while IFS=$'\t' read -r _n _i; do
		[ "$_n" = "$1" ] && printf '%s\n' "$_i"
	done
}

# backup_record_file KIND OBJECT - the extracted record of one object, or nothing.
backup_record_file() {
	case "$1" in
		web) echo "$PROBE_RECORDS/web/$2/$BACKUP_CONTAINER/web.conf" ;;
		mail) echo "$PROBE_RECORDS/mail/$2/$BACKUP_CONTAINER/mail.conf" ;;
		db) echo "$PROBE_RECORDS/db/$2/$BACKUP_CONTAINER/db.conf" ;;
		user) echo "$PROBE_RECORDS/$BACKUP_CONTAINER/user.conf" ;;
	esac
}

# Local storage
# Defining local storage function
local_backup() {

	rm -f $BACKUP/$user.$backup_new_date.tar

	# Checking retention. An adopted archive is the operator's own file - a migration source they put
	# there - and it carries a date in its name like any other, so the rotation below would take it
	# first. Excluded by NAME from the records, not by age.
	backup_list=$(ls -lrt $BACKUP/ | awk '{print $9}' | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
	if [ -s "$USER_DATA/backup.conf" ]; then
		while IFS= read -r _adopted; do
			[ -n "$_adopted" ] || continue
			backup_list=$(grep -vxF -- "$_adopted" <<< "$backup_list")
		done < <(grep -E "(^| )ADOPTED='yes'( |$)" "$USER_DATA/backup.conf" | sed -n "s/^BACKUP='\([^']*\)'.*/\1/p")
	fi
	backups_count=$(grep -c . <<< "$backup_list")
	if [ "$BACKUPS" -le "$backups_count" ]; then
		backups_rm_number=$((backups_count - BACKUPS + 1))

		# Removing old backup
		for backup in $(echo "$backup_list" | head -n $backups_rm_number); do
			backup_date=$(echo $backup | sed -e "s/$user.//" -e "s/.tar$//")
			echo -e "$(date "+%F %T") Rotated: $backup_date" \
				| tee -a $BACKUP/$user.log
			rm -f $BACKUP/$backup
		done
	fi

	# Checking disk space
	disk_usage=$(df $BACKUP | tail -n1 | tr ' ' '\n' | grep % | cut -f 1 -d %)
	if [ "$disk_usage" -ge "$BACKUP_DISK_LIMIT" ]; then
		rm -rf $tmpdir
		rm -f $BACKUP/$user.log
		queue_drop_job "$CONF_DIR/queue/backup.pipe"
		echo "Not enough disk space" | $SENDMAIL -s "$subj" "$email" "yes"
		check_result "$E_DISK" "Not enough dsk space"
	fi

	# Creating final tarball
	cd $tmpdir
	tar -cf $BACKUP/$user.$backup_new_date.tar .
	chmod 640 $BACKUP/$user.$backup_new_date.tar
	chown "hestia":"$user" $BACKUP/$user.$backup_new_date.tar
	localbackup='yes'
	echo -e "$(date "+%F %T") Local: $BACKUP/$user.$backup_new_date.tar" \
		| tee -a $BACKUP/$user.log
}

# FTP Functions
# Defining ftp command function
ftpc() {
	/usr/bin/ftp -np $HOST $PORT << EOF
    quote USER $USERNAME
    quote PASS $PASSWORD
    binary
    $1
    $2
    $3
    quit
EOF
}

# Defining ftp storage function
ftp_backup() {
	# Checking config
	if [ ! -e "$HESTIA/conf/ftp.backup.conf" ]; then
		error="ftp.backup.conf doesn't exist"
		echo "$error" | $SENDMAIL -s "$subj" $email "yes"
		queue_drop_job "$CONF_DIR/queue/backup.pipe"
		echo "$error"
		errorcode="$E_NOTEXIST"
		return "$E_NOTEXIST"
	fi

	# Parse config
	source_conf "$HESTIA/conf/ftp.backup.conf"

	# Set default port
	if [ -z "$(grep 'PORT=' $HESTIA/conf/ftp.backup.conf)" ]; then
		PORT='21'
	fi

	# Checking variables
	if [ -z "$HOST" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
		error="Can't parse ftp backup configuration"
		echo "$error" | $SENDMAIL -s "$subj" $email "yes"
		queue_drop_job "$CONF_DIR/queue/backup.pipe"
		echo "$error"
		errorcode="$E_PARSING"
		return "$E_PARSING"
	fi

	# Debug info
	echo -e "$(date "+%F %T") Remote: ftp://$HOST$BPATH/$user.$backup_new_date.tar"

	# Checking ftp connection
	fconn=$(ftpc)
	ferror=$(echo $fconn | grep -i -e failed -e error -e "Can't" -e "not conn")
	if [ -n "$ferror" ]; then
		error="Error: can't login to ftp ftp://$USERNAME@$HOST"
		echo "$error" | $SENDMAIL -s "$subj" $email $notify
		queue_drop_job "$CONF_DIR/queue/backup.pipe"
		echo "$error"
		errorcode="$E_CONNECT"
		return "$E_CONNECT"
	fi

	# Check ftp permissions
	if [ -z $BPATH ]; then
		ftmpdir="vst.bK76A9SUkt"
	else
		ftpc "mkdir $BPATH" > /dev/null 2>&1
		ftmpdir="$BPATH/vst.bK76A9SUkt"
	fi
	ftpc "mkdir $ftmpdir" "rm $ftmpdir"
	ftp_result=$(ftpc "mkdir $ftmpdir" "rm $ftmpdir" | grep -v Trying)
	if [ -n "$ftp_result" ]; then
		error="Can't create ftp backup folder ftp://$HOST$BPATH"
		echo "$error" | $SENDMAIL -s "$subj" $email $notify
		queue_drop_job "$CONF_DIR/queue/backup.pipe"
		echo "$error"
		errorcode="$E_FTP"
		return "$E_FTP"
	fi

	# Checking retention (Only include .tar files)
	if [ -z $BPATH ]; then
		backup_list=$(ftpc "ls" | awk '{print $9}' | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
	else
		backup_list=$(ftpc "cd $BPATH" "ls" | awk '{print $9}' | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
	fi
	backups_count=$(echo "$backup_list" | wc -l)
	if [ "$backups_count" -ge "$BACKUPS" ]; then
		backups_rm_number=$((backups_count - BACKUPS + 1))
		for backup in $(echo "$backup_list" | head -n $backups_rm_number); do
			backup_date=$(echo $backup | sed -e "s/$user.//" -e "s/.tar$//")
			echo -e "$(date "+%F %T") Rotated ftp backup: $backup_date" \
				| tee -a $BACKUP/$user.log
			if [ -z $BPATH ]; then
				ftpc "delete $backup"
			else
				ftpc "cd $BPATH" "delete $backup"
			fi
		done
	fi

	# Uploading backup archive
	if [ "$localbackup" = 'yes' ]; then
		cd $BACKUP
		if [ -z $BPATH ]; then
			ftpc "put $user.$backup_new_date.tar"
		else
			ftpc "cd $BPATH" "put $user.$backup_new_date.tar"
		fi
	else
		cd $tmpdir
		tar -cf $BACKUP/$user.$backup_new_date.tar .
		cd $BACKUP/
		if [ -z $BPATH ]; then
			ftpc "put $user.$backup_new_date.tar"
		else
			ftpc "cd $BPATH" "put $user.$backup_new_date.tar"
		fi
		rm -f $user.$backup_new_date.tar
	fi
}

# FTP backup download function
ftp_download() {
	source_conf "$HESTIA/conf/ftp.backup.conf"
	if [ -z "$PORT" ]; then
		PORT='21'
	fi
	cd $BACKUP
	if [ -z $BPATH ]; then
		ftpc "get $1"
	else
		ftpc "cd $BPATH" "get $1"
	fi
}

#FTP Delete function
ftp_delete() {
	source_conf "$HESTIA/conf/ftp.backup.conf"
	if [ -z "$PORT" ]; then
		PORT='21'
	fi
	if [ -z $BPATH ]; then
		ftpc "delete $1"
	else
		ftpc "cd $BPATH" "delete $1"
	fi
}

# SFTP Functions
# sftp command function
sftpc() {
	if [ "$PRIVATEKEY" != "yes" ]; then
		expect -f "-" "$@" << EOF
            set timeout 60
            set count 0
            spawn /usr/bin/sftp -o StrictHostKeyChecking=no \
                -o Port=$PORT $USERNAME@$HOST
            expect {
                -nocase "password:" {
                    send "$PASSWORD\r"
                    exp_continue
                }

                -re "Password for (.*)@(.*)" {
                    send "$PASSWORD\r"
                    exp_continue
                }

                -re "Couldn't|(.*)disconnect|(.*)stalled|(.*)not found" {
                    set count \$argc
                    set output "Disconnected."
                    set rc $E_FTP
                    exp_continue
                }

                -re ".*denied.*(publickey|password)." {
                    set output "Permission denied, wrong publickey or password."
                    set rc $E_CONNECT
                }

                -re "\[0-9]*%" {
                    exp_continue
                }

                "sftp>" {
                    if {\$count < \$argc} {
                        set arg [lindex \$argv \$count]
                        send "\$arg\r"
                        incr count
                    } else {
                        send "exit\r"
                        set output "Disconnected."
                        if {[info exists rc] != 1} {
                            set rc $OK
                        }
                    }
                    exp_continue
                }

                timeout {
                    set output "Connection timeout."
                    set rc $E_CONNECT
                }
            }

            if {[info exists output] == 1} {
                puts "\$output"
            }

        exit \$rc
EOF
	else

		expect -f "-" "$@" << EOF
            set timeout 60
            set count 0
            spawn /usr/bin/sftp -o StrictHostKeyChecking=no \
                -o Port=$PORT -i $PASSWORD $USERNAME@$HOST
            expect {
                -nocase "password:" {
                    send "$PASSWORD\r"
                    exp_continue
                }

                -re "Couldn't|(.*)disconnect|(.*)stalled|(.*)not found" {
                    set count \$argc
                    set output "Disconnected."
                    set rc $E_FTP
                    exp_continue
                }

                -re ".*denied.*(publickey|password)." {
                    set output "Permission denied, wrong publickey or password."
                    set rc $E_CONNECT
                }

                -re "\[0-9]*%" {
                    exp_continue
                }

                "sftp>" {
                    if {\$count < \$argc} {
                        set arg [lindex \$argv \$count]
                        send "\$arg\r"
                        incr count
                    } else {
                        send "exit\r"
                        set output "Disconnected."
                        if {[info exists rc] != 1} {
                            set rc $OK
                        }
                    }
                    exp_continue
                }

                timeout {
                    set output "Connection timeout."
                    set rc $E_CONNECT
                }
            }

            if {[info exists output] == 1} {
                puts "\$output"
            }

        exit \$rc
EOF

	fi
}

# SFTP backup download function
sftp_download() {
	source_conf "$HESTIA/conf/sftp.backup.conf"
	if [ -z "$PORT" ]; then
		PORT='22'
	fi
	cd $BACKUP
	if [ -z $BPATH ]; then
		sftpc "get $1" > /dev/null 2>&1
	else
		sftpc "cd $BPATH" "get $1" > /dev/null 2>&1
	fi
}

sftp_delete() {
	source_conf "$HESTIA/conf/sftp.backup.conf"
	if [ -z "$PORT" ]; then
		PORT='22'
	fi
	if [ -z "$BPATH" ]; then
		sftpc "rm $1" > /dev/null 2>&1
	else
		sftpc "cd $BPATH" "rm $1" > /dev/null 2>&1
	fi

}

sftp_backup() {
	# Checking config
	if [ ! -e "$HESTIA/conf/sftp.backup.conf" ]; then
		error="Can't open sftp.backup.conf"
		echo "$error" | $SENDMAIL -s "$subj" $email "yes"
		queue_drop_job "$CONF_DIR/queue/backup.pipe"
		echo "$error"
		errorcode="$E_NOTEXIST"
		return "$E_NOTEXIST"
	fi

	# Parse config
	source_conf "$HESTIA/conf/sftp.backup.conf"

	# Set default port
	if [ -z "$(grep 'PORT=' $HESTIA/conf/sftp.backup.conf)" ]; then
		PORT='22'
	fi

	# Checking variables
	if [ -z "$HOST" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
		error="Can't parse sftp backup configuration"
		echo "$error" | $SENDMAIL -s "$subj" $email "yes"
		queue_drop_job "$CONF_DIR/queue/backup.pipe"
		echo "$error"
		errorcode="$E_PARSING"
		return "$E_PARSING"
	fi

	# Debug info
	echo -e "$(date "+%F %T") Remote: sftp://$HOST/$BPATH/$user.$backup_new_date.tar" \
		| tee -a $BACKUP/$user.log

	# Checking network connection and write permissions
	if [ -z $BPATH ]; then
		sftmpdir="vst.bK76A9SUkt"
	else
		sftmpdir="$BPATH/vst.bK76A9SUkt"
	fi
	sftpc "mkdir $BPATH" > /dev/null 2>&1
	sftpc "mkdir $sftmpdir" "rmdir $sftmpdir" > /dev/null 2>&1
	rc=$?
	if [[ "$rc" != 0 ]]; then
		case $rc in
			$E_CONNECT) error="Can't login to sftp host $HOST" ;;
			$E_FTP) error="Can't create temp folder on sftp $HOST" ;;
		esac
		echo "$error" | $SENDMAIL -s "$subj" $email "yes"
		queue_drop_job "$CONF_DIR/queue/backup.pipe"
		echo "$error"
		errorcode="$rc"
		return "$rc"
	fi

	# Checking retention (Only include .tar files)
	if [ -z $BPATH ]; then
		backup_list=$(sftpc "ls -l" | awk '{print $9}' | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
	else
		backup_list=$(sftpc "cd $BPATH" "ls -l" | awk '{print $9}' | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
	fi
	backups_count=$(echo "$backup_list" | wc -l)
	if [ "$backups_count" -ge "$BACKUPS" ]; then
		backups_rm_number=$((backups_count - BACKUPS + 1))
		for backup in $(echo "$backup_list" | head -n $backups_rm_number); do
			backup_date=$(echo $backup | sed -e "s/$user.//" -e "s/.tar.*$//")
			echo -e "$(date "+%F %T") Rotated sftp backup: $backup_date" \
				| tee -a $BACKUP/$user.log
			if [ -z $BPATH ]; then
				sftpc "rm $backup" > /dev/null 2>&1
			else
				sftpc "cd $BPATH" "rm $backup" > /dev/null 2>&1
			fi
		done
	fi

	# Uploading backup archive
	echo "$(date "+%F %T") Uploading $user.$backup_new_date.tar" | tee -a $BACKUP/$user.log
	if [ "$localbackup" = 'yes' ]; then
		cd $BACKUP
		if [ -z $BPATH ]; then
			sftpc "put $user.$backup_new_date.tar" "chmod 0600 $user.$backup_new_date.tar" > /dev/null 2>&1
		else
			sftpc "cd $BPATH" "put $user.$backup_new_date.tar" "chmod 0600 $user.$backup_new_date.tar" > /dev/null 2>&1
		fi
	else
		cd $tmpdir
		tar -cf $BACKUP/$user.$backup_new_date.tar .
		cd $BACKUP/
		if [ -z $BPATH ]; then
			sftpc "put $user.$backup_new_date.tar" "chmod 0600 $user.$backup_new_date.tar" > /dev/null 2>&1
		else
			sftpc "cd $BPATH" "put $user.$backup_new_date.tar" "chmod 0600 $user.$backup_new_date.tar" > /dev/null 2>&1
		fi
		rm -f $user.$backup_new_date.tar
	fi
}

rclone_backup() {
	# Define rclone config
	source_conf "$HESTIA/conf/rclone.backup.conf"
	echo -e "$(date "+%F %T") Upload With Rclone to $HOST: $user.$backup_new_date.tar"
	if [ "$localbackup" != 'yes' ]; then
		cd $tmpdir
		tar -cf $BACKUP/$user.$backup_new_date.tar .
	fi
	cd $BACKUP/

	if [ -z "$BPATH" ]; then
		rclone copy -v $user.$backup_new_date.tar $HOST:$backup
		if [ "$?" -ne 0 ]; then
			check_result "$E_CONNECT" "Unable to upload backup"
		fi

		# Only include *.tar files
		backup_list=$(rclone lsf $HOST: | cut -d' ' -f1 | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
		backups_count=$(echo "$backup_list" | wc -l)
		backups_rm_number=$((backups_count - BACKUPS))
		if [ "$backups_count" -ge "$BACKUPS" ]; then
			for backup in $(echo "$backup_list" | head -n $backups_rm_number); do
				echo "Delete file: $backup"
				rclone deletefile $HOST:/$backup
			done
		fi
	else
		rclone copy -v $user.$backup_new_date.tar $HOST:$BPATH
		if [ "$?" -ne 0 ]; then
			check_result "$E_CONNECT" "Unable to upload backup"
		fi

		# Only include *.tar files
		backup_list=$(rclone lsf $HOST:$BPATH | cut -d' ' -f1 | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
		backups_count=$(echo "$backup_list" | wc -l)
		backups_rm_number=$(($backups_count - $BACKUPS))
		if [ "$backups_count" -ge "$BACKUPS" ]; then
			for backup in $(echo "$backup_list" | head -n $backups_rm_number); do
				echo "Delete file: $backup"
				rclone deletefile $HOST:$BPATH/$backup
			done
		fi
	fi
	if [ "$localbackup" != 'yes' ]; then
		rm -f $user.$backup_new_date.tar
	fi

}

rclone_delete() {
	# Defining rclone settings
	source_conf "$HESTIA/conf/rclone.backup.conf"
	if [ -z "$BPATH" ]; then
		rclone deletefile $HOST:/$1
	else
		rclone deletefile $HOST:$BPATH/$1
	fi
}

rclone_download() {

	# Defining rclone settings
	source_conf "$HESTIA/conf/rclone.backup.conf"
	cd $BACKUP
	if [ -z "$BPATH" ]; then
		rclone copy -v $HOST:/$1 ./
	else
		rclone copy -v $HOST:$BPATH/$1 ./
	fi
}
