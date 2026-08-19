#!/bin/bash

#===========================================================================#
#                                                                           #
# Hestia Control Panel - Backup Function Library                            #
#                                                                           #
#===========================================================================#

#===========================================================================#
#                     Archived record lines (#705)                          #
#===========================================================================#
#
# The restore takes the record line out of the archive and edits it AS TEXT, rather than parsing
# it and emitting a fresh one from a list of known keys. That list was the defect: a field it did
# not know about - the domain's AUTH_USER/AUTH_HASH among them - simply did not come back, and
# syshealth then re-inserted the key EMPTY, so the record looked healthy afterwards.
#
# In place and not re-emitted, because the field ORDER is load-bearing: include/botpolicy.sh reads
# with `sed -n "s/^DOMAIN='\([^']*\)'.*BOTLIMIT='[^']\+.*/\1/p"`, so DOMAIN has to stay first and
# BOTLIMIT behind it. A re-emit would also silently normalise whatever the parser does not model.
#
# Known limit, and the same one every `grep -F "DOMAIN='$domain'"` in the tree already has: a value
# containing a literal ' is not representable. record_line_valid rejects such a line rather than
# letting it through half-parsed.

# Is this line exactly a sequence of KEY='VALUE', separated by single spaces?
#
# This gate is what makes the verbatim path safe, and it is not optional. Appending the archived
# line means a line this box did not write lands in a live *.conf, and the consumers downstream do
# NOT all go through the (sound) PHP tokenizer: botpolicy and crowdsec read it with sed on quote
# boundaries, get_object_value with grep/cut, and the h-list-* emitters splice it into JSON.
#
# $ stays ALLOWED: MD5, AUTH_HASH and STATS_CRYPT are crypt hashes and carry it as a matter of
# course. Inside a single-quoted record value it is literal, and no consumer evaluates it.
#
# It is also what lets record_set_field find a field by a plain " KEY='" search: with ' banned from
# every value, that sequence cannot occur inside one.
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
		# A repeated key is refused, because the readers disagree about which one wins: the
		# tokenizer's eval keeps the LAST assignment, sed and grep -o take the FIRST match, and
		# record_set_field rewrites the first occurrence only. One line, two truths - and the
		# difference is invisible in the panel, which is what makes it worth refusing outright.
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
		# No separator in front of the first field: on an empty record the space would produce a
		# leading blank, which record_line_valid refuses - the two helpers would disagree about
		# what a valid line is. Not reachable from the restore, which always starts from a record
		# that already passed the gate, but a helper should not be able to build what the gate
		# next to it rejects.
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

# restore_parse_record KEYVAR LINE - parse a record into the environment and remember, in KEYVAR,
# which keys it set.
#
# The cleanup between two objects has to be derived from whatever LAST parsed, at EVERY parse site
# in the loop. Maintaining it on only one branch is the same defect one level up: it reads as
# complete and silently covers less the moment another branch parses a record - and the db loop
# does exactly that for a database that already exists on the target.
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

#===========================================================================#
#                        Reading an archive (#707)                          #
#===========================================================================#
#
# The restore used to find out what an archive holds while it was already writing, and what it
# could not do it did not say at all: a dns/ member was ignored in silence, and a whole section was
# skipped without a word when this box has no such subsystem - after which the run reported success.
#
# So: read the archive ONCE, up front, and describe it. backup_probe collects what is IN the
# archive; backup_report compares that against THIS host and says what will be lost. Two functions
# because the first is about the file alone and is the same everywhere, while the second only makes
# sense against a particular box.
#
# Everything is derived from the archive and from this host's own state - nothing is a list kept in
# step by hand. That is the whole point: a list is what made the restore lose fields in the first
# place.

