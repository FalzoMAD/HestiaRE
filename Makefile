# ======================================================== #
#
# HestiaRE Makefile
# Drives the full system install; also handles updates.
#
# Usage:
#   make install OS=debian-bookworm [PROFILE=standard]
#   make install OS=debian-bookworm H_HOSTNAME=host.example.com \
#                H_ADMIN=admin H_EMAIL=admin@host H_PASS=secret
#   make update
#   make check-updates
#   make status
#
# ======================================================== #

.ONESHELL:
SHELL        := /bin/bash
.SHELLFLAGS  := -euo pipefail -c

HESTIA           := /usr/local/hestia
CONF_DIR         := /etc/hestia
INSTALL_CONF     := $(CONF_DIR)/install.conf
SOURCE_CONF      := $(CONF_DIR)/source.conf
LOG              := /var/log/hestia/install.log
VERSION          := $(shell cat $(HESTIA)/VERSION 2>/dev/null || cat VERSION 2>/dev/null || echo "dev")

# Install profile and OS (set by install.sh or caller)
OS               ?= unknown
PROFILE          ?= standard

# Optional non-interactive overrides (skip interactive prompts)
H_HOSTNAME       ?=
H_ADMIN          ?=
H_EMAIL          ?=
H_PASS           ?=

# Component version pins (keep in sync with install/upgrade/upgrade.conf)
MARIADB_VER      := 11.8
PHP_VER          := 8.3
PMA_VER          := 5.2.3
MULTIPHP_VER     := 5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3 8.4 8.5

HESTIA_INSTALL_DIR := $(HESTIA)/install/deb
HESTIA_COMMON_DIR  := $(HESTIA)/install/common

# Update channel config (written by install.sh --dev)
-include $(SOURCE_CONF)

HESTIARE_SOURCE   ?= github
HESTIARE_REPO_URL ?= https://github.com/FalzoMAD/HestiaRE
HESTIARE_TOKEN    ?=
HESTIARE_CHANNEL  ?= stable

GITHUB_REPO  := FalzoMAD/HestiaRE
GITHUB_API   := https://api.github.com/repos/$(GITHUB_REPO)
GITHUB_RAW   := https://github.com/$(GITHUB_REPO)/releases/download

# OS-specific settings
ifeq ($(OS),debian-bookworm)
  OS_ID    := debian
  CODENAME := bookworm
  RELEASE  := 12
  EXIM_USR := Debian-exim
else ifeq ($(OS),ubuntu-noble)
  OS_ID    := ubuntu
  CODENAME := noble
  RELEASE  := 24
  EXIM_USR := Debian-exim
endif

ARCH := $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

.PHONY: install install-base install-panel install-web install-db install-mail \
        install-security install-tools \
        _check-root _collect-params _configure-hestia _finalize \
        _profile-standard _profile-minimal \
        update check-updates _do-update status backup uninstall

# -------------------------------------------------------- #
# install — main entry point
# -------------------------------------------------------- #

install:
	@echo "========================================================================"
	echo " HestiaRE $(VERSION)"
	echo " OS:      $(OS)"
	echo " Profile: $(PROFILE)"
	echo "========================================================================"
	echo ""
	$(MAKE) _check-root
	$(MAKE) _collect-params H_HOSTNAME="$(H_HOSTNAME)" H_ADMIN="$(H_ADMIN)" H_EMAIL="$(H_EMAIL)" H_PASS="$(H_PASS)"
	$(MAKE) install-base
	$(MAKE) install-panel
	$(MAKE) install-web
	$(MAKE) install-db
	$(MAKE) _profile-$(PROFILE)
	$(MAKE) install-security
	$(MAKE) install-tools
	$(MAKE) _configure-hestia
	$(MAKE) _finalize

_profile-standard:
	@$(MAKE) install-mail

_profile-minimal:
	@echo "[ * ] Minimal profile — skipping mail stack"

# -------------------------------------------------------- #
# _check-root
# -------------------------------------------------------- #

_check-root:
	@[ "$${EUID:-$$(id -u)}" -eq 0 ] || { echo "ERROR: Must run as root."; exit 1; }
	[ "$(OS)" != "unknown" ] || { echo "ERROR: OS not specified. Use: make install OS=debian-bookworm"; exit 1; }
	if [ -f "$(HESTIA)/conf/hestia.conf" ]; then \
	    echo "ERROR: HestiaRE already installed. Remove $(HESTIA)/conf/hestia.conf to reinstall."; \
	    exit 1; \
	fi

# -------------------------------------------------------- #
# _collect-params — prompt for missing install values
# -------------------------------------------------------- #

_collect-params:
	@mkdir -p "$(CONF_DIR)"
	chmod 700 "$(CONF_DIR)"
	HNAME="$(H_HOSTNAME)"
	HADMIN="$(H_ADMIN)"
	HEMAIL="$(H_EMAIL)"
	HPASS="$(H_PASS)"
	if [ -z "$$HNAME" ]; then \
	    DEFAULT=$$(hostname --fqdn 2>/dev/null || echo "server.example.com"); \
	    read -rp "Hostname [$$DEFAULT]: " input; \
	    HNAME="$${input:-$$DEFAULT}"; \
	fi
	if [ -z "$$HADMIN" ]; then \
	    read -rp "Admin username [admin]: " input; \
	    HADMIN="$${input:-admin}"; \
	fi
	if [ -z "$$HEMAIL" ]; then \
	    read -rp "Admin email [admin@$$HNAME]: " input; \
	    HEMAIL="$${input:-admin@$$HNAME}"; \
	fi
	if [ -z "$$HPASS" ]; then \
	    HPASS=$$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16); \
	fi
	cat > "$(INSTALL_CONF)" << HEREDOC
HESTIA_HOSTNAME="$$HNAME"
HESTIA_ADMIN="$$HADMIN"
HESTIA_EMAIL="$$HEMAIL"
HESTIA_PASS="$$HPASS"
HESTIA_OS="$(OS)"
HESTIA_PROFILE="$(PROFILE)"
HEREDOC
	chmod 600 "$(INSTALL_CONF)"
	echo "[ * ] Install parameters saved to $(INSTALL_CONF)"

# -------------------------------------------------------- #
# install-base — repos, OS packages, users, dirs
# -------------------------------------------------------- #

