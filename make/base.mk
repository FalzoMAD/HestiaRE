# -------------------------------------------------------- #
# base.mk — APT repos, OS packages, system users,
#           SSH hardening, NTP, /proc restriction
# -------------------------------------------------------- #

.PHONY: _install-base

BASE_PKGS_EXTRA ?=

_install-base:
	@[ ! -f $(CONF_DIR)/.done.base ] || { echo "[ skip ] base already configured"; exit 0; }
	echo "[ * ] Configuring APT..."
	[ -f /etc/apt/apt.conf.d/80-retries ] \
	    || echo 'APT::Acquire::Retries "3";' > /etc/apt/apt.conf.d/80-retries
	echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/90nolang
	mkdir -p /root/.gnupg && chmod 700 /root/.gnupg
	echo "[ * ] Adding nginx mainline repo..."
	printf 'deb [arch=%s signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://nginx.org/packages/mainline/%s/ %s nginx\n' \
	    "$(ARCH)" "$(OS_ID)" "$(CODENAME)" > /etc/apt/sources.list.d/nginx.list
	curl -fsSL https://nginx.org/keys/nginx_signing.key \
	    | gpg --dearmor | tee /usr/share/keyrings/nginx-keyring.gpg > /dev/null
	echo "[ * ] Adding Sury PHP repo..."
	printf 'deb [arch=%s signed-by=/usr/share/keyrings/sury-keyring.gpg] https://packages.sury.org/php/ %s main\n' \
	    "$(ARCH)" "$(CODENAME)" > /etc/apt/sources.list.d/php.list
	curl -fsSL https://packages.sury.org/php/apt.gpg \
	    | gpg --dearmor | tee /usr/share/keyrings/sury-keyring.gpg > /dev/null
	echo "[ * ] Adding MariaDB $(MARIADB_VER) repo..."
	printf 'deb [arch=%s signed-by=/usr/share/keyrings/mariadb-keyring.gpg] https://dlm.mariadb.com/repo/mariadb-server/%s/repo/%s %s main\n' \
	    "$(ARCH)" "$(MARIADB_VER)" "$(OS_ID)" "$(CODENAME)" > /etc/apt/sources.list.d/mariadb.list
	curl -fsSL https://mariadb.org/mariadb_release_signing_key.asc \
	    | gpg --dearmor | tee /usr/share/keyrings/mariadb-keyring.gpg > /dev/null
	echo "[ * ] Installing base packages..."
	apt-get -qq update
	DEBIAN_FRONTEND=noninteractive apt-get -y install \
	    acl at bc bsdmainutils bsdutils ca-certificates \
	    cron curl dnsutils e2fslibs e2fsprogs expect flex ftp \
	    git gnupg idn2 imagemagick ipset iptables jq \
	    lsb-release lsof mc net-tools openssh-server quota \
	    rrdtool rsyslog sysstat unzip util-linux vim-common \
	    wget whois xxd zip zstd bubblewrap restic sudo \
	    apt-transport-https awstats \
	    $(BASE_PKGS_EXTRA) >> $(LOG)
	echo "[ * ] Creating system users..."
	id hestiaweb &>/dev/null \
	    || useradd hestiaweb -c "HestiaRE Web" --no-create-home -s /sbin/nologin
	id hestiamail &>/dev/null \
	    || useradd hestiamail -c "HestiaRE Mail" --no-create-home -s /sbin/nologin
	getent group hestia-users &>/dev/null || groupadd hestia-users
	usermod -aG hestia-users hestiaweb
	usermod -aG hestia-users hestiamail
	echo "[ * ] Hardening SSH..."
	if grep -qiE "^#?.*Subsystem.+(sftp )?sftp-server" /etc/ssh/sshd_config; then \
	    sed -i -E "s/^#?.*Subsystem.+(sftp )?sftp-server/Subsystem sftp internal-sftp/g" \
	        /etc/ssh/sshd_config; \
	fi
	sed -i 's/[#]LoginGraceTime [[:digit:]]m/LoginGraceTime 1m/g' /etc/ssh/sshd_config
	grep -q "^DebianBanner no" /etc/ssh/sshd_config \
	    || echo 'DebianBanner no' >> /etc/ssh/sshd_config
	systemctl restart ssh
	echo "[ * ] Configuring NTP..."
	if [ -f /etc/systemd/timesyncd.conf ]; then \
	    sed -i 's/#NTP=/NTP=pool.ntp.org/' /etc/systemd/timesyncd.conf; \
	    systemctl enable --now systemd-timesyncd; \
	fi
	grep -q '^/sbin/nologin' /etc/shells     || echo "/sbin/nologin" >> /etc/shells
	grep -q '^/usr/sbin/nologin' /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells
	grep -q 'LS_COLORS="$$LS_COLORS:di=00;33"' /etc/profile \
	    || echo 'LS_COLORS="$$LS_COLORS:di=00;33"' >> /etc/profile
	mount -o remount,defaults,hidepid=2 /proc > /dev/null 2>&1 \
	    && echo "@reboot root sleep 5 && mount -o remount,defaults,hidepid=2 /proc" \
	        > /etc/cron.d/hestia-proc \
	    || echo "Info: Cannot remount /proc (LXC — skip hidepid)"
	touch $(CONF_DIR)/.done.base
	echo ""
	echo "[ OK ] install-base complete"
