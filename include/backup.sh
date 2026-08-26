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

# BACKUP_USER_DATA_CORE - entries of a customer's data directory that travel in NEITHER direction.
# One list for both sides; the restore adds its own on top, so it can never reject less than the
# backup withholds.
#
#   web|mail|db|cron.conf, mail  the sections rebuild these per object
#   backup.conf                  a box's own list of archives
#   dns.conf, dns                the subsystem is gone
#   restic.conf                  a repository password
#   auth.log                     login IPs, browser fingerprints and session ids
BACKUP_USER_DATA_CORE='web.conf mail.conf db.conf cron.conf mail backup.conf dns.conf dns restic.conf auth.log'

# The text identifying a queued job - command plus the arguments that tell it apart. One per
# queueable command.
QUEUE_JOB=''
# One drop per run, tracked here and not by each caller (there are forty of them).
QUEUE_JOB_DROPPED=''

# queue_drop_job PIPE - remove the first line QUEUE_JOB prefixes, at most once per run.
#
# A prefix, not an identity: two restores of one archive for one customer differ only in their
# selectors, and either may go. The prefix must end at a word boundary or it also matches a longer
# token (a.tar would take a.tar.gz, u1 would take u12), so it is padded here rather than left to
# each caller.
#
# AT MOST ONCE, because a prefix that may take any matching line must not be allowed to take two:
# every remote transport drops on its error path and then RETURNS, so a run with a working local
# target carries on to the end and drops again - and the second drop takes the NEXT queued line for
# that customer. A failed remote silently cancelled a scheduled backup that way.
#
# The flag is set even when no line matched, on purpose: a run gets one attempt, full stop. Trying
# again later could only succeed on a line that appeared meanwhile, which belongs to someone else.
#
# Deleting a line does not stop it running in the pass already under way: sed -i writes a new inode
# and the running bash finishes the one it opened.
queue_drop_job() {
	local _pipe="$1" _job="$QUEUE_JOB" _n
	[ -n "$_job" ] || return 0
	[ -n "$QUEUE_JOB_DROPPED" ] && return 0
	QUEUE_JOB_DROPPED='yes'
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
	if [ "$BACKUP_MODE" = 'zstd' ]; then pzstd -q -"${BACKUP_GZIP:-3}" -; else gzip -"${BACKUP_GZIP:-3}" -; fi
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

# backup_member_write DEST TAR-ARG... - build one compressed member, and let BOTH ends of the pipe
# decide. The status of `tar ... | pzstd ... > file` is the compressor's alone, and even that was
# never read: a staging filesystem that filled up produced a truncated member and the run reported
# success over it - measured, 8 of 31 MB, `zstd -t` saying "premature end", the record written and
# the outer tar perfectly readable (#823). A half archive that looks whole is worse than none, so
# this returns false and every caller aborts.
#
# The compressor is chosen by the DEST extension, so the caller names the file it wants and the two
# never disagree about which one was written.
backup_member_write() {
	local _dest="$1"
	shift
	local -a _st
	if [ "${_dest##*.}" = 'zst' ]; then
		tar "$@" | pzstd -"$BACKUP_GZIP" - > "$_dest"
		_st=("${PIPESTATUS[@]}")
	else
		tar "$@" | gzip -n -"$BACKUP_GZIP" - > "$_dest"
		_st=("${PIPESTATUS[@]}")
	fi
	[ "${_st[0]}" -eq 0 ] && [ "${_st[1]}" -eq 0 ]
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
	PROBE_DIFF_BASE='' PROBE_DIFF_MEMBERS=''

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

	# A differential archive has to say so before anyone restores it: everything else it carries is
	# complete, but these members are not, and the base is the only thing that completes them.
	if grep -qx "\./$BACKUP_CONTAINER/backup.base" <<< "$_members"; then
		PROBE_DIFF_BASE=$(tar -xOf "$_arc" "./$BACKUP_CONTAINER/backup.base" 2> /dev/null \
			| sed -n "s/.*BASE='\([^']*\)'.*/\1/p")
		PROBE_DIFF_MEMBERS=$(tar -xOf "$_arc" "./$BACKUP_CONTAINER/backup.members" 2> /dev/null \
			| sed -n 's/=diff$//p')
	fi
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
	local _o_mode _o_fmt _o_who _prot _dom _file _bl _e _bl_list

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
	if [ -n "$PROBE_DIFF_BASE" ]; then
		printf '   DIFFERENTIAL against %s\n' "$PROBE_DIFF_BASE"
		if [ -n "$PROBE_DIFF_MEMBERS" ]; then
			printf '   incomplete without it: %s\n' "$(tr '\n' ' ' <<< "$PROBE_DIFF_MEMBERS")"
		fi
	fi
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

	# Webmail settings and address books sit in one table set per box, shared by every mailbox, so
	# the server backup carries them. Said whenever the archive has mail domains.
	if [ -n "$PROBE_MAIL" ]; then
		_found=1
		printf '   webmail settings and address books for %s mail domain(s) - shared per box, so the server backup carries them\n' \
			"$(backup_report_count "$PROBE_MAIL")"
	fi

	# Protections a domain asks for that this host cannot render. The setting survives the restore
	# on purpose, so only the report can say that it does nothing here. Asked of the renderers' own
	# predicates, and only where the module is present - this must not be what dies without one.
	[ -f "$HESTIA/include/crowdsec.sh" ] && { type crowdsec_domain_capable > /dev/null 2>&1 || source "$HESTIA/include/crowdsec.sh"; }
	[ -f "$HESTIA/include/botpolicy.sh" ] && { type botpolicy_family_enabled > /dev/null 2>&1 || source "$HESTIA/include/botpolicy.sh"; }
	_prot=''
	while IFS= read -r _dom; do
		[ -n "$_dom" ] || continue
		_file=$(backup_record_file web "$_dom")
		[ -s "$_file" ] || continue
		_rec=$(head -n1 "$_file")
		if [ "$(sed -n "s/.*CROWDSEC='\([^']*\)'.*/\1/p" <<< "$_rec")" = 'yes' ] \
			&& type crowdsec_domain_capable > /dev/null 2>&1 && ! crowdsec_domain_capable; then
			_prot="$_prot$_dom: CrowdSec"$'\n'
		fi
		_bl=$(sed -n "s/.*BOTLIMIT='\([^']*\)'.*/\1/p" <<< "$_rec")
		type botpolicy_family_enabled > /dev/null 2>&1 || continue
		# Split on the comma and only there: unquoted, a '*' would glob against the cwd.
		IFS=',' read -r -a _bl_list <<< "$_bl"
		for _e in "${_bl_list[@]}"; do
			[ -n "$_e" ] || continue
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

# Consent to write: all of it before the first write, or the run has not started. Three ways -
# selector (the selection IS the consent), CONSENT argument, or TTY prompt. An argument, never an
# env prefix (the queue line runs through bash - GHSA-2xw3); a closed set, never a character class
# (one quietly admitted a pipe once). A section implies the account, and no OTHER section.
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

# backup_php_missing DOMAIN-LIST - sets BACKUP_PHP_MISSING and BACKUP_PHP_UNREADABLE. One
# derivation, two readers (report = whole archive, consent = this run), so the list is a parameter.
# Globals, NOT stdout: in a $() subshell the unreadable register would never reach the caller.
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
# Sets LEFTOVERS_PATTERNS (tar wildcards), LEFTOVERS_SUMMARY (one line each) and
# LEFTOVERS_DEGRADED - the subset the customer is actually missing afterwards.
backup_leftovers_plan() {
	local _obj _eff
	LEFTOVERS_PATTERNS=''
	LEFTOVERS_SUMMARY=''
	LEFTOVERS_DEGRADED=''
	# Each line is <mode>TAB<pattern>. 'w' means tar may read it as a wildcard, 'x' means literally.
	# Only OUR patterns are wildcards; anything carrying a name out of the archive is literal, or a
	# database called x* extracts xyz along with it - measured, and xyz was one this host can restore.
	#
	# A fourth argument marks a whole section this box cannot take although the product can - the
	# customer is missing it afterwards. DNS and rewritten templates carry no such mark: the first
	# is a subsystem this product does not have, the second is a remap. Per-object engine mismatches
	# are marked by the restore itself, which would otherwise count them twice.
	_lo() {
		LEFTOVERS_PATTERNS="$LEFTOVERS_PATTERNS$1"$'\t'"$2"$'\n'
		LEFTOVERS_SUMMARY="$LEFTOVERS_SUMMARY$3"$'\n'
		[ -n "$4" ] && LEFTOVERS_DEGRADED="$LEFTOVERS_DEGRADED$3"$'\n'
		return 0
	}

	[ -n "$PROBE_DNS" ] && _lo w './dns/*' "$(backup_report_count "$PROBE_DNS") DNS zone(s), records and zone files"
	[ -n "$PROBE_TPL" ] && _lo w './web/*/template/*' "custom web template(s) for $(backup_report_count "$PROBE_TPL") domain(s)"

	[ -z "$WEB_SYSTEM" ] && [ -n "$PROBE_WEB" ] && _lo w './web/*' "$(backup_report_count "$PROBE_WEB") web object(s), no WEB_SYSTEM here" d
	[ -z "$MAIL_SYSTEM" ] && [ -n "$PROBE_MAIL" ] && _lo w './mail/*' "$(backup_report_count "$PROBE_MAIL") mail object(s), no MAIL_SYSTEM here" d
	[ "$PROBE_CRON" = 'yes' ] && [ -z "$CRON_SYSTEM" ] && _lo w './cron/*' "the cron section, no CRON_SYSTEM here" d

	if [ -z "$DB_SYSTEM" ]; then
		[ -n "$PROBE_DB" ] && _lo w './db/*' "$(backup_report_count "$PROBE_DB") database(s), no DB_SYSTEM here" d
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

# sqlite_snapshot FILE DEST - .backup, not cp: WAL mode (measured) lets a plain copy miss durable
# commits or tear. Without the client the copy is still taken - some backup beats none - but the
# caller is told the guarantee is gone.
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

# ── Per-customer archive folder (#789) ──────────────────────────────────────────────────────────
#
# Two allowed places per archive: $BACKUP/$user (the normal one, every run writes here) and
# $BACKUP itself (the hand-off spot - a migration archive an operator drops in by hand stays
# flat). Resolution lives here and ONLY here, so the two-place rule cannot fork into
# per-command variants.

# backup_user_dir USER - create the customer's folder on first use. hestia owns it (the panel
# pool reads as hestia), the customer's group may enter and list, nobody else - $BACKUP itself
# is 711, so names are not enumerable. The group may not exist yet (a restore of a not-yet-
# created customer downloads first); set when possible, the next backup run repairs it.
backup_user_dir() {
	[ -d "$BACKUP/$1" ] || mkdir -p "$BACKUP/$1"
	chown hestia "$BACKUP/$1"
	getent group "$1" > /dev/null 2>&1 && chgrp "$1" "$BACKUP/$1"
	chmod 750 "$BACKUP/$1"
}

# backup_archive_path USER NAME - resolve NAME against the two allowed places, customer folder
# first. NAME is a basename (the #661 validator allows no slash), but -e follows symlinks and
# $BACKUP is environment-overridable, so the find must resolve back into exactly the directory
# it was found in. Sets BACKUP_ARCHIVE (path) and BACKUP_ARCHIVE_DIR ('user'|'root').
# Returns 1 = in neither place, 2 = found but does not resolve - refused loudly, a planted
# symlink must not fall through to the other place.
backup_archive_path() {
	local _user="$1" _name="$2" _dir _real _dreal
	BACKUP_ARCHIVE='' BACKUP_ARCHIVE_DIR=''
	for _dir in "$BACKUP/$_user" "$BACKUP"; do
		[ -e "$_dir/$_name" ] || continue
		_real=$(realpath -e -- "$_dir/$_name" 2> /dev/null)
		_dreal=$(realpath -e -- "$_dir" 2> /dev/null)
		if [ -z "$_real" ] || [ -z "$_dreal" ] || [ "${_real%/*}" != "$_dreal" ] || [ ! -f "$_real" ]; then
			return 2
		fi
		BACKUP_ARCHIVE="$_dir/$_name"
		if [ "$_dir" = "$BACKUP" ]; then BACKUP_ARCHIVE_DIR='root'; else BACKUP_ARCHIVE_DIR='user'; fi
		return 0
	done
	return 1
}

# Local storage
# Defining local storage function
local_backup() {

	rm -f $BACKUP/$user/$user.$backup_new_date.tar

	# Checking retention. An adopted archive is the operator's own file - a migration source they put
	# there - and it carries a date in its name like any other, so the rotation below would take it
	# first. Excluded by NAME from the records, not by age.
	backup_list=$(ls -lrt $BACKUP/$user/ 2> /dev/null | awk '{print $9}' | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
	if [ -s "$USER_DATA/backup.conf" ]; then
		while IFS= read -r _adopted; do
			[ -n "$_adopted" ] || continue
			backup_list=$(grep -vxF -- "$_adopted" <<< "$backup_list")
		done < <(grep -E "(^| )ADOPTED='yes'( |$)" "$USER_DATA/backup.conf" | sed -n "s/^BACKUP='\([^']*\)'.*/\1/p")
	fi
	backups_count=$(grep -c . <<< "$backup_list")
	if [ "$BACKUPS" -le "$backups_count" ]; then

		# Removing old backup
		for backup in $(echo "$backup_list" \
			| backup_set_removals "$USER_DATA/backup.conf" "$BACKUPS" "$diff_base"); do
			backup_date=$(echo $backup | sed -e "s/$user.//" -e "s/.tar$//")
			echo -e "$(date "+%F %T") Rotated: $backup_date" \
				| tee -a $BACKUP/$user/$user.log
			rm -f $BACKUP/$user/$backup
		done
	fi

	# Checking disk space
	disk_usage=$(df $BACKUP | tail -n1 | tr ' ' '\n' | grep % | cut -f 1 -d %)
	if [ "$disk_usage" -ge "$BACKUP_DISK_LIMIT" ]; then
		rm -rf $tmpdir
		rm -f $BACKUP/$user/$user.log
		queue_drop_job "$CONF_DIR/queue/backup.pipe"
		echo "Not enough disk space" | $SENDMAIL -s "$subj" "$email" "yes"
		check_result "$E_DISK" "Not enough dsk space"
	fi

	# Creating final tarball
	cd $tmpdir
	tar -cf $BACKUP/$user/$user.$backup_new_date.tar .
	chmod 640 $BACKUP/$user/$user.$backup_new_date.tar
	chown "hestia":"$user" $BACKUP/$user/$user.$backup_new_date.tar
	localbackup='yes'
	echo -e "$(date "+%F %T") Local: $BACKUP/$user/$user.$backup_new_date.tar" \
		| tee -a $BACKUP/$user/$user.log
}

# backup_target_keep TYPE - how many SETS this remote place retains. Its own BACKUPS_KEEP if
# the target conf carries one, the customer's $BACKUPS otherwise - so with no per-target number
# every place mirrors the package and nothing moves by default. The pattern starts at 1: zero
# and garbage both fall back to $BACKUPS, because a keep of 0 handed to the rotation would be
# a mass deletion - "retain nothing" is not a retention setting (add-host refuses it by name).
backup_target_keep() {
	local _k
	_k=$(sed -n "s/^BACKUPS_KEEP='\([1-9][0-9]*\)'.*/\1/p" "$HESTIA/conf/$1.backup.conf" 2> /dev/null | head -1)
	echo "${_k:-$BACKUPS}"
}

# remote_file_present TYPE NAME - is NAME on the target, asked from a FRESH listing? Content
# over exit codes: the put pipelines discard theirs, and a chmod-000 target gave a green run,
# a record, and an archive that existed nowhere (stage-0 protocol, C5). Same pipelines as the
# rotation listings, CR stripped for the same pty reason.
remote_file_present() {
	local _t="$1" _n="$2" _l=''
	case "$_t" in
		ftp)
			if [ -z "$BPATH" ]; then
				_l=$(ftpc "ls" | tr -d "\r" | awk '{print $9}')
			else
				_l=$(ftpc "cd $BPATH" "ls" | tr -d "\r" | awk '{print $9}')
			fi
			;;
		sftp)
			if [ -z "$BPATH" ]; then
				_l=$(sftpc "ls -l" | tr -d "\r" | awk '{print $9}')
			else
				_l=$(sftpc "cd $BPATH" "ls -l" | tr -d "\r" | awk '{print $9}')
			fi
			;;
		rclone)
			if [ -z "$BPATH" ]; then
				_l=$(rclone lsf "$HOST:" 2> /dev/null | cut -d' ' -f1)
			else
				_l=$(rclone lsf "$HOST:$BPATH" 2> /dev/null | cut -d' ' -f1)
			fi
			;;
	esac
	grep -qxF -- "$_n" <<< "$_l"
}