install-base:
	@echo "[ * ] Configuring APT..."
	[ -f /etc/apt/apt.conf.d/80-retries ] || echo 'APT::Acquire::Retries "3";' > /etc/apt/apt.conf.d/80-retries
	echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/90nolang
	mkdir -p /root/.gnupg && chmod 700 /root/.gnupg
	echo ""
	echo "[ * ] Adding package repositories..."
	echo "deb [arch=$(ARCH) signed-by=/usr/share/keyrings/nginx-keyring.gpg] \
	https://nginx.org/packages/mainline/$(OS_ID)/ $(CODENAME) nginx" \
	> /etc/apt/sources.list.d/nginx.list
	curl -fsSL https://nginx.org/keys/nginx_signing.key \
	    | gpg --dearmor | tee /usr/share/keyrings/nginx-keyring.gpg > /dev/null
	echo "deb [arch=$(ARCH) signed-by=/usr/share/keyrings/sury-keyring.gpg] \
	https://packages.sury.org/php/ $(CODENAME) main" \
	> /etc/apt/sources.list.d/php.list
	curl -fsSL https://packages.sury.org/php/apt.gpg \
	    | gpg --dearmor | tee /usr/share/keyrings/sury-keyring.gpg > /dev/null
	echo "deb [arch=$(ARCH) signed-by=/usr/share/keyrings/mariadb-keyring.gpg] \
	https://dlm.mariadb.com/repo/mariadb-server/$(MARIADB_VER)/repo/$(OS_ID) $(CODENAME) main" \
	> /etc/apt/sources.list.d/mariadb.list
	curl -fsSL https://mariadb.org/mariadb_release_signing_key.asc \
	    | gpg --dearmor | tee /usr/share/keyrings/mariadb-keyring.gpg > /dev/null
	echo ""
	echo "[ * ] Updating package lists..."
	apt-get -qq update
	echo "[ * ] Installing base packages..."
	DEBIAN_FRONTEND=noninteractive apt-get -y install \
	    acl at bc bsdmainutils bsdutils ca-certificates \
	    cron curl dnsutils e2fslibs e2fsprogs expect flex ftp \
	    git gnupg idn2 imagemagick ipset iptables jq \
	    lsb-release lsof mc net-tools openssh-server quota \
	    rrdtool rsyslog sysstat unzip util-linux vim-common \
	    wget whois xxd zip zstd bubblewrap restic sudo \
	    apt-transport-https awstats >> $(LOG)
	echo ""
	echo "[ * ] Creating system users..."
	if ! id hestiaweb &>/dev/null; then \
	    useradd hestiaweb -c "HestiaRE Web" --no-create-home -s /sbin/nologin; \
	fi
	if ! id hestiamail &>/dev/null; then \
	    useradd hestiamail -c "HestiaRE Mail" --no-create-home -s /sbin/nologin; \
	fi
	if ! getent group hestia-users &>/dev/null; then \
	    groupadd hestia-users; \
	fi
	usermod -aG hestia-users hestiaweb
	usermod -aG hestia-users hestiamail
	echo "[ * ] Configuring SSH..."
	if grep -qiE "^#?.*Subsystem.+(sftp )?sftp-server" /etc/ssh/sshd_config; then \
	    sed -i -E "s/^#?.*Subsystem.+(sftp )?sftp-server/Subsystem sftp internal-sftp/g" /etc/ssh/sshd_config; \
	fi
	sed -i 's/[#]LoginGraceTime [[:digit:]]m/LoginGraceTime 1m/g' /etc/ssh/sshd_config
	if ! grep -q "^DebianBanner no" /etc/ssh/sshd_config; then \
	    echo 'DebianBanner no' >> /etc/ssh/sshd_config; \
	fi
	systemctl restart ssh
	echo "[ * ] Configuring NTP..."
	if [ -f /etc/systemd/timesyncd.conf ]; then \
	    sed -i 's/#NTP=/NTP=pool.ntp.org/' /etc/systemd/timesyncd.conf; \
	    systemctl enable systemd-timesyncd; \
	    systemctl start systemd-timesyncd; \
	fi
	grep -q '^/sbin/nologin' /etc/shells || echo "/sbin/nologin" >> /etc/shells
	grep -q '^/usr/sbin/nologin' /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells
	echo "[ * ] Configuring directory color..."
	grep -q 'LS_COLORS="$$LS_COLORS:di=00;33"' /etc/profile \
	    || echo 'LS_COLORS="$$LS_COLORS:di=00;33"' >> /etc/profile
	echo ""
	echo "[ OK ] install-base complete"

# -------------------------------------------------------- #
# install-panel — Caddy + hestia-php.service
# -------------------------------------------------------- #

install-panel:
	@echo "[ * ] Installing panel packages (Caddy, PHP $(PHP_VER) FPM)..."
	DEBIAN_FRONTEND=noninteractive apt-get -y install \
	    caddy \
	    php$(PHP_VER)-fpm php$(PHP_VER)-mysql php$(PHP_VER)-curl \
	    php$(PHP_VER)-zip php$(PHP_VER)-gmp php$(PHP_VER)-mbstring \
	    php$(PHP_VER)-opcache >> $(LOG)
	echo "[ * ] Configuring panel PHP-FPM..."
	mkdir -p /etc/php/hestia/fpm/pool.d
	cp -f $(HESTIA)/install/panel-php/php-fpm.conf /etc/php/hestia/fpm/
	cp -f $(HESTIA)/install/panel-php/pool.d/panel.conf /etc/php/hestia/fpm/pool.d/
	cp -f $(HESTIA)/install/panel-php/hestia-php.service /etc/systemd/system/
	systemctl daemon-reload
	systemctl enable hestia-php
	systemctl start hestia-php
	echo "[ * ] Configuring Caddy..."
	mkdir -p /etc/caddy
	cp -f $(HESTIA)/install/panel-caddy/Caddyfile /etc/caddy/Caddyfile
	cp -f $(HESTIA)/install/panel-caddy/hestia.conf /etc/caddy/hestia.conf
	systemctl enable caddy
	systemctl start caddy
	echo ""
	echo "[ OK ] install-panel complete"

# -------------------------------------------------------- #
# install-web — nginx, PHP multi, web templates
# -------------------------------------------------------- #