# backup_probe ARCHIVE WORKDIR - describe an archive. Sets PROBE_* and extracts the record members
# into WORKDIR, so the caller can read them without unpacking the archive again.
backup_probe() {
	local _arc="$1" _wd="$2" _members _dir

	PROBE_CONTAINER='hestia'
	PROBE_MODE='gzip'
	PROBE_WEB='' PROBE_MAIL='' PROBE_DB='' PROBE_UDIR='' PROBE_DNS=''
	PROBE_CRON='no' PROBE_PACKAGES='' PROBE_WEB_SYSTEM='' PROBE_PROXY_SYSTEM=''
	PROBE_ORIGIN='' PROBE_RECORDS="$_wd"

	[ -f "$_arc" ] || return 1
	_members=$(tar -tf "$_arc" 2> /dev/null) || return 1
	[ -n "$_members" ] || return 1

	# Feature detection, never a marker: a HestiaCP archive and every HestiaRE archive written so far
	# carry no origin line at all, so anything that keyed on one would be deciding by its absence.
	grep -qx './vesta/' <<< "$_members" || grep -qx './vesta' <<< "$_members" && PROBE_CONTAINER='vesta'
	grep -qx './.zstd' <<< "$_members" && PROBE_MODE='zstd'

	# Object names come from the member paths, one pass per subsystem rather than one tar per
	# object: the archive is compressed, and per-object extraction would walk it N times.
	#
	# One name per LINE, never space separated: a home entry can be called "my documents", and a
	# register that splits on spaces is exactly what made the restore abort on one (#706).
	PROBE_WEB=$(sed -n 's|^\./web/\([^/]*\)/'"$PROBE_CONTAINER"'/web\.conf$|\1|p' <<< "$_members" | sort -u)
	PROBE_MAIL=$(sed -n 's|^\./mail/\([^/]*\)/'"$PROBE_CONTAINER"'/mail\.conf$|\1|p' <<< "$_members" | sort -u)
	PROBE_DB=$(sed -n 's|^\./db/\([^/]*\)/'"$PROBE_CONTAINER"'/db\.conf$|\1|p' <<< "$_members" | sort -u)
	# Two expressions, not one alternation: | is the delimiter here, so \| inside the pattern is an
	# escaped delimiter and matched nothing at all - the list came back empty and the report would
	# have said the archive carries no home entries. Greedy \(.*\) on purpose, so a name with a dot
	# of its own survives: a real archive carried geekbench_claim.url.tar.zst.
	PROBE_UDIR=$(sed -n -e 's|^\./user_dir/\(.*\)\.tar\.gz$|\1|p' -e 's|^\./user_dir/\(.*\)\.tar\.zst$|\1|p' \
		<<< "$_members" | sort -u)
	# dns/ is the one we never write and never restore. Zones by NAME, because for somebody moving
	# off HestiaCP the count is not the answer to the question they are actually asking.
	PROBE_DNS=$(sed -n 's|^\./dns/\([^/]*\)/.*|\1|p' <<< "$_members" | sort -u)
	grep -qx "\./cron/cron\.conf" <<< "$_members" && PROBE_CRON='yes'
	PROBE_PACKAGES=$(sed -n "s|^\./$PROBE_CONTAINER/packages/\(.*\)\.pkg$|\1|p" <<< "$_members" | sort -u)

	# One extraction for every record member there is. --wildcards needs the pattern quoted, and a
	# pattern that matches nothing is not an error here: an archive without a mail section is a fact
	# to report, not a failure to read.
	mkdir -p "$_wd" || return 1
	tar -xf "$_arc" -C "$_wd" --wildcards --no-wildcards-match-slash \
		"./$PROBE_CONTAINER/user.conf" "./$PROBE_CONTAINER/web-system" "./$PROBE_CONTAINER/origin" \
		2> /dev/null || true
	tar -xf "$_arc" -C "$_wd" --wildcards \
		"./$PROBE_CONTAINER/packages/*" "./web/*/$PROBE_CONTAINER/web.conf" \
		"./mail/*/$PROBE_CONTAINER/mail.conf" "./db/*/$PROBE_CONTAINER/db.conf" \
		"./cron/cron.conf" 2> /dev/null || true

	_dir="$_wd/$PROBE_CONTAINER"
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
	[ -n "$1" ] || { echo 0; return; }
	grep -c . <<< "$1"
}