# backup_download_norm NAME - a fetched copy carries the same rights picture as a locally
# written archive. The group may not exist yet (DR box, account created later in the restore).
backup_download_norm() {
	[ -f "$BACKUP/$user/$1" ] || return 0
	chmod 640 "$BACKUP/$user/$1"
	chown hestia "$BACKUP/$user/$1"
	getent group "$user" > /dev/null 2>&1 && chgrp "$user" "$BACKUP/$user/$1"
	return 0
}

# FTP Functions
# Defining ftp command function. /usr/bin/ftp exits 0 even when it cannot connect, so failure is
# read from the output.
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

	# Checking retention. tr -d CR: expect runs in a pty, every line ends CRLF and tar$ never matches.
	if [ -z $BPATH ]; then
		backup_list=$(ftpc "ls" | tr -d "\r" | awk '{print $9}' | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
	else
		backup_list=$(ftpc "cd $BPATH" "ls" | tr -d "\r" | awk '{print $9}' | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
	fi
	backups_count=$(grep -c . <<< "$backup_list")
	target_keep=$(backup_target_keep ftp)
	if [ "$backups_count" -ge "$target_keep" ]; then
		for backup in $(echo "$backup_list" \
			| backup_set_removals "$USER_DATA/backup.conf" "$target_keep" "$diff_base"); do
			backup_date=$(echo $backup | sed -e "s/$user.//" -e "s/.tar$//")
			echo -e "$(date "+%F %T") Rotated ftp backup: $backup_date" \
				| tee -a $BACKUP/$user/$user.log
			if [ -z $BPATH ]; then
				ftpc "delete $backup"
			else
				ftpc "cd $BPATH" "delete $backup"
			fi
		done
	fi

	# A diff without its base on THIS target is unrestorable there - a target enabled after the
	# base run never received it. The listing is already fetched; ship the base first.
	if [ -n "$diff_base" ] && ! grep -qxF -- "$diff_base" <<< "$backup_list" \
		&& ! backup_archive_path "$user" "$diff_base"; then
		# Not fatal: the restore chain fetches the base from whichever place still has it. But
		# said out loud - this target alone cannot restore the diff it is about to receive.
		echo "$(date "+%F %T") Warning: base $diff_base is not local and not on the ftp target - a restore needs another source for it" \
			| tee -a $BACKUP/$user/$user.log
	fi
	if [ -n "$diff_base" ] && backup_archive_path "$user" "$diff_base" && ! grep -qxF -- "$diff_base" <<< "$backup_list"; then
		echo "$(date "+%F %T") Uploading base $diff_base missing on ftp target" | tee -a $BACKUP/$user/$user.log
		cd "${BACKUP_ARCHIVE%/*}"
		if [ -z $BPATH ]; then
			ftpc "put $diff_base"
		else
			ftpc "cd $BPATH" "put $diff_base"
		fi
		if ! remote_file_present ftp "$diff_base"; then
			error="base $diff_base did not arrive on the ftp target - every diff there would be unrestorable"
			echo "$error" | $SENDMAIL -s "$subj" $email $notify
			echo "$error"
			errorcode="$E_FTP"
			return "$E_FTP"
		fi
	fi

	# Uploading backup archive
	if [ "$localbackup" = 'yes' ]; then
		cd $BACKUP/$user
		if [ -z $BPATH ]; then
			ftpc "put $user.$backup_new_date.tar"
		else
			ftpc "cd $BPATH" "put $user.$backup_new_date.tar"
		fi
	else
		cd $tmpdir
		tar -cf $BACKUP/$user/$user.$backup_new_date.tar .
		cd $BACKUP/$user/
		if [ -z $BPATH ]; then
			ftpc "put $user.$backup_new_date.tar"
		else
			ftpc "cd $BPATH" "put $user.$backup_new_date.tar"
		fi
		rm -f $user.$backup_new_date.tar
	fi
	if ! remote_file_present ftp "$user.$backup_new_date.tar"; then
		error="$user.$backup_new_date.tar did not arrive on the ftp target"
		echo "$error" | $SENDMAIL -s "$subj" $email $notify
		echo "$error"
		errorcode="$E_FTP"
		return "$E_FTP"
	fi
}

# FTP backup download function
ftp_download() {
	source_conf "$HESTIA/conf/ftp.backup.conf"
	if [ -z "$PORT" ]; then
		PORT='21'
	fi
	backup_user_dir "$user"
	cd $BACKUP/$user
	if [ -z $BPATH ]; then
		ftpc "get $1"
	else
		ftpc "cd $BPATH" "get $1"
	fi
	backup_download_norm "$1"
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

# Path-producing exclusions only: DB and CRON exclude objects, not paths. The stage is never
# excluded, whatever the customer writes into the list.
restic_excludes() {
	local _u="$1" _f="$CONF_DIR/users/$1/backup-excludes.conf" _e _list=()
	[ -f "$_f" ] || return 0
	# All five keys local: the file sets them globally, and the caller's subshell is not our guard.
	local WEB='' MAIL='' DB='' CRON='' USER=''
	# shellcheck disable=SC1090
	source "$_f" 2> /dev/null
	# read -a, never an unquoted expansion: a '*' inside the list would glob against the cwd (#761).
	case "$WEB" in
		'*') echo "$HOMEDIR/$_u/web" ;;
		?*)
			IFS=',' read -r -a _list <<< "$WEB"
			for _e in "${_list[@]}"; do
				[ -n "$_e" ] && echo "$HOMEDIR/$_u/web/$_e"
			done
			;;
	esac
	case "$MAIL" in
		'*') echo "$HOMEDIR/$_u/mail" ;;
		?*)
			IFS=',' read -r -a _list <<< "$MAIL"
			for _e in "${_list[@]}"; do
				[ -n "$_e" ] && echo "$HOMEDIR/$_u/mail/$_e"
			done
			;;
	esac
	case "$USER" in
		'*')
			for _e in "$HOMEDIR/$_u"/* "$HOMEDIR/$_u"/.[!.]*; do
				[ -e "$_e" ] || continue
				case "${_e##*/}" in web | mail | .dumps) continue ;; esac
				echo "$_e"
			done
			;;
		?*)
			IFS=',' read -r -a _list <<< "$USER"
			for _e in "${_list[@]}"; do
				case "$_e" in '' | .dumps) continue ;; esac
				echo "$HOMEDIR/$_u/$_e"
			done
			;;
	esac
	return 0
}