install-web:
	@echo "[ * ] Installing web packages (nginx, PHP $(PHP_VER) extensions)..."
	DEBIAN_FRONTEND=noninteractive apt-get -y install \
	    nginx \
	    php$(PHP_VER) php$(PHP_VER)-apcu php$(PHP_VER)-bz2 php$(PHP_VER)-cgi \
	    php$(PHP_VER)-cli php$(PHP_VER)-common php$(PHP_VER)-gd \
	    php$(PHP_VER)-imagick php$(PHP_VER)-imap php$(PHP_VER)-intl \
	    php$(PHP_VER)-ldap php$(PHP_VER)-pgsql php$(PHP_VER)-pspell \
	    php$(PHP_VER)-readline php$(PHP_VER)-xml >> $(LOG)
	echo "[ * ] Configuring nginx..."
	rm -f /etc/nginx/conf.d/*.conf
	cp -f $(HESTIA_INSTALL_DIR)/nginx/nginx.conf /etc/nginx/
	cp -f $(HESTIA_INSTALL_DIR)/nginx/status.conf /etc/nginx/conf.d/
	cp -f $(HESTIA_INSTALL_DIR)/nginx/0rtt-anti-replay.conf /etc/nginx/conf.d/
	cp -f $(HESTIA_INSTALL_DIR)/nginx/agents.conf /etc/nginx/conf.d/
	cp -f $(HESTIA_INSTALL_DIR)/nginx/cloudflare.inc /etc/nginx/conf.d/
	cp -f $(HESTIA_INSTALL_DIR)/nginx/phpmyadmin.inc /etc/nginx/conf.d/
	cp -f $(HESTIA_INSTALL_DIR)/logrotate/nginx /etc/logrotate.d/
	mkdir -p /etc/nginx/conf.d/domains /etc/nginx/conf.d/main \
	         /etc/nginx/modules-enabled /var/log/nginx/domains
	for ns in $$(grep -is '^nameserver' /etc/resolv.conf | awk '{print $$2}' | tr '\n' ' '); do \
	    if echo "$$ns" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$$'; then \
	        resolver="$${resolver:-} $$ns"; \
	    fi; \
	done; \
	resolver=$${resolver# }; \
	[ -n "$$resolver" ] && sed -i "s/1.0.0.1 8.8.4.4 1.1.1.1 8.8.8.8/$$resolver/g" /etc/nginx/nginx.conf || true
	cf_ips=$$(curl -fsLm5 --retry 2 https://api.cloudflare.com/client/v4/ips 2>/dev/null || echo ""); \
	if [ -n "$$cf_ips" ] && [ "$$(echo "$$cf_ips" | jq -r '.success//""')" = "true" ]; then \
	    cf_inc="/etc/nginx/conf.d/cloudflare.inc"; \
	    echo "# Cloudflare IP Ranges" > $$cf_inc; \
	    echo "" >> $$cf_inc; \
	    echo "# IPv4" >> $$cf_inc; \
	    for ip in $$(echo "$$cf_ips" | jq -r '.result.ipv4_cidrs[]//""' | sort); do \
	        echo "set_real_ip_from $$ip;" >> $$cf_inc; \
	    done; \
	    echo "" >> $$cf_inc; \
	    echo "# IPv6" >> $$cf_inc; \
	    for ip in $$(echo "$$cf_ips" | jq -r '.result.ipv6_cidrs[]//""' | sort); do \
	        echo "set_real_ip_from $$ip;" >> $$cf_inc; \
	    done; \
	    echo "" >> $$cf_inc; \
	    echo "real_ip_header CF-Connecting-IP;" >> $$cf_inc; \
	    echo "[ * ] Cloudflare IP ranges updated"; \
	fi
	update-rc.d nginx defaults > /dev/null 2>&1
	systemctl start nginx
	echo "[ * ] Installing PHP multi versions..."
	for v in $(MULTIPHP_VER); do \
	    echo "  php$$v..."; \
	    $(HESTIA)/bin/h-add-web-php "$$v" > /dev/null 2>&1 || true; \
	done
	echo "[ * ] Configuring PHP $(PHP_VER) web pool..."
	cp -f $(HESTIA_INSTALL_DIR)/php-fpm/www.conf /etc/php/$(PHP_VER)/fpm/pool.d/www.conf
	update-rc.d php$(PHP_VER)-fpm defaults > /dev/null 2>&1
	systemctl start php$(PHP_VER)-fpm
	update-alternatives --set php /usr/bin/php$(PHP_VER) > /dev/null 2>&1 || true
	echo "[ * ] Configuring PHP settings (timezone, short_open_tag)..."
	ZONE=$$(timedatectl 2>/dev/null | awk '/Timezone/{print $$2}'); \
	ZONE=$${ZONE:-UTC}; \
	for pconf in $$(find /etc/php -name php.ini 2>/dev/null); do \
	    sed -i "s%;date.timezone =%date.timezone = $$ZONE%g" "$$pconf"; \
	    sed -i 's%_open_tag = Off%_open_tag = On%g' "$$pconf"; \
	done
	printf '#!/bin/sh\nfind -O3 /home/*/tmp/ -ignore_readdir_race -depth -mindepth 1 -name '"'"'sess_*'"'"' -type f -cmin '"'"'+10080'"'"' -delete > /dev/null 2>&1\nfind -O3 $(HESTIA)/data/sessions/ -ignore_readdir_race -depth -mindepth 1 -name '"'"'sess_*'"'"' -type f -cmin '"'"'+10080'"'"' -delete > /dev/null 2>&1\n' > /etc/cron.daily/php-session-cleanup
	chmod 755 /etc/cron.daily/php-session-cleanup
	mkdir -p /var/www/html /var/www/document_errors
	cp -rf $(HESTIA_COMMON_DIR)/templates/web/unassigned/index.html /var/www/html/
	cp -rf $(HESTIA_COMMON_DIR)/templates/web/skel/document_errors/* /var/www/document_errors/
	cp -f $(HESTIA_INSTALL_DIR)/logrotate/httpd-prerotate/* /etc/logrotate.d/httpd-prerotate/ 2>/dev/null || true
	rm -f /etc/cron.d/awstats
	echo ""
	echo "[ OK ] install-web complete"

# -------------------------------------------------------- #
# install-db — MariaDB + phpMyAdmin
# -------------------------------------------------------- #

install-db:
	@echo "[ * ] Installing database packages (MariaDB $(MARIADB_VER))..."
	DEBIAN_FRONTEND=noninteractive apt-get -y install \
	    mariadb-client mariadb-common mariadb-server >> $(LOG)
	echo "[ * ] Configuring MariaDB..."
	MEM=$$(awk '/MemTotal/{print $$2}' /proc/meminfo); \
	if   [ "$$MEM" -gt 3900000 ]; then MYCNF="my-large.cnf"; \
	elif [ "$$MEM" -gt 1200000 ]; then MYCNF="my-medium.cnf"; \
	else                               MYCNF="my-small.cnf"; fi; \
	rm -f /etc/mysql/my.cnf; \
	cp -f $(HESTIA_INSTALL_DIR)/mysql/$$MYCNF /etc/mysql/my.cnf; \
	sed -i 's|/usr/share/mysql|/usr/share/mariadb|g' /etc/mysql/my.cnf
	mariadb-install-db >> $(LOG) 2>&1
	update-rc.d mariadb defaults > /dev/null 2>&1
	systemctl -q enable mariadb
	systemctl start mariadb
	echo "[ * ] Securing MariaDB installation..."
	MPASS=$$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
	printf '[client]\npassword='"'"'%s'"'"'\n' "$$MPASS" > /root/.my.cnf
	chmod 600 /root/.my.cnf
	mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$$MPASS'; FLUSH PRIVILEGES;"
	mariadb -e "UPDATE mysql.global_priv SET priv=json_set(priv, '$.password_last_changed', UNIX_TIMESTAMP(), '$.plugin', 'mysql_native_password', '$.authentication_string', 'invalid', '$.auth_or', json_array(json_object(), json_object('plugin', 'unix_socket'))) WHERE User='root';"
	mariadb -e "DELETE FROM mysql.global_priv WHERE User='';"
	mariadb -e "DROP DATABASE IF EXISTS test;"
	mariadb -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
	mariadb -e "FLUSH PRIVILEGES;"
	grep -q 'HESTIA_MPASS' "$(INSTALL_CONF)" \
	    || echo "HESTIA_MPASS=\"$$MPASS\"" >> "$(INSTALL_CONF)"
	echo "[ * ] Installing phpMyAdmin v$(PMA_VER)..."
	cd /tmp
	wget -q --retry-connrefused \
	    https://files.phpmyadmin.net/phpMyAdmin/$(PMA_VER)/phpMyAdmin-$(PMA_VER)-all-languages.tar.gz
	tar xzf phpMyAdmin-$(PMA_VER)-all-languages.tar.gz
	mkdir -p /usr/share/phpmyadmin /etc/phpmyadmin /etc/phpmyadmin/conf.d \
	         /usr/share/phpmyadmin/tmp /var/lib/phpmyadmin/tmp
	cp -rf phpMyAdmin-$(PMA_VER)-all-languages/* /usr/share/phpmyadmin/
	cp -f $(HESTIA_INSTALL_DIR)/phpmyadmin/config.inc.php /etc/phpmyadmin/
	sed -i "s|'configFile' => ROOT_PATH . 'config.inc.php',|'configFile' => '/etc/phpmyadmin/config.inc.php',|g" \
	    /usr/share/phpmyadmin/libraries/vendor_config.php 2>/dev/null || true
	BLOWFISH=$$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
	sed -i "s|%blowfish_secret%|$$BLOWFISH|" /etc/phpmyadmin/config.inc.php
	chown -R hestiamail:www-data /usr/share/phpmyadmin/tmp/
	chmod 770 /var/lib/phpmyadmin/tmp
	chown -R root:hestiamail /etc/phpmyadmin/
	chmod 640 /etc/phpmyadmin/config.inc.php
	chmod 750 /etc/phpmyadmin/conf.d/
	source $(HESTIA_INSTALL_DIR)/phpmyadmin/pma.sh > /dev/null 2>&1 || true
	rm -rf phpMyAdmin-$(PMA_VER)-all-languages phpMyAdmin-$(PMA_VER)-all-languages.tar.gz
	echo ""
	echo "[ OK ] install-db complete"

# -------------------------------------------------------- #
# install-mail — exim4, dovecot, rspamd, roundcube
# -------------------------------------------------------- #

install-mail:
	@echo "[ * ] Installing mail packages (exim4, dovecot, rspamd)..."
	DEBIAN_FRONTEND=noninteractive apt-get -y install \
	    exim4 exim4-daemon-heavy \
	    dovecot-imapd dovecot-pop3d dovecot-managesieved dovecot-sieve \
	    rspamd libmail-dkim-perl >> $(LOG)
	echo "[ * ] Configuring Exim4..."
	gpasswd -a $(EXIM_USR) mail > /dev/null 2>&1 || true
	EXIM_VER=$$(exim4 --version 2>/dev/null | head -1 | awk '{print $$3}' | cut -f-2 -d. || echo "4.96")
	cp -f $(HESTIA_INSTALL_DIR)/exim/exim4.conf.template /etc/exim4/ 2>/dev/null \
	    || cp -f $(HESTIA_INSTALL_DIR)/exim/exim4.conf.4.95.template /etc/exim4/exim4.conf.template
	cp -f $(HESTIA_INSTALL_DIR)/exim/dnsbl.conf /etc/exim4/
	cp -f $(HESTIA_INSTALL_DIR)/exim/spam-blocks.conf /etc/exim4/
	cp -f $(HESTIA_INSTALL_DIR)/exim/limit.conf /etc/exim4/
	cp -f $(HESTIA_INSTALL_DIR)/exim/system.filter /etc/exim4/
	touch /etc/exim4/white-blocks.conf
	SRS=$$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
	echo "$$SRS" > /etc/exim4/srs.conf
	chmod 640 /etc/exim4/srs.conf
	chown root:$(EXIM_USR) /etc/exim4/srs.conf
	chmod 640 /etc/exim4/exim4.conf.template
	rm -rf /etc/exim4/domains && mkdir -p /etc/exim4/domains
	rm -f /etc/alternatives/mta
	ln -s /usr/sbin/exim4 /etc/alternatives/mta
	update-rc.d -f sendmail remove > /dev/null 2>&1 || true
	update-rc.d -f postfix remove > /dev/null 2>&1 || true
	update-rc.d exim4 defaults
	systemctl start exim4
	echo "[ * ] Configuring Dovecot..."
	gpasswd -a dovecot mail > /dev/null 2>&1 || true
	mkdir -p /etc/dovecot/conf.d
	DOVECOT_VER=$$(dovecot --version 2>/dev/null | cut -f-2 -d. || echo "2.3")
	if [ "$$DOVECOT_VER" = "2.4" ]; then \
	    cp -f $(HESTIA_COMMON_DIR)/dovecot-24/dovecot.conf /etc/dovecot/; \
	    cp -f $(HESTIA_COMMON_DIR)/dovecot-24/conf.d/* /etc/dovecot/conf.d/; \
	else \
	    cp -f $(HESTIA_COMMON_DIR)/dovecot/dovecot.conf /etc/dovecot/; \
	    cp -f $(HESTIA_COMMON_DIR)/dovecot/conf.d/* /etc/dovecot/conf.d/; \
	    rm -f /etc/dovecot/conf.d/15-mailboxes.conf; \
	fi
	cp -f $(HESTIA_INSTALL_DIR)/logrotate/dovecot /etc/logrotate.d/
	chown -R root:root /etc/dovecot*
	touch /var/log/dovecot.log
	chown dovecot:mail /var/log/dovecot.log
	chmod 660 /var/log/dovecot.log
	update-rc.d dovecot defaults
	systemctl start dovecot
	echo "[ * ] Configuring rspamd..."
	if [ -d "$(HESTIA_INSTALL_DIR)/rspamd" ]; then \
	    mkdir -p /etc/rspamd/local.d; \
	    cp -rf $(HESTIA_INSTALL_DIR)/rspamd/* /etc/rspamd/local.d/ 2>/dev/null || true; \
	fi
	systemctl enable rspamd
	systemctl start rspamd
	echo "[ * ] Installing Roundcube..."
	$(HESTIA)/bin/h-add-sys-roundcube quiet 2>/dev/null || \
	    DEBIAN_FRONTEND=noninteractive apt-get -y install roundcube roundcube-mysql roundcube-plugins >> $(LOG)
	echo ""
	echo "[ OK ] install-mail complete"

# -------------------------------------------------------- #
# install-security — fail2ban, iptables, ipset
# -------------------------------------------------------- #

install-security:
	@echo "[ * ] Installing security packages (fail2ban, iptables, ipset)..."
	DEBIAN_FRONTEND=noninteractive apt-get -y install \
	    fail2ban iptables ipset >> $(LOG)
	echo "[ * ] Configuring fail2ban..."
	cp -rf $(HESTIA_INSTALL_DIR)/fail2ban /etc/
	if [ -f /etc/fail2ban/jail.d/defaults-debian.conf ]; then \
	    rm -f /etc/fail2ban/jail.d/defaults-debian.conf; \
	fi
	if [ ! -e /var/log/auth.log ]; then \
	    touch /var/log/auth.log; \
	    chmod 640 /var/log/auth.log; \
	    chown root:adm /var/log/auth.log; \
	fi
	update-rc.d fail2ban defaults
	systemctl start fail2ban
	echo ""
	echo "[ OK ] install-security complete"

# -------------------------------------------------------- #
# install-tools — composer, wp-cli, rclone, restic, fm
# -------------------------------------------------------- #

install-tools:
	@echo "[ * ] Installing PHP dependencies (composer, wp-cli)..."
	$(HESTIA)/bin/h-add-sys-dependencies quiet 2>/dev/null || echo "  (h-add-sys-dependencies not available yet)"
	echo "[ * ] Installing File Manager..."
	$(HESTIA)/bin/h-add-sys-filemanager quiet 2>/dev/null || echo "  (h-add-sys-filemanager not available yet)"
	echo "[ * ] Installing rclone..."
	curl -fsSL https://rclone.org/install.sh | bash > /dev/null 2>&1 || true
	echo "[ * ] Updating restic..."
	restic self-update > /dev/null 2>&1 || true
	echo ""
	echo "[ OK ] install-tools complete"

# -------------------------------------------------------- #
# _configure-hestia — hestia.conf, admin user, SSL, crons
# -------------------------------------------------------- #

_configure-hestia:
	@source "$(INSTALL_CONF)"
	echo "[ * ] Configuring Hestia Control Panel..."
	mkdir -p /etc/sudoers.d
	cp -f $(HESTIA_COMMON_DIR)/sudo/hestiaweb /etc/sudoers.d/
	chmod 440 /etc/sudoers.d/hestiaweb
	if [ ! -e /etc/hestia/hestia.conf ]; then \
	    printf '# Do not edit this file, will get overwritten on next upgrade, use /etc/hestia/local.conf instead\n\nexport HESTIA='"'"'/usr/local/hestia'"'"'\n\n[[ -f /etc/hestia/local.conf ]] && source /etc/hestia/local.conf\n' > /etc/hestia/hestia.conf; \
	fi
	printf 'export HESTIA='"'"'%s'"'"'\nPATH=$$PATH:%s/bin\nexport PATH\n' \
	    "$(HESTIA)" "$(HESTIA)" > /etc/profile.d/hestia.sh
	chmod 755 /etc/profile.d/hestia.sh
	source /etc/profile.d/hestia.sh
	cp -f $(HESTIA_INSTALL_DIR)/logrotate/hestia /etc/logrotate.d/hestia 2>/dev/null || true
	rm -f /var/log/hestia
	mkdir -p /var/log/hestia
	ln -sf /var/log/hestia $(HESTIA)/log
	mkdir -p $(HESTIA)/conf $(HESTIA)/ssl \
	         $(HESTIA)/data/ips $(HESTIA)/data/queue \
	         $(HESTIA)/data/users $(HESTIA)/data/firewall \
	         $(HESTIA)/data/sessions
	touch $(HESTIA)/data/queue/backup.pipe $(HESTIA)/data/queue/disk.pipe \
	      $(HESTIA)/data/queue/webstats.pipe $(HESTIA)/data/queue/restart.pipe \
	      $(HESTIA)/data/queue/traffic.pipe $(HESTIA)/data/queue/daily.pipe \
	      $(HESTIA)/log/system.log $(HESTIA)/log/auth.log $(HESTIA)/log/backup.log
	chmod 750 $(HESTIA)/conf $(HESTIA)/data/users $(HESTIA)/data/ips $(HESTIA)/log
	chmod -R 750 $(HESTIA)/data/queue
	chmod 660 /var/log/hestia/*
	chmod 770 $(HESTIA)/data/sessions
	echo "[ * ] Creating v-* symlinks..."
	for hcmd in $(HESTIA)/bin/h-*; do \
	    vcmd="$(HESTIA)/bin/v-$${hcmd##*/h-}"; \
	    [ -L "$$vcmd" ] || ln -s "$$(basename "$$hcmd")" "$$vcmd"; \
	done
	echo "[ * ] Generating hestia.conf..."
	rm -f $(HESTIA)/conf/hestia.conf
	touch $(HESTIA)/conf/hestia.conf
	chmod 660 $(HESTIA)/conf/hestia.conf
	wcv() { echo "$$1='$$2'" >> $(HESTIA)/conf/hestia.conf; }
	wcv "BACKEND_PORT"               "8083"
	wcv "WEB_SYSTEM"                 "nginx"
	wcv "WEB_PORT"                   "80"
	wcv "WEB_SSL_PORT"               "443"
	wcv "WEB_SSL"                    "openssl"
	wcv "PROXY_SYSTEM"               ""
	wcv "STATS_SYSTEM"               "awstats"
	wcv "WEB_BACKEND"                "php-fpm"
	wcv "DB_SYSTEM"                  "mysql"
	wcv "DB_PMA_ALIAS"               "phpmyadmin"
	if [ "$(PROFILE)" = "standard" ]; then \
	    wcv "MAIL_SYSTEM"            "exim4"; \
	    wcv "IMAP_SYSTEM"            "dovecot"; \
	    wcv "ANTISPAM_SYSTEM"        "rspamd"; \
	    wcv "SIEVE_SYSTEM"           "yes"; \
	fi
	wcv "CRON_SYSTEM"                "cron"
	wcv "FIREWALL_SYSTEM"            "iptables"
	wcv "FIREWALL_EXTENSION"         "fail2ban"
	wcv "DISK_QUOTA"                 "no"
	wcv "RESOURCES_LIMIT"            "no"
	wcv "BACKUP_SYSTEM"              "local"
	wcv "BACKUP_GZIP"                "4"
	wcv "BACKUP_MODE"                "zstd"
	wcv "LANGUAGE"                   "en"
	wcv "LOGIN_STYLE"                "default"
	wcv "THEME"                      "dark"
	wcv "INACTIVE_SESSION_TIMEOUT"   "60"
	wcv "VERSION"                    "$(VERSION)"
	wcv "RELEASE_BRANCH"             "release"
	wcv "UPGRADE_SEND_EMAIL"         "true"
	wcv "UPGRADE_SEND_EMAIL_LOG"     "false"
	wcv "API"                        "no"
	wcv "API_SYSTEM"                 "0"
	wcv "API_ALLOWED_IP"             ""
	wcv "ROOT_USER"                  "$$HESTIA_ADMIN"
	echo "[ * ] Installing packages, templates, firewall data..."
	cp -rf $(HESTIA_COMMON_DIR)/packages $(HESTIA)/data/
	IFS='.' read -r -a dom <<< "$$HESTIA_HOSTNAME"; \
	if [ -n "$${dom[-2]:-}" ] && [ -n "$${dom[-1]:-}" ]; then \
	    SERVERDOMAIN="$${dom[-2]}.$${dom[-1]}"; \
	    sed -i "s/domain.tld/$$SERVERDOMAIN/g" $(HESTIA)/data/packages/*.pkg 2>/dev/null || true; \
	fi
	cp -rf $(HESTIA_INSTALL_DIR)/templates $(HESTIA)/data/
	cp -rf $(HESTIA_COMMON_DIR)/templates/web/ $(HESTIA)/data/templates
	cp -rf $(HESTIA_COMMON_DIR)/templates/dns/ $(HESTIA)/data/templates
	cp -rf $(HESTIA_COMMON_DIR)/firewall $(HESTIA)/data/
	rm -f $(HESTIA)/data/firewall/ipset/blacklist.sh \
	      $(HESTIA)/data/firewall/ipset/blacklist.ipv6.sh
	if [ "$(PROFILE)" != "standard" ]; then \
	    sed -i "/COMMENT='SMTP'/d" $(HESTIA)/data/firewall/rules.conf 2>/dev/null || true; \
	    sed -i "/COMMENT='IMAP'/d" $(HESTIA)/data/firewall/rules.conf 2>/dev/null || true; \
	    sed -i "/COMMENT='POP3'/d" $(HESTIA)/data/firewall/rules.conf 2>/dev/null || true; \
	fi
	sed -i "/COMMENT='FTP'/d"  $(HESTIA)/data/firewall/rules.conf 2>/dev/null || true
	sed -i "/COMMENT='DNS'/d"  $(HESTIA)/data/firewall/rules.conf 2>/dev/null || true
	cp -rf $(HESTIA_COMMON_DIR)/api $(HESTIA)/data/
	echo "[ * ] Configuring hostname..."
	$(HESTIA)/bin/h-change-sys-hostname "$$HESTIA_HOSTNAME" > /dev/null 2>&1 || true
	echo "[ * ] Configuring OpenSSL TLS ciphers..."
	TLS13="TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384"; \
	if ! grep -qw "^ssl_conf = ssl_sect$$" /etc/ssl/openssl.cnf 2>/dev/null; then \
	    sed -i '/providers = provider_sect$$/a ssl_conf = ssl_sect' /etc/ssl/openssl.cnf; \
	fi; \
	if ! grep -qw "^\[ssl_sect\]$$" /etc/ssl/openssl.cnf 2>/dev/null; then \
	    printf '\n[ssl_sect]\nsystem_default = hestia_openssl_sect\n\n[hestia_openssl_sect]\nCiphersuites = %s\nOptions = PrioritizeChaCha\n' "$$TLS13" >> /etc/ssl/openssl.cnf; \
	fi
	echo "[ * ] Generating SSL certificate..."
	$(HESTIA)/bin/h-generate-ssl-cert "$$(hostname)" '' 'US' 'California' \
	    'San Francisco' 'HestiaRE' 'IT' > /tmp/hst.pem
	CRT_END=$$(grep -n "END CERTIFICATE-" /tmp/hst.pem | head -n1 | cut -f1 -d:)
	KEY_START=$$(grep -nE "BEGIN (RSA |EC |ENCRYPTED )?PRIVATE KEY" /tmp/hst.pem | head -n1 | cut -f1 -d:)
	KEY_END=$$(grep -nE "END (RSA |EC |ENCRYPTED )?PRIVATE KEY" /tmp/hst.pem | head -n1 | cut -f1 -d:)
	if [ -z "$$KEY_START" ]; then \
	    KEY_START=$$(grep -n "BEGIN RSA" /tmp/hst.pem | head -n1 | cut -f1 -d:); \
	    KEY_END=$$(grep -n "END RSA" /tmp/hst.pem | head -n1 | cut -f1 -d:); \
	fi
	cd $(HESTIA)/ssl
	sed -n "1,$${CRT_END}p" /tmp/hst.pem > certificate.crt
	sed -n "$${KEY_START},$${KEY_END}p" /tmp/hst.pem > certificate.key
	chown root:mail $(HESTIA)/ssl/*
	chmod 660 $(HESTIA)/ssl/*
	rm -f /tmp/hst.pem
	cp -f $(HESTIA_INSTALL_DIR)/ssl/dhparam.pem /etc/ssl/ 2>/dev/null || true
	echo "[ * ] Enabling SFTP and SSH jails..."
	$(HESTIA)/bin/h-add-sys-sftp-jail > /dev/null 2>&1
	$(HESTIA)/bin/h-add-sys-ssh-jail > /dev/null 2>&1
	echo "[ * ] Creating admin user..."
	$(HESTIA)/bin/h-add-user "$$HESTIA_ADMIN" "$$HESTIA_PASS" "$$HESTIA_EMAIL" "default" "System Administrator"
	$(HESTIA)/bin/h-change-user-shell "$$HESTIA_ADMIN" nologin
	$(HESTIA)/bin/h-change-user-role "$$HESTIA_ADMIN" admin
	$(HESTIA)/bin/h-change-user-language "$$HESTIA_ADMIN" en
	$(HESTIA)/bin/h-change-sys-config-value 'POLICY_SYSTEM_PROTECTED_ADMIN' 'yes'
	echo "[ * ] Registering MariaDB host..."
	if [ -f /root/.my.cnf ]; then \
	    source "$(INSTALL_CONF)"; \
	    $(HESTIA)/bin/h-add-database-host mysql localhost root "$$HESTIA_MPASS" > /dev/null 2>&1; \
	fi
	$(HESTIA)/bin/h-change-sys-db-alias 'pma' 'phpmyadmin' > /dev/null 2>&1 || true
	echo "[ * ] Configuring system IP..."
	$(HESTIA)/bin/h-update-sys-ip > /dev/null 2>&1
	DEFAULT_NIC="$$(ip -d -j route show | jq -r '.[] | if .dst == "default" then .dev else empty end' | head -n1)"
	IP="$$(ip -4 -d -j addr show "$$DEFAULT_NIC" 2>/dev/null \
	    | jq -r '.[] | .addr_info[] | if .scope == "global" then .local else empty end' 2>/dev/null \
	    | head -n1 || hostname -I | awk '{print $$1}')"
	PUB_IP="$$(curl -fsLm5 --retry 2 --ipv4 https://ip.hestiacp.com/ 2>/dev/null || echo "")"
	if [ -n "$$PUB_IP" ] && [ "$$PUB_IP" != "$$IP" ]; then \
	    [ -e /etc/rc.local ] && sed -i '/exit 0/d' /etc/rc.local || touch /etc/rc.local; \
	    grep -q '^#!' /etc/rc.local || echo '#!/bin/sh' >> /etc/rc.local; \
	    echo "$(HESTIA)/bin/h-update-sys-ip" >> /etc/rc.local; \
	    echo "exit 0" >> /etc/rc.local; \
	    chmod +x /etc/rc.local; \
	    systemctl enable rc-local > /dev/null 2>&1; \
	    $(HESTIA)/bin/h-change-sys-ip-nat "$$IP" "$$PUB_IP" > /dev/null 2>&1; \
	    IP="$$PUB_IP"; \
	fi
	if [ "$(PROFILE)" = "standard" ]; then \
	    $(HESTIA)/bin/h-update-firewall; \
	fi
	echo "[ * ] Adding default domain..."
	$(HESTIA)/bin/h-add-web-domain "$$HESTIA_ADMIN" "$$HESTIA_HOSTNAME" "$$IP"
	echo "[ * ] Creating hestiaweb crontab..."
	MIN=$$(tr -dc '012345' < /dev/urandom | head -c 2)
	HOUR=$$(tr -dc '1234567' < /dev/urandom | head -c 1)
	mkdir -p /var/spool/cron/crontabs
	cat > /var/spool/cron/crontabs/hestiaweb << CRONTAB
MAILTO=""
CONTENT_TYPE="text/plain; charset=utf-8"
*/2 * * * * sudo $(HESTIA)/bin/h-update-sys-queue restart
10 00 * * * sudo $(HESTIA)/bin/h-update-sys-queue daily
15 02 * * * sudo $(HESTIA)/bin/h-update-sys-queue disk
10 00 * * * sudo $(HESTIA)/bin/h-update-sys-queue traffic
30 03 * * * sudo $(HESTIA)/bin/h-update-sys-queue webstats
*/5 * * * * sudo $(HESTIA)/bin/h-update-sys-queue backup
10 05 * * * sudo $(HESTIA)/bin/h-backup-users
20 00 * * * sudo $(HESTIA)/bin/h-update-user-stats
*/5 * * * * sudo $(HESTIA)/bin/h-update-sys-rrd
$$MIN $$HOUR * * * sudo $(HESTIA)/bin/h-update-letsencrypt-ssl
41 4 * * * sudo $(HESTIA)/bin/h-update-sys-hestia-all
CRONTAB
	chmod 600 /var/spool/cron/crontabs/hestiaweb
	chown hestiaweb:hestiaweb /var/spool/cron/crontabs/hestiaweb
	$(HESTIA)/bin/h-add-cron-hestia-autoupdate apt > /dev/null 2>&1 || true
	echo "[ * ] Building initial RRD graphs..."
	$(HESTIA)/bin/h-update-sys-rrd > /dev/null 2>&1 || true
	$(HESTIA)/bin/h-change-sys-port 8083 > /dev/null 2>&1 || true
	$(HESTIA)/bin/h-update-sys-defaults > /dev/null 2>&1 || true
	BIN="$(HESTIA)/bin"
	source $(HESTIA)/func/syshealth.sh 2>/dev/null \
	    && syshealth_repair_system_config 2>/dev/null || true
	[ -f /root/.bashrc ] && grep -q 'hestia.sh' /root/.bashrc || \
	    printf 'if [ "$${PATH#*/usr/local/hestia/bin*}" = "$$PATH" ]; then\n    . /etc/profile.d/hestia.sh\nfi\n' >> /root/.bashrc
	echo ""
	echo "[ OK ] _configure-hestia complete"