# Keys this host itself can put into a KIND record. Three sources, all derived, because each alone
# shrinks in a way that would make the report lie:
#
#   - the registry, which is behind reality by design (CROWDSEC and BOTLIMIT are not in it yet)
#   - the live records on this box, which only show what some customer HAPPENS to use right now -
#     on a box where no domain has a bot limit, BOTLIMIT would read as a foreign field
#   - the keys the commands themselves can add, which is the only source that does not depend on
#     the current population
#
# PHP_PROFILE is named as archive-only rather than unknown: it exists in an archive and never in a
# live record (#591), and the restore drops it on purpose - the one place that says so is the remap
# table in h-restore-user, and this is the second.
backup_local_keys() {
	local _kind="$1" _f
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

# backup_report - what this host will NOT be able to restore from the probed archive.
#
# Every line is derived: from the archive, from this host's config, and from the record keys both
# sides actually use. An empty report is PRINTED, never left as silence - "nothing falls away" and
# "the probe read nothing" have to be distinguishable, and they were not before.
backup_report() {
	local _found=0 _n _obj _rec _keys _unknown _tpl _eff _ver _missing _pkg _local _hostkeys

	echo "-- ARCHIVE --"
	printf '   container %s, %s compressed\n' "$PROBE_CONTAINER" "$PROBE_MODE"
	# "home entries", not directories: h-backup-user walks `ls -a` of the home, so the archive holds
	# plain files too - a real HestiaCP archive listed .bashrc, .profile and geekbench_claim.url
	# next to the directories.
	printf '   objects: %s web, %s mail, %s database, %s home entr%s, cron %s\n' \
		"$(backup_report_count "$PROBE_WEB")" "$(backup_report_count "$PROBE_MAIL")" \
		"$(backup_report_count "$PROBE_DB")" "$(backup_report_count "$PROBE_UDIR")" \
		"$([ "$(backup_report_count "$PROBE_UDIR")" = 1 ] && echo y || echo ies)" "$PROBE_CRON"
	if [ -n "$PROBE_ORIGIN" ]; then
		printf '   origin: %s\n' "$PROBE_ORIGIN"
	else
		printf '   origin: not stated - recognised by its contents\n'
	fi

	echo "-- WHAT THIS HOST CANNOT RESTORE --"

	# DNS is the one the migration case asks about, so the zones are named rather than counted.
	if [ -n "$PROBE_DNS" ]; then
		_found=1
		printf '   %s DNS zone(s), which this host does not serve at all (#58) - the records are in\n' \
			"$(backup_report_count "$PROBE_DNS")"
		printf '   the archive and stay there, nothing here reads them:\n'
		sed 's/^/      /' <<< "$PROBE_DNS"
	fi

	# A section whose subsystem this host does not have is dropped in full. With the object count,
	# because "mail is skipped" and "your 40 mail domains are skipped" are different sentences.
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

	[ "$_found" -eq 0 ] && printf '   nothing - every object in this archive has a home on this host\n'

	echo "-- WHAT WILL BE REWRITTEN --"
	_found=0

	# The web model decides how the vhosts are rendered; a different one on the archive side means
	# custom includes may not apply. This is the #120 banner, moved to before the first write.
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

	# Templates and PHP versions, per web record. accept_web_template is asked, not re-implemented -
	# a second copy of the mapping table is a second thing to keep in step.
	_missing=''
	while IFS= read -r _obj; do
		[ -n "$_obj" ] || continue
		_rec=$(head -n1 "$(backup_record_file web "$_obj")" 2> /dev/null) || continue
		[ -n "$_rec" ] || continue
		for _n in TPL:web PROXY:proxy; do
			_tpl=$(sed -n "s/.*[[:space:]]${_n%%:*}='\([^']*\)'.*/\1/p" <<< " $_rec")
			[ -n "$_tpl" ] || continue
			read -r _eff _ < <(accept_web_template "${_n#*:}" "$_tpl" 2> /dev/null)
			[ "$_eff" = "$_tpl" ] && continue
			_found=1
			printf '   %s: %s template %s -> %s\n' "$_obj" "${_n#*:}" "$_tpl" "$_eff"
		done
		_ver=$(sed -n "s/.*PHP_VERSION='\([^']*\)'.*/\1/p" <<< "$_rec")
		[ -z "$_ver" ] && _ver=$(sed -n "s/.*BACKEND='PHP-\([0-9]*\)_\([0-9]*\)'.*/\1.\2/p" <<< "$_rec")
		{ [ -z "$_ver" ] || [ "$_ver" = 'none' ]; } && continue
		[[ " $($BIN/h-list-sys-php plain 2> /dev/null | tr '\n' ' ') " == *" $_ver "* ]] || _missing="$_missing $_ver"
	done <<< "$PROBE_WEB"
	if [ -n "$_missing" ]; then
		_found=1
		printf '   PHP %s is not installed here - those domains would move to the default (%s)\n' \
			"$(tr ' ' '\n' <<< "$_missing" | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ $//')" \
			"$(multiphp_default_version 2> /dev/null)"
	fi

	# Record keys this host neither knows nor writes. Three-way, so our own newer fields do not read
	# as foreign: archived, minus the registry, minus what this box puts in its own records.
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

	# Package limits from a box that has subsystems this one does not (HestiaCP's DNS_DOMAINS and
	# friends). Derived by comparing key sets, so a future divergence shows up without an edit here.
	for _pkg in $PROBE_PACKAGES; do
		[ -f "$PROBE_RECORDS/$PROBE_CONTAINER/packages/$_pkg.pkg" ] || continue
		_local=" $(cat "$CONF_DIR/packages/"*.pkg 2> /dev/null | grep -o "^[A-Z][A-Z0-9_]*=" | tr -d '=' | sort -u | tr '\n' ' ') "
		_unknown=$(grep -o "^[A-Z][A-Z0-9_]*=" "$PROBE_RECORDS/$PROBE_CONTAINER/packages/$_pkg.pkg" | tr -d '=' | sort -u \
			| while IFS= read -r _tpl; do [[ "$_local" == *" $_tpl "* ]] || printf ' %s' "$_tpl"; done)
		if [ -n "$_unknown" ]; then
			_found=1
			printf '   package %s sets limit(s) this host has no subsystem for:%s\n' "$_pkg" "$_unknown"
		fi
	done

	[ "$_found" -eq 0 ] && printf '   nothing - every value comes back exactly as it was archived\n'
	return 0
}

# backup_record_file KIND OBJECT - the extracted record of one object, or nothing.
backup_record_file() {
	case "$1" in
		web) echo "$PROBE_RECORDS/web/$2/$PROBE_CONTAINER/web.conf" ;;
		mail) echo "$PROBE_RECORDS/mail/$2/$PROBE_CONTAINER/mail.conf" ;;
		db) echo "$PROBE_RECORDS/db/$2/$PROBE_CONTAINER/db.conf" ;;
		user) echo "$PROBE_RECORDS/$PROBE_CONTAINER/user.conf" ;;
	esac
}

# Local storage
# Defining local storage function
local_backup() {

	rm -f $BACKUP/$user.$backup_new_date.tar

	# Checking retention
	backup_list=$(ls -lrt $BACKUP/ | awk '{print $9}' | grep -E "^${user}\.[0-9]{4}-.+\.tar$" | sort)
	backups_count=$(echo "$backup_list" | wc -l)
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
		sed -i "/ $user /d" $CONF_DIR/queue/backup.pipe
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
		sed -i "/ $user /d" $CONF_DIR/queue/backup.pipe
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
		sed -i "/ $user /d" $CONF_DIR/queue/backup.pipe
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
		sed -i "/ $user /d" $CONF_DIR/queue/backup.pipe
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
		sed -i "/ $user /d" $CONF_DIR/queue/backup.pipe
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
		sed -i "/ $user /d" $CONF_DIR/queue/backup.pipe
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
		sed -i "/ $user /d" $CONF_DIR/queue/backup.pipe
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
		sed -i "/ $user /d" $CONF_DIR/queue/backup.pipe
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