# What the dumps really weigh, measured with the very command that writes them - a probe with its
# own command line drifts from the real one the day a flag changes. Roughly a minute per 9 GB, which
# is nothing against a backup run (#805). Returns bytes; a failed dump returns 1 and no number.
restic_dump_size_measured() {
	local _u="$1" _line _db _type _sum=0 _bytes _rc _scratch
	local database TYPE HOST USER PASSWORD PORT mycnf host_str
	[ -f "$CONF_DIR/users/$_u/db.conf" ] || {
		echo 0
		return 0
	}
	_scratch=$(mktemp -d) || return 1
	while read -r _line; do
		_db=$(sed -n "s/.*DB='\([^']*\)'.*/\1/p" <<< "$_line")
		_type=$(sed -n "s/.*TYPE='\([^']*\)'.*/\1/p" <<< "$_line")
		[ -n "$_db" ] || continue
		database="$_db"
		TYPE="$_type"
		HOST=$(sed -n "s/.*HOST='\([^']*\)'.*/\1/p" <<< "$_line")
		# The dump's own exit code, never wc's: a dump that fails measures zero bytes and would wave
		# through the very check it feeds. The subshell also contains the dump helpers' `rm -rf
		# $tmpdir` and their `exit` on error.
		_bytes=$(
			tmpdir="$_scratch"
			notify='no'
			case "$_type" in
				mysql)
					mysql_connect "$HOST"
					mysql_dump /dev/stdout "$_db" | wc -c
					exit "${PIPESTATUS[0]}"
					;;
				pgsql)
					psql_connect "$HOST"
					psql_dump /dev/stdout "$_db" | wc -c
					exit "${PIPESTATUS[0]}"
					;;
				*) exit 1 ;;
			esac
		)
		_rc=$?
		case "$_rc:$_bytes" in
			0:*[0-9]) _sum=$((_sum + _bytes)) ;;
			*)
				rm -rf "$_scratch"
				return 1
				;;
		esac
	done < "$CONF_DIR/users/$_u/db.conf"
	rm -rf "$_scratch"
	echo "$_sum"
}