# -------------------------------------------------------- #
# _finalize — start hestia.service, final upgrade, summary
# -------------------------------------------------------- #

_finalize:
	@source "$(INSTALL_CONF)"
	echo "[ * ] Starting Hestia service..."
	update-rc.d hestia defaults
	systemctl start hestia
	chown hestiaweb:hestiaweb $(HESTIA)/data/sessions
	mkdir -p /backup && chmod 755 /backup
	echo "[ * ] Scheduling Let's Encrypt host certificate..."
	echo "@reboot root sleep 10 && rm /etc/cron.d/hestia-ssl && PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:' && $(HESTIA)/bin/h-add-letsencrypt-host" \
	    > /etc/cron.d/hestia-ssl
	echo "[ * ] Final package upgrade..."
	apt-get -qq update
	DEBIAN_FRONTEND=noninteractive apt-get -y upgrade >> $(LOG) 2>&1
	HOST_IP=$$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{print $$7; exit}' || hostname -I | awk '{print $$1}')
	echo ""
	echo "========================================================================"
	echo " HestiaRE installation complete!"
	echo "========================================================================"
	echo ""
	echo "  Panel URL:  https://$$HESTIA_HOSTNAME:8083"
	echo "  Backup URL: https://$$HOST_IP:8083"
	echo ""
	echo "  Username:   $$HESTIA_ADMIN"
	echo "  Password:   $$HESTIA_PASS"
	echo ""
	echo "  Install log: $(LOG)"
	echo ""
	echo "  IMPORTANT: Reboot the server to complete the installation."
	echo ""

