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
		_rec_ref="$_rec_ref $_key='$_val'"
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
	echo "$1"
	source_conf "$HESTIA/conf/sftp.backup.conf"
	if [ -z "$PORT" ]; then
		PORT='22'
	fi
	echo $BPATH
	if [ -z $BPATH ]; then
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