# What a first snapshot will add: the home tree the backup actually walks. The exclude list comes
# from restic_excludes, the same one restic is handed, so a customer exclusion cannot make the two
# disagree - a second hand-built list would drift on the day someone excludes a directory. Bytes;
# returns 1 and no number if du cannot read the tree.
restic_home_size_measured() {
	local _u="$1" _x _ex=() _out
	while read -r _x; do
		[ -n "$_x" ] && _ex+=(--exclude="$_x")
	done < <(restic_excludes "$_u")
	_out=$(nice -n 19 du -sb "${_ex[@]}" "$HOMEDIR/$_u" 2> /dev/null | cut -f1)
	case "$_out" in '' | *[!0-9]*) return 1 ;; esac
	echo "$_out"
}

# The demands of one run, booked per FILESYSTEM: two paths on one device share its free space, so
# there they add up, and on separate devices each stands alone. Identified by device number, not by
# path text - /backup can be a symlink or a bind mount. Upstream books a full backup at twice the
# archive for the same reason, only without measuring. A reserve on top, because filling a device to
# the last byte hurts every customer on it, not just this run.
#
# Does NOT cover: what a repeat snapshot adds to an existing repository. That is the delta against
# what the repository already holds, and nothing short of the backup itself knows it - restic's own
# stats would be a remembered number, the very kind that was dropped for the dumps. So a later run
# is booked at its dumps only, and a repository that grows past the reserve is caught by the run
# after it, not by this one.
space_budget_refused() {
	local _spec _path _need _dev _free _total _reserve _first _df
	declare -A _by_dev=()
	declare -A _paths=()
	for _spec in "$@"; do
		_path="${_spec%:*}"
		_need="${_spec##*:}"
		# Every argument must mean something. A path that should be there and is not used to be
		# skipped in silence, which dropped its whole demand and let the barrier say yes.
		case "$_need" in '' | *[!0-9]*) return 2 ;; esac
		[ -d "$_path" ] || return 2
		[ "$_need" -gt 0 ] || continue
		_dev=$(stat -c %d "$_path" 2> /dev/null) || return 2
		_by_dev[$_dev]=$((${_by_dev[$_dev]:-0} + _need))
		_paths[$_dev]="${_paths[$_dev]:+${_paths[$_dev]} and }$_path"
	done
	for _dev in "${!_by_dev[@]}"; do
		_first=${_paths[$_dev]%% and *}
		# One df, one moment: two calls gave the two numbers of the comparison different ages.
		_df=$(df -PB1 "$_first" 2> /dev/null) || return 2
		read -r _total _free <<< "$(awk 'END {print $2, $4}' <<< "$_df")"
		case "$_total" in '' | *[!0-9]*) return 2 ;; esac
		case "$_free" in '' | *[!0-9]*) return 2 ;; esac
		_reserve=$((_total / 20))
		if [ "$((${_by_dev[$_dev]} + _reserve))" -gt "$_free" ]; then
			echo "${_paths[$_dev]} needs $((${_by_dev[$_dev]} / 1048576)) MB plus a" \
				"$((_reserve / 1048576)) MB reserve, $((_free / 1048576)) MB free"
			return 1
		fi
	done
	return 0
}

# The package that belongs to a snapshot: over the tag the snapshot carries, and if that is gone,
# over the snapshot id the packages name - the same two directions as the pairing guard.
restic_pkg_for_snapshot() {
	local _u="$1" _s="$2" _key="$CONF_DIR/users/$1/restic.conf" _repo _json _sid _stamp _pkg
	_repo=$(restic_repo_base) || return 1
	_json=$(restic --repo "$_repo$_u" --password-file "$_key" --json snapshots "$_s" 2> /dev/null) || return 1
	_sid=$(grep -o '"short_id":"[^"]*"' <<< "$_json" | head -1 | cut -d'"' -f4)
	[ -n "$_sid" ] || return 1
	_stamp=$(grep -o "\"meta:$_u\.[^\"]*\"" <<< "$_json" | head -1 | tr -d '"')
	if [ -n "$_stamp" ] && [ -f "$BACKUP/$_u/${_stamp#meta:}.meta.tgz" ]; then
		echo "$BACKUP/$_u/${_stamp#meta:}.meta.tgz"
		return 0
	fi
	for _pkg in "$BACKUP/$_u/$_u".*.meta.tgz; do
		[ -f "$_pkg" ] || continue
		[ "$(tar -xzOf "$_pkg" ./restic.meta 2> /dev/null | sed -n "s/^SNAPSHOT='\([^']*\)'.*/\1/p")" = "$_sid" ] || continue
		echo "$_pkg"
		return 0
	done
	return 1
}

# One reader and one unpacker for the package - the restore path never looks into the snapshot for
# metadata again, it moved out of the home in stage 2a.
# --no-wildcards: the member names carry record values (domain, database), and a name holding a
# glob would pull foreign objects out of the package (the #2d rule for archive-controlled names).
restic_meta_cat() { tar --no-wildcards -xzOf "$1" "./$2" 2> /dev/null; }
restic_meta_unpack() {
	local _pkg="$1" _dest="$2"
	shift 2
	mkdir -p "$_dest" || return 1
	tar --no-wildcards -xzf "$_pkg" -C "$_dest" "$@" 2> /dev/null
}

# Derived, never an argument: the stager removes both as root.
restic_meta_dir() { echo "${BACKUP_TEMP:-$BACKUP}/restic-meta.$1"; }
restic_dump_dir() { echo "$HOMEDIR/$1/.dumps"; }