# -------------------------------------------------------- #
# update
# -------------------------------------------------------- #

update: check-updates
	@echo "Downloading update..."
	$(MAKE) _do-update

_do-update:
	@if [ "$(HESTIARE_SOURCE)" = "gitea" ]; then \
		AUTH=""; \
		if [ -n "$(HESTIARE_TOKEN)" ]; then AUTH="-H \"Authorization: token $(HESTIARE_TOKEN)\""; fi; \
		LATEST=$$(curl -fsSL $$AUTH "$(HESTIARE_REPO_URL)/releases/latest" \
			| grep '"tag_name"' | cut -d'"' -f4); \
		URL="$(HESTIARE_REPO_URL)/releases/download/$$LATEST/hestiare-$$LATEST.tar.gz"; \
	else \
		if [ "$(HESTIARE_CHANNEL)" = "prerelease" ]; then \
			LATEST=$$(curl -fsSL "$(GITHUB_API)/releases" \
				| grep '"tag_name"' | head -n1 | cut -d'"' -f4); \
		else \
			LATEST=$$(curl -fsSL "$(GITHUB_API)/releases/latest" \
				| grep '"tag_name"' | cut -d'"' -f4); \
		fi; \
		URL="$(GITHUB_RAW)/$$LATEST/hestiare-$$LATEST.tar.gz"; \
	fi; \
	echo "Version: $$LATEST"; \
	curl -fsSL "$$URL" -o /tmp/hestiare-update.tar.gz; \
	tar -xzf /tmp/hestiare-update.tar.gz -C /tmp; \
	rm /tmp/hestiare-update.tar.gz; \
	cp -r /tmp/hestiare-$$LATEST/. $(HESTIA)/; \
	rm -rf /tmp/hestiare-$$LATEST; \
	cd $(HESTIA) && $(MAKE) install OS="$(OS)" PROFILE="$(PROFILE)"; \
	echo "Update complete."