# SFTP Functions
# sftp command function. The rc fallback belongs at the END: eof also arrives after the regular
# exit and would fail every success.
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

            if {[info exists rc] != 1} {
                set output "Connection to $HOST failed."
                set rc $E_CONNECT
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

            if {[info exists rc] != 1} {
                set output "Connection to $HOST failed."
                set rc $E_CONNECT
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
	backup_user_dir "$user"
	cd $BACKUP/$user
	if [ -z $BPATH ]; then
		sftpc "get $1" > /dev/null 2>&1
	else
		sftpc "cd $BPATH" "get $1" > /dev/null 2>&1
	fi
	backup_download_norm "$1"
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
		| tee -a $BACKUP/$user/$user.log

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
			*) error="sftp to $HOST failed with code $rc" ;;
		esac
		echo "$error" | $SENDMAIL -s "$subj" $email "yes"
		queue_drop_job "$CONF_DIR/queue/backup.pipe"
		echo "$error"
		errorcode="$rc"
		return "$rc"
	fi

	# Checking retention (Only include .tar files)
	if [ -z $BPATH ]; then
		backup_list=$(sftpc "ls -l" | tr -d "\r" | awk '{print $9}' | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
	else
		backup_list=$(sftpc "cd $BPATH" "ls -l" | tr -d "\r" | awk '{print $9}' | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
	fi
	backups_count=$(grep -c . <<< "$backup_list")
	target_keep=$(backup_target_keep sftp)
	if [ "$backups_count" -ge "$target_keep" ]; then
		for backup in $(echo "$backup_list" \
			| backup_set_removals "$USER_DATA/backup.conf" "$target_keep" "$diff_base"); do
			backup_date=$(echo $backup | sed -e "s/$user.//" -e "s/.tar.*$//")
			echo -e "$(date "+%F %T") Rotated sftp backup: $backup_date" \
				| tee -a $BACKUP/$user/$user.log
			if [ -z $BPATH ]; then
				sftpc "rm $backup" > /dev/null 2>&1
			else
				sftpc "cd $BPATH" "rm $backup" > /dev/null 2>&1
			fi
		done
	fi

	# Same edge as on ftp: a base absent on this target makes every diff there unrestorable.
	if [ -n "$diff_base" ] && ! grep -qxF -- "$diff_base" <<< "$backup_list" \
		&& ! backup_archive_path "$user" "$diff_base"; then
		echo "$(date "+%F %T") Warning: base $diff_base is not local and not on the sftp target - a restore needs another source for it" \
			| tee -a $BACKUP/$user/$user.log
	fi
	if [ -n "$diff_base" ] && backup_archive_path "$user" "$diff_base" && ! grep -qxF -- "$diff_base" <<< "$backup_list"; then
		echo "$(date "+%F %T") Uploading base $diff_base missing on sftp target" | tee -a $BACKUP/$user/$user.log
		cd "${BACKUP_ARCHIVE%/*}"
		if [ -z $BPATH ]; then
			sftpc "put $diff_base" "chmod 0600 $diff_base" > /dev/null 2>&1
		else
			sftpc "cd $BPATH" "put $diff_base" "chmod 0600 $diff_base" > /dev/null 2>&1
		fi
		if ! remote_file_present sftp "$diff_base"; then
			error="base $diff_base did not arrive on the sftp target - every diff there would be unrestorable"
			echo "$error" | $SENDMAIL -s "$subj" $email $notify
			echo "$error"
			errorcode="$E_FTP"
			return "$E_FTP"
		fi
	fi

	# Uploading backup archive
	echo "$(date "+%F %T") Uploading $user.$backup_new_date.tar" | tee -a $BACKUP/$user/$user.log
	if [ "$localbackup" = 'yes' ]; then
		cd $BACKUP/$user
		if [ -z $BPATH ]; then
			sftpc "put $user.$backup_new_date.tar" "chmod 0600 $user.$backup_new_date.tar" > /dev/null 2>&1
		else
			sftpc "cd $BPATH" "put $user.$backup_new_date.tar" "chmod 0600 $user.$backup_new_date.tar" > /dev/null 2>&1
		fi
	else
		cd $tmpdir
		tar -cf $BACKUP/$user/$user.$backup_new_date.tar .
		cd $BACKUP/$user/
		if [ -z $BPATH ]; then
			sftpc "put $user.$backup_new_date.tar" "chmod 0600 $user.$backup_new_date.tar" > /dev/null 2>&1
		else
			sftpc "cd $BPATH" "put $user.$backup_new_date.tar" "chmod 0600 $user.$backup_new_date.tar" > /dev/null 2>&1
		fi
		rm -f $user.$backup_new_date.tar
	fi
	if ! remote_file_present sftp "$user.$backup_new_date.tar"; then
		error="$user.$backup_new_date.tar did not arrive on the sftp target"
		echo "$error" | $SENDMAIL -s "$subj" $email $notify
		echo "$error"
		errorcode="$E_FTP"
		return "$E_FTP"
	fi
}

rclone_backup() {
	# Define rclone config
	source_conf "$HESTIA/conf/rclone.backup.conf"
	echo -e "$(date "+%F %T") Upload With Rclone to $HOST: $user.$backup_new_date.tar"
	if [ "$localbackup" != 'yes' ]; then
		cd $tmpdir
		tar -cf $BACKUP/$user/$user.$backup_new_date.tar .
	fi
	cd $BACKUP/$user/

	if [ -z "$BPATH" ]; then
		# Same edge as on ftp/sftp; rclone lists only after the upload, so ask once beforehand.
		# One listing, one truth: the same answer drives the warning and the upload branch.
		if [ -n "$diff_base" ] \
			&& ! rclone lsf $HOST: 2> /dev/null | cut -d' ' -f1 | grep -qxF -- "$diff_base"; then
			if ! backup_archive_path "$user" "$diff_base"; then
				echo "$(date "+%F %T") Warning: base $diff_base is not local and not on the rclone target - a restore needs another source for it" \
					| tee -a $BACKUP/$user/$user.log
			else
				echo "$(date "+%F %T") Uploading base $diff_base missing on rclone target" | tee -a $BACKUP/$user/$user.log
				if ! rclone copy -v "$BACKUP_ARCHIVE" $HOST:; then
					error="base $diff_base did not arrive on the rclone target - every diff there would be unrestorable"
					echo "$error" | $SENDMAIL -s "$subj" $email $notify
					echo "$error"
					errorcode="$E_CONNECT"
					return "$E_CONNECT"
				fi
			fi
		fi
		# $HOST: plain - $backup here would be the LOOP VARIABLE of an earlier transport's rotation
		# return, not check_result: check_result exits the whole run BEFORE the record is written,
		# so with local,rclone a finished local archive lost its record (stage-0 class E).
		if ! rclone copy -v $user.$backup_new_date.tar $HOST:; then
			error="$user.$backup_new_date.tar did not arrive on the rclone target"
			echo "$error" | $SENDMAIL -s "$subj" $email $notify
			echo "$error"
			errorcode="$E_CONNECT"
			return "$E_CONNECT"
		fi

		# Only include *.tar files
		backup_list=$(rclone lsf $HOST: | cut -d' ' -f1 | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
		backups_count=$(grep -c . <<< "$backup_list")
		target_keep=$(backup_target_keep rclone)
		if [ "$backups_count" -ge "$target_keep" ]; then
			for backup in $(echo "$backup_list" \
				| backup_set_removals "$USER_DATA/backup.conf" "$target_keep" "$diff_base"); do
				echo "Delete file: $backup"
				rclone deletefile $HOST:/$backup
			done
		fi
	else
		# One listing, one truth: the same answer drives the warning and the upload branch.
		if [ -n "$diff_base" ] \
			&& ! rclone lsf $HOST:$BPATH 2> /dev/null | cut -d' ' -f1 | grep -qxF -- "$diff_base"; then
			if ! backup_archive_path "$user" "$diff_base"; then
				echo "$(date "+%F %T") Warning: base $diff_base is not local and not on the rclone target - a restore needs another source for it" \
					| tee -a $BACKUP/$user/$user.log
			else
				echo "$(date "+%F %T") Uploading base $diff_base missing on rclone target" | tee -a $BACKUP/$user/$user.log
				if ! rclone copy -v "$BACKUP_ARCHIVE" $HOST:$BPATH; then
					error="base $diff_base did not arrive on the rclone target - every diff there would be unrestorable"
					echo "$error" | $SENDMAIL -s "$subj" $email $notify
					echo "$error"
					errorcode="$E_CONNECT"
					return "$E_CONNECT"
				fi
			fi
		fi
		if ! rclone copy -v $user.$backup_new_date.tar $HOST:$BPATH; then
			error="$user.$backup_new_date.tar did not arrive on the rclone target"
			echo "$error" | $SENDMAIL -s "$subj" $email $notify
			echo "$error"
			errorcode="$E_CONNECT"
			return "$E_CONNECT"
		fi

		# Only include *.tar files
		backup_list=$(rclone lsf $HOST:$BPATH | cut -d' ' -f1 | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
		backups_count=$(grep -c . <<< "$backup_list")
		target_keep=$(backup_target_keep rclone)
		if [ "$backups_count" -ge "$target_keep" ]; then
			for backup in $(echo "$backup_list" \
				| backup_set_removals "$USER_DATA/backup.conf" "$target_keep" "$diff_base"); do
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
	backup_user_dir "$user"
	cd $BACKUP/$user
	if [ -z "$BPATH" ]; then
		rclone copy -v $HOST:/$1 ./
	else
		rclone copy -v $HOST:$BPATH/$1 ./
	fi
	backup_download_norm "$1"
}

# ── Content map (#712) ───────────────────────────────────────────────────────────────────────────
#
# One record per entry, five NUL-terminated fields, no record separator, unordered by design:
#   <path>\0<hash>\0<mode>\0<uid>:<gid>\0<symlink target>\0
# Hash field: "" = type carries none (dir/symlink/device); "-" = withdrawn or never taken, compares
# as changed even against itself. Paths and metadata come from the member listing, hashes from the
# tree BEFORE the member is tarred - the map is never newer than the archive, so every race lands
# on re-ship, never on silent omission. Per-file hashing via --to-command cost 836s of an 838s run
# on 153k files (measured); batched off the tree it is ~2s.
BACKUP_MAP_ALGO='b3sum'

# tar autodetects zstd but exits non-zero while doing it (measured), so the decompressor is named.
backup_map_taropt() {
	case "$1" in
		*.zst) echo '--zstd' ;;
		*.gz) echo '--gzip' ;;
		*) echo '' ;;
	esac
}

# backup_map_hash_tree OUTTABLE [PATH...] - <path>\0<hash>\0 pairs off the live tree, batched.
# Pairing is positional (--no-names): a vanished file shifts the columns, the count check catches
# it, one retry absorbs a moving delivery, a second miss leaves the member unmapped.
backup_map_hash_tree() {
	local _out="$1" _try _paths _hashes
	shift
	[ $# -gt 0 ] || set -- .
	_paths=$(mktemp)
	_hashes=$(mktemp)
	for _try in 1 2; do
		# Count runs against the frozen list xargs consumed, never a re-walk: arrival plus
		# expunge would count the same twice with a shifted middle.
		find "$@" -type f -printf '%p\0%s.%T@\0' 2> /dev/null > "$_out.stat"
		# BEGIN-only; -v keeps awk from re-reading the file in its empty main loop.
		awk -v sf="$_out.stat" 'BEGIN { RS = "\0"; while ((getline p < sf) > 0) { if ((getline s < sf) <= 0) break; printf "%s%c", p, 0 } }' \
			< /dev/null > "$_paths"
		xargs -0 -r "$BACKUP_MAP_ALGO" --no-names < "$_paths" 2> "$_hashes.err" > "$_hashes"
		if [ "$(tr -cd '\0' < "$_paths" | wc -c)" -eq "$(grep -c . "$_hashes")" ]; then
			awk -v pf="$_paths" -v hf="$_hashes" 'BEGIN {
				while ((getline h < hf) > 0) { n++; hash[n] = h }
				close(hf)
				RS = "\0"
				while ((getline p < pf) > 0) { i++; printf "%s%c%s%c", p, 0, hash[i], 0 }
			}' < /dev/null > "$_out"
			rm -f "$_paths" "$_hashes" "$_hashes.err"
			return 0
		fi
	done
	# Permanent and transient failures must not read alike: name what the hasher refused.
	sed 's/^/Warning:   /' "$_hashes.err" 2> /dev/null | head -5 >&2
	rm -f "$_paths" "$_hashes" "$_hashes.err" "$_out" "$_out.stat"
	return 1
}

# backup_map_hash_verify OUTTABLE [PATH...] - run AFTER the tar: any file whose size or mtime moved
# since the snapshot gets "-". Without it, a later revert to the hashed bytes would read as covered
# by a base that holds the other version - and never heal.
backup_map_hash_verify() {
	local _out="$1" _now
	shift
	[ -s "$_out" ] || return 0
	[ -s "$_out.stat" ] || return 0
	[ $# -gt 0 ] || set -- .
	_now=$(mktemp)
	find "$@" -type f -printf '%p\0%s.%T@\0' 2> /dev/null > "$_now"
	awk -v tf="$_out.stat" -v nf="$_now" -v of="$_out" 'BEGIN {
		RS = "\0"
		while ((getline p < tf) > 0) { if ((getline s < tf) <= 0) break; then_stat[p] = s }
		close(tf)
		while ((getline p < nf) > 0) { if ((getline s < nf) <= 0) break; now_stat[p] = s }
		close(nf)
		while ((getline p < of) > 0) {
			if ((getline h < of) <= 0) break
			if (then_stat[p] != now_stat[p]) h = "-"
			printf "%s%c%s%c", p, 0, h, 0
		}
	}' < /dev/null > "$_out.checked"
	mv "$_out.checked" "$_out"
	rm -f "$_now" "$_out.stat"
}

# backup_map_member ARCHIVE PREFIX HASHTABLE - records for one member: one LC_ALL=C listing for
# paths/types/modes/owners, hashes joined in by path. Hardlink members join like regular files;
# --to-command never even handed them over.
backup_map_member() {
	local _arc="$1" _pre="$2" _tbl="$3" _opt
	[ -f "$_arc" ] || return 0
	_opt=$(backup_map_taropt "$_arc")
	[ -s "$_tbl" ] || _tbl=/dev/null

	# KNOWN LIMIT: the listing is line-based (tar has no NUL variant); a newline in a name leaves a
	# plausible TRUNCATED record, only the spill line is detectable - hence the warning wording.
	# LC_ALL=C pins the hardlink phrase ("link to") the parser relies on.
	# shellcheck disable=SC2086
	LC_ALL=C tar $_opt -tvf "$_arc" --quoting-style=literal --numeric-owner 2> /dev/null \
		| awk -v pre="$_pre" -v tbl="$_tbl" '
			function octal(p,   i, c, v, r) {
				r = ""
				for (i = 1; i <= 3; i++) {
					v = 0
					c = substr(p, 2 + (i - 1) * 3, 3)
					if (substr(c, 1, 1) == "r") v += 4
					if (substr(c, 2, 1) == "w") v += 2
					if (substr(c, 3, 1) ~ /[xst]/) v += 1
					r = r v
				}
				return "0" r
			}
			BEGIN {
				# Table first, while RS can still be switched back.
				RS = "\0"
				while ((getline p < tbl) > 0) {
					if ((getline h < tbl) > 0) hash[p] = h
					else break
				}
				close(tbl)
				RS = "\n"
			}
			/^[-hdlpbc]/ {
				if (length($1) != 10 || $1 !~ /^[-hdlpbc][rwxsStT-]+$/ || index($2, "/") == 0) { bad++; next }
				typ = substr($0, 1, 1)
				split($2, o, "/")
				# Name = tail after field five (keeps spaces); devices print major,minor as
				# ONE field, so the positions hold for every type.
				n = index($0, $5) + length($5) + 1
				rest = substr($0, n)
				target = ""
				if (typ == "l") {
					i = index(rest, " -> ")
					if (i > 0) { target = substr(rest, i + 4); rest = substr(rest, 1, i - 1) }
				}
				if (typ == "h") {
					i = index(rest, " link to ")
					if (i > 0) rest = substr(rest, 1, i - 1)
				}
				# "-" = withdrawn or never taken, reads as changed forever (see section header).
				h = ""
				if (typ == "-" || typ == "h") { h = hash[rest]; if (h == "") h = "-" }
				# Names EXACTLY as stored ("./" and trailing slash intact): -T matches literally,
				# and the table keys carry the same form. (No apostrophe in this awk block.)
				printf "%s|%s%c%s%c%s%c%s:%s%c%s%c", pre, rest, 0, h, 0, octal($1), 0, o[1], o[2], 0, target, 0
			}
			$0 !~ /^[-dlbcpshD]/ { bad++ }
			END {
				if (bad) printf "Warning: %d unparseable listing line(s) in %s - a record may be truncated or missing\n", bad, pre > "/dev/stderr"
			}'
}

# backup_map_write TMPDIR MAPFILE TBLDIR - the map for everything this archive diffs against: web and mail.
# The other members are always written whole, so they have nothing to compare.
backup_map_write() {
	local _tmp="$1" _out="$2" _tbldir="$3" _d _arc _n
	: > "$_out"
	for _d in "$_tmp"/web/*/ "$_tmp"/mail/*/; do
		[ -d "$_d" ] || continue
		_n=$(basename "$_d")
		for _arc in "$_d"domain_data.tar.zst "$_d"domain_data.tar.gz "$_d"accounts.tar.zst "$_d"accounts.tar.gz; do
			[ -f "$_arc" ] || continue
			case "$_d" in
				*/web/*) backup_map_member "$_arc" "web/$_n" "$_tbldir/web.$_n.tbl" ;;
				*/mail/*) backup_map_member "$_arc" "mail/$_n" "$_tbldir/mail.$_n.tbl" ;;
			esac
		done
	done >> "$_out"
	# A member that produced no records is a suspicion, not a success: a tree that could not be read
	# looks exactly like one that is empty. Counted, so the caller can say which.
	backup_map_count "$_out"
}

# backup_map_count MAPFILE - how many records, derived from the field count (five per record).
# A remainder means one record has the wrong field count and every field after it is shifted by one
# in any reader - such a map counts as unusable (0), not as a plausible smaller number.
backup_map_count() {
	local _f=$((0))
	[ -s "$1" ] || {
		echo 0
		return
	}
	_f=$(tr -cd '\0' < "$1" | wc -c)
	if [ $((_f % 5)) -ne 0 ]; then
		echo "Warning: map $1 holds $_f fields, not a multiple of five - treating it as unreadable" >&2
		echo 0
		return
	fi
	echo $((_f / 5))
}

# backup_map_prune MAPDIR BACKUPCONF - a local map whose archive is gone is dead weight. Derived
# from the records, so a map survives exactly as long as the backup it describes.
backup_map_prune() {
	local _dir="$1" _conf="$2" _f _name
	[ -d "$_dir" ] || return 0
	for _f in "$_dir"/*.map.zst; do
		[ -f "$_f" ] || continue
		_name=$(basename "$_f" .map.zst)
		# Literal and anchored - the name holds dots, and grep would read them as a pattern.
		sed -n "s/^BACKUP='\([^']*\)'.*/\1/p" "$_conf" 2> /dev/null | grep -qxF -- "$_name" || rm -f "$_f"
	done
}

# ── Differential members (#712) ──────────────────────────────────────────────────────────────────
#
# The map is always the FULL one: a diff without a complete map cannot express a deletion. Members
# are built whole, measured, then rebuilt as diffs - decide after building, never by guessing.
# RS="\0" record walking is verified on mawk (deb12) as well as gawk.
BACKUP_MAP_FIELDS=5

# backup_map_changed BASEMAP CURMAP PREFIX - new or differing in-member paths, NUL-list. Compared
# over the WHOLE record: hash-only would restore the old mode over a chmod.
backup_map_changed() {
	awk -v base="$1" -v pre="$3|" '
		BEGIN { RS = "\0"; ORS = "" }
		{
			i = (FNR - 1) % 5
			if (i == 0) p = $0
			else if (i == 1) h = $0
			else if (i == 2) m = $0
			else if (i == 3) o = $0
			else {
				v = h "\x01" m "\x01" o "\x01" $0
				if (FILENAME == base) { B[p] = v; BH[p] = h; next }
				if (index(p, pre) != 1) next
				inpath = substr(p, length(pre) + 1)
				# "-" is changed even against itself - a twice-raced file must not read as covered.
				if (!(p in B) || B[p] != v || h == "-" || BH[p] == "-") print inpath "\0"
			}
		}' "$1" "$2"
}

# backup_map_keep BASEMAP CURMAP PREFIX SKIPLIST - first-pass list: paths in both maps minus what
# the diff carries. A deleted path is in neither list and never written - that IS the deletion.
# The subtraction is an economy: a slip-through gets overwritten by the diff pass.
backup_map_keep() {
	awk -v base="$1" -v pre="$3|" -v skip="$4" '
		BEGIN {
			# Skip list BEFORE RS changes: getline honours RS, at NUL the listing becomes one key.
			if (skip != "") { while ((getline line < skip) > 0) S[line] = 1 }
			RS = "\0"; ORS = ""
		}
		{
			i = (FNR - 1) % 5
			if (i == 0) p = $0
			else if (i > 0 && i < 4) next
			else {
				if (FILENAME == base) { B[p] = 1; next }
				if (!(p in B)) next
				if (index(p, pre) != 1) next
				inpath = substr(p, length(pre) + 1)
				if (inpath in S) next
				print inpath "\0"
			}
		}' "$1" "$2"
}

# backup_base_reachable NAME - can a diff against NAME be restored from somewhere this box can
# reach? A local copy answers it (either allowed place) and costs no remote round trip; without
# one, a configured remote's FRESH listing has to show the file - the record's word alone is not
# enough, or a hand-cleaned target would collect diffs against a base that exists nowhere (the
# C5 class, one level up). Each target's conf is sourced inside a SUBSHELL with the connection
# keys blanked first: neither the caller nor the next target inherits HOST/USERNAME/PASSWORD/
# BPATH/PORT/PRIVATEKEY, and a conf missing a key cannot read the previous target's value.
backup_base_reachable() {
	local _n="$1" _t
	backup_archive_path "$user" "$_n" && return 0
	for _t in $(echo -e "${BACKUP_SYSTEM//,/\\n}"); do
		case "$_t" in
			ftp | sftp | rclone) ;;
			*) continue ;;
		esac
		[ -f "$HESTIA/conf/$_t.backup.conf" ] || continue
		if (
			HOST='' USERNAME='' PASSWORD='' BPATH='' PORT='' PRIVATEKEY=''
			source_conf "$HESTIA/conf/$_t.backup.conf"
			if [ -z "$PORT" ]; then
				if [ "$_t" = 'ftp' ]; then PORT='21'; else PORT='22'; fi
			fi
			remote_file_present "$_t" "$_n"
		); then
			return 0
		fi
	done
	return 1
}

# backup_diff_base BACKUPCONF MAPDIR - the newest usable base: listed, not adopted, present, local
# map readable. A run that finds none writes a full archive, never a diff against nothing.
backup_diff_base() {
	local _conf="$1" _dir="$2" _name
	[ -f "$_conf" ] || return 1
	local _line
	while read -r _name; do
		[ -n "$_name" ] || continue
		# -F: the name holds dots, grep must not read it as a pattern (same lesson as #765).
		_line=$(grep -F "BACKUP='$_name'" "$_conf" 2> /dev/null | head -1)
		case "$_line" in *"ADOPTED='yes'"*) continue ;; esac
		# Only a FULL archive is a base - no chains.
		case "$_line" in *"MODE='diff'"*) continue ;; esac
		# Map first - a local file test - so the remote listing below runs only for a real
		# candidate. The map is what the diff is BUILT from; the archive itself is needed at
		# restore time and may live on a remote only (the remote-only mode, #790 stage 3).
		[ -s "$_dir/$_name.map.zst" ] || continue
		backup_base_reachable "$_name" || continue
		echo "$_name"
		return 0
	done < <(sed -n "s/^BACKUP='\([^']*\)'.*/\1/p" "$_conf" | sort -r)
	return 1
}

# Per-member threshold: a diff that saves less than this is not worth the dependency on a base.
BACKUP_DIFF_MEMBER_PCT=50