# -------------------------------------------------------- #
# check-updates
# -------------------------------------------------------- #

check-updates:
	@echo "Checking for updates..."
	if [ "$(HESTIARE_SOURCE)" = "gitea" ]; then \
		AUTH=""; \
		if [ -n "$(HESTIARE_TOKEN)" ]; then AUTH="-H \"Authorization: token $(HESTIARE_TOKEN)\""; fi; \
		LATEST=$$(curl -fsSL $$AUTH "$(HESTIARE_REPO_URL)/releases/latest" \
			| grep '"tag_name"' | cut -d'"' -f4); \
	else \
		LATEST=$$(curl -fsSL "$(GITHUB_API)/releases/latest" \
			| grep '"tag_name"' | cut -d'"' -f4); \
	fi; \
	echo "Installed: $(VERSION)"; \
	echo "Available: $$LATEST"; \
	if [ "$$LATEST" = "v$(VERSION)" ] || [ "$$LATEST" = "$(VERSION)" ]; then \
		echo "Already up to date."; \
	else \
		echo "Update available: $$LATEST"; \
	fi

# -------------------------------------------------------- #
# status
# -------------------------------------------------------- #

status:
	@echo "HestiaRE $(VERSION)"
	echo "Source:   $(HESTIARE_SOURCE)"
	echo "Channel:  $(HESTIARE_CHANNEL)"
	echo "OS:       $(OS)"
	echo "Profile:  $(PROFILE)"

# -------------------------------------------------------- #
# backup / uninstall (stubs)
# -------------------------------------------------------- #

backup:
	@echo "HestiaRE — backup placeholder"

uninstall:
	@echo "========================================================================"
	echo " HestiaRE Uninstall"
	echo "========================================================================"
	echo ""
	read -p "This will remove HestiaRE. Are you sure? [y/N] " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
	    echo "Aborted."; \
	    exit 1; \
	fi
	echo "Uninstall placeholder — nothing removed yet."
	echo ""
	echo "Done."