# backup_diff_build TMPDIR BASEMAP CURMAP BASE - rebuild what is worth rebuilding, record what each
# member ended up as. Rebuilt FROM the full member, never from the live tree.
backup_diff_build() {
	local _tmp="$1" _bm="$2" _cur="$3" _base="$4"
	local _d _pre _arc _out _opt _list _work _sz_full _sz_diff _kind _basehits
	local -a _codec
	: > "$_tmp/$BACKUP_CONTAINER/backup.members"
	for _d in "$_tmp"/web/*/ "$_tmp"/mail/*/; do
		[ -d "$_d" ] || continue
		case "$_d" in
			*/web/*) _pre="web/$(basename "$_d")" ;;
			*/mail/*) _pre="mail/$(basename "$_d")" ;;
			*) continue ;;
		esac
		_arc=$(ls "$_d"domain_data.tar.* "$_d"accounts.tar.* 2> /dev/null | head -1)
		[ -n "$_arc" ] || continue
		_kind='full'

		# A member the base never had: a diff of it is the full member plus a dependency.
		_basehits=$(backup_map_prefix_count "$_bm" "$_pre")
		if [ "$_basehits" -gt 0 ]; then
			_list=$(mktemp)
			backup_map_changed "$_bm" "$_cur" "$_pre" > "$_list"
			_work=$(mktemp -d)
			_opt=$(backup_map_taropt "$_arc")
			# An ARRAY, not a string: a caller's IFS decides how a string splits, and this one has to
			# work whatever it is set to.
			case "$_arc" in
				*.zst) _codec=(pzstd -q "-$BACKUP_GZIP" -) ;;
				*) _codec=(gzip -n "-$BACKUP_GZIP" -) ;;
			esac
			# shellcheck disable=SC2086
			tar $_opt -xpf "$_arc" -C "$_work" --null -T "$_list" > /dev/null 2>&1
			# --no-recursion BEFORE -T (positional!) - after -T a changed directory drags its
			# whole unchanged content along.
			tar --sort=name -cpf- -C "$_work" --no-recursion --null -T "$_list" 2> /dev/null \
				| "${_codec[@]}" > "$_arc.diff" 2> /dev/null
			_sz_full=$(stat -c %s "$_arc" 2> /dev/null || echo 0)
			_sz_diff=$(stat -c %s "$_arc.diff" 2> /dev/null || echo 0)
			# An empty diff is the normal quiet case; only a ZERO-BYTE file means the build failed.
			if [ "$_sz_diff" -gt 0 ] && [ $((_sz_diff * 100)) -lt $((_sz_full * BACKUP_DIFF_MEMBER_PCT)) ]; then
				mv -f "$_arc.diff" "$_arc"
				_kind='diff'
			else
				rm -f "$_arc.diff"
			fi
			rm -rf "$_work" "$_list"
		fi
		echo "$_pre=$_kind" >> "$_tmp/$BACKUP_CONTAINER/backup.members"
	done
	# MAPHASH = "the base I was built against"; a same-named archive from elsewhere fails it.
	printf "BASE='%s' MAPHASH='%s'\n" "$_base" "$(sha256sum "$_bm" | cut -d' ' -f1)" \
		> "$_tmp/$BACKUP_CONTAINER/backup.base"
}

# backup_map_prefix_count MAPFILE PREFIX - how many entries a member has in a map.
backup_map_prefix_count() {
	awk -v pre="$2|" 'BEGIN { RS = "\0" } (FNR - 1) % 5 == 0 && index($0, pre) == 1 { n++ } END { print n + 0 }' "$1"
}

# ── Reading a differential archive back ──────────────────────────────────────────────────────────
#
# A diff archive carries its full outer structure; only diffable member CONTENT is short. Listing,
# probe, report and preflight never need the base - it is fetched for the extraction alone.

# backup_diff_probe ARCHIVE WORKDIR - sets DIFF_BASE when the archive is one. Everything else is
# decided from the files it drops in WORKDIR, so a caller never has to be told what it is holding.
backup_diff_probe() {
	local _arc="$1" _wd="$2"
	DIFF_BASE=''
	mkdir -p "$_wd" || return 1
	# All three unconditionally: without backup.base the members file is what lets the caller
	# refuse instead of unpacking diff members as whole.
	tar -xOf "$_arc" "./$BACKUP_CONTAINER/backup.base" > "$_wd/backup.base" 2> /dev/null || true
	tar -xOf "$_arc" "./$BACKUP_CONTAINER/backup.members" > "$_wd/backup.members" 2> /dev/null || true
	tar -xOf "$_arc" "./$BACKUP_CONTAINER/backup.map" > "$_wd/backup.map" 2> /dev/null || true
	[ -s "$_wd/backup.base" ] || return 0
	DIFF_BASE=$(sed -n "s/.*BASE='\([^']*\)'.*/\1/p" "$_wd/backup.base")
}

# backup_member_needs_base MEMBERSFILE PREFIX - anything not explicitly "full" needs the base:
# a diff treated as whole looks complete and is not; the reverse costs one pointless base read.
backup_member_needs_base() {
	grep -qxF "$2=full" "$1" 2> /dev/null && return 1
	return 0
}

# backup_diff_stage_base BASEARCHIVE PREFIX MEMBERNAME WORKDIR - put the base's copy of one member
# next to the diff and print its path.
backup_diff_stage_base() {
	local _base="$1" _pre="$2" _member="$3" _wd="$4"
	mkdir -p "$_wd/base" || return 1
	tar -xf "$_base" -C "$_wd/base" "./$_pre" > /dev/null 2>&1 || return 1
	[ -f "$_wd/base/$_pre/$_member" ] || return 1
	echo "$_wd/base/$_pre/$_member"
}

# backup_diff_keep_list BASEARCHIVE CURMAP PREFIX DIFFMEMBER OUT - what the first pass writes; the
# diff's own paths are subtracted, deleted paths are in neither map and never written.
backup_diff_keep_list() {
	local _base="$1" _cur="$2" _pre="$3" _member="$4" _out="$5" _bm _skip _opt
	_bm=$(mktemp) || return 1
	_skip=$(mktemp) || return 1
	tar -xOf "$_base" "./$BACKUP_CONTAINER/backup.map" > "$_bm" 2> /dev/null
	if [ ! -s "$_bm" ]; then
		rm -f "$_bm" "$_skip"
		return 1
	fi
	_opt=$(backup_map_taropt "$_member")
	# literal quoting: an escaped backslash would never match the NUL-clean maps - double work only.
	# shellcheck disable=SC2086
	tar $_opt -tf "$_member" --quoting-style=literal > "$_skip" 2> /dev/null
	backup_map_keep "$_bm" "$_cur" "$_pre" "$_skip" > "$_out"
	rm -f "$_bm" "$_skip"
}

# ── Set rotation (#712) ──────────────────────────────────────────────────────────────────────────
#
# The unit is the SET: one full plus the diffs naming it. "Taking a full takes its diffs" is the
# wrong way round - measured, it collapsed four archives into one in a single run.
backup_set_removals() {
	local _conf="$1" _target="$2" _base="${3:-}"
	# TARGET counts SETS (full-only: every archive is its own set, the old count). The incoming
	# archive is not in the records yet: a diff extends the set of _base (kept explicitly), a new
	# full founds its own, so the existing list keeps one set less - without this, BACKUPS='1'
	# deleted its own base seconds before the diff against it (measured). One level deep only,
	# which carries because backup_diff_base restricts bases to FULL archives.
	# LC_ALL=C: byte order on every awk; the quote arrives via -v q, never as an escape.
	LC_ALL=C awk -v conf="$_conf" -v target="$_target" -v inbase="$_base" -v q="'" '
		function field(l, k,   i, r) {
			i = index(l, k q)
			if (i == 0) return ""
			r = substr(l, i + length(k) + 1)
			i = index(r, q)
			if (i == 0) return ""
			return substr(r, 1, i - 1)
		}
		BEGIN {
			while ((getline l < conf) > 0) {
				n = field(l, "BACKUP=")
				if (n == "") continue
				b = field(l, "BASE=")
				setid[n] = (b == "" ? n : b)
			}
			close(conf)
			if (inbase == "") target = target - 1
			if (target < 0) target = 0
		}
		NF {
			names[++c] = $0
			id = ($0 in setid) ? setid[$0] : $0
			ids[$0] = id
			if (!(id in seen)) { seen[id] = 1; sets[++s] = id }
		}
		END {
			# newest sets first - the timestamp in the archive name sorts chronologically
			for (i = 1; i <= s; i++)
				for (j = i + 1; j <= s; j++)
					if (sets[j] > sets[i]) { t = sets[i]; sets[i] = sets[j]; sets[j] = t }
			for (i = 1; i <= target && i <= s; i++) keep[sets[i]] = 1
			if (inbase != "") keep[inbase] = 1
			for (i = 1; i <= c; i++)
				if (!(ids[names[i]] in keep)) print names[i]
		}'
}
