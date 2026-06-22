# -------------------------------------------------------- #
# configure.mk — pre-flight checks, param collection,
#                hestia.conf generation, admin user, finalize
# -------------------------------------------------------- #

.PHONY: _check-root _collect-params _configure-hestia _finalize

# Sentinel: written by _configure-hestia when fully complete
_DONE_CONFIGURE := $(CONF_DIR)/.done.configure

# -------------------------------------------------------- #
# _check-root — must run as root; block reinstall
# -------------------------------------------------------- #

_check-root:
	@[ "$${EUID:-$$(id -u)}" -eq 0 ] || { echo "ERROR: Must run as root."; exit 1; }
	[ "$(OS)" != "unknown" ] || { echo "ERROR: OS not set. Use: make install OS=debian-bookworm"; exit 1; }
	if [ -f "$(_DONE_CONFIGURE)" ]; then \
	    echo "ERROR: HestiaRE already installed."; \
	    echo "  Delete $(_DONE_CONFIGURE) to force reinstall."; \
	    exit 1; \
	fi

# -------------------------------------------------------- #
# _collect-params — prompt for missing install values
# -------------------------------------------------------- #

_collect-params:
	@mkdir -p "$(CONF_DIR)"
	chmod 700 "$(CONF_DIR)"
	mkdir -p /var/log/hestia
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
	    HPASS=$$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16 || true); \
	fi
	{ \
	    echo "HESTIA_HOSTNAME=\"$$HNAME\""; \
	    echo "HESTIA_ADMIN=\"$$HADMIN\""; \
	    echo "HESTIA_EMAIL=\"$$HEMAIL\""; \
	    echo "HESTIA_PASS=\"$$HPASS\""; \
	    echo "HESTIA_OS=\"$(OS)\""; \
	    echo "HESTIA_PROFILE=\"$(PROFILE)\""; \
	} > "$(INSTALL_CONF)"
	chmod 600 "$(INSTALL_CONF)"
	echo "[ * ] Install parameters saved."

# -------------------------------------------------------- #
# _configure-hestia — hestia.conf, sudoers, SSL cert,
#                     admin user, data dirs, IP, crontab
# -------------------------------------------------------- #

_configure-hestia:
	@source "$(INSTALL_CONF)"
	echo "[ * ] Configuring Hestia Control Panel..."
	mkdir -p /etc/sudoers.d
	cp -f $(HESTIA_COMMON_DIR)/sudo/hestiaweb /etc/sudoers.d/
	chmod 440 /etc/sudoers.d/hestiaweb
	if [ ! -e /etc/hestia/hestia.conf ]; then \
	    printf '# Do not edit — use /etc/hestia/local.conf instead\n\nexport HESTIA='"'"'/usr/local/hestia'"'"'\n\n[[ -f /etc/hestia/local.conf ]] && source /etc/hestia/local.conf\n' \
	        > /etc/hestia/hestia.conf; \
	fi
	printf 'export HESTIA='"'"'%s'"'"'\nPATH=$$PATH:%s/bin\nexport PATH\n' \
	    "$(HESTIA)" "$(HESTIA)" > /etc/profile.d/hestia.sh
	chmod 755 /etc/profile.d/hestia.sh
	source /etc/profile.d/hestia.sh
	cp -f $(HESTIA_INSTALL_DIR)/logrotate/hestia /etc/logrotate.d/hestia 2>/dev/null || true
	[ -L /var/log/hestia ] && rm -f /var/log/hestia || true
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
	echo "[ * ] Writing hestia.conf..."
	rm -f $(HESTIA)/conf/hestia.conf
	touch $(HESTIA)/conf/hestia.conf
	chmod 660 $(HESTIA)/conf/hestia.conf
	wcv() { echo "$$1='$$2'" >> $(HESTIA)/conf/hestia.conf; }
	wcv "BACKEND_PORT"             "8083"
	wcv "WEB_SYSTEM"               "nginx"
	wcv "WEB_PORT"                 "80"
	wcv "WEB_SSL_PORT"             "443"
	wcv "WEB_SSL"                  "openssl"
	wcv "PROXY_SYSTEM"             ""
	wcv "STATS_SYSTEM"             "awstats"
	wcv "WEB_BACKEND"              "php-fpm"
	wcv "DB_SYSTEM"                "mysql"
	wcv "DB_PMA_ALIAS"             "phpmyadmin"
	if [ "$(PROFILE)" = "standard" ]; then \
	    wcv "MAIL_SYSTEM"          "exim4"; \
	    wcv "IMAP_SYSTEM"          "dovecot"; \
	    wcv "ANTISPAM_SYSTEM"      "rspamd"; \
	    wcv "SIEVE_SYSTEM"         "yes"; \
	    wcv "WEBMAIL_SYSTEM"       "roundcube"; \
	    wcv "WEBMAIL_ALIAS"        "webmail"; \
	fi
	wcv "CRON_SYSTEM"              "cron"
	wcv "FIREWALL_SYSTEM"          "iptables"
	wcv "FIREWALL_EXTENSION"       "fail2ban"
	wcv "DISK_QUOTA"               "no"
	wcv "RESOURCES_LIMIT"          "no"
	wcv "BACKUP_SYSTEM"            "local"
	wcv "BACKUP_GZIP"              "4"
	wcv "BACKUP_MODE"              "zstd"
	wcv "LANGUAGE"                 "en"
	wcv "LOGIN_STYLE"              "default"
	wcv "THEME"                    "dark"
	wcv "INACTIVE_SESSION_TIMEOUT" "60"
	wcv "VERSION"                  "$(VERSION)"
	wcv "RELEASE_BRANCH"           "release"
	wcv "UPGRADE_SEND_EMAIL"       "true"
	wcv "UPGRADE_SEND_EMAIL_LOG"   "false"
	wcv "API"                      "no"
	wcv "API_SYSTEM"               "0"
	wcv "API_ALLOWED_IP"           ""
	wcv "ROOT_USER"                "$$HESTIA_ADMIN"
	echo "[ * ] Installing packages, templates, firewall data..."
	cp -rf $(HESTIA_COMMON_DIR)/packages $(HESTIA)/data/
	IFS='.' read -r -a dom <<< "$$HESTIA_HOSTNAME"; \
	if [ -n "$${dom[-2]:-}" ] && [ -n "$${dom[-1]:-}" ]; then \
	    SDOMAIN="$${dom[-2]}.$${dom[-1]}"; \
	    sed -i "s/domain.tld/$$SDOMAIN/g" $(HESTIA)/data/packages/*.pkg 2>/dev/null || true; \
	fi
	cp -rf $(HESTIA_INSTALL_DIR)/templates $(HESTIA)/data/
	cp -rf $(HESTIA_COMMON_DIR)/templates/web/ $(HESTIA)/data/templates
	cp -rf $(HESTIA_COMMON_DIR)/firewall $(HESTIA)/data/
	rm -f $(HESTIA)/data/firewall/ipset/blacklist.sh \
	    $(HESTIA)/data/firewall/ipset/blacklist.ipv6.sh
	if [ "$(PROFILE)" != "standard" ]; then \
	    sed -i "/COMMENT='SMTP'/d" $(HESTIA)/data/firewall/rules.conf 2>/dev/null || true; \
	    sed -i "/COMMENT='IMAP'/d" $(HESTIA)/data/firewall/rules.conf 2>/dev/null || true; \
	    sed -i "/COMMENT='POP3'/d"  $(HESTIA)/data/firewall/rules.conf 2>/dev/null || true; \
	fi
	sed -i "/COMMENT='FTP'/d" $(HESTIA)/data/firewall/rules.conf 2>/dev/null || true
	cp -rf $(HESTIA_COMMON_DIR)/api $(HESTIA)/data/
	echo "[ * ] Setting hostname..."
	$(HESTIA)/bin/h-change-sys-hostname "$$HESTIA_HOSTNAME" > /dev/null 2>&1 || true
	echo "[ * ] Configuring OpenSSL TLS ciphers..."
	TLS13="TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384"; \
	if ! grep -qw "^ssl_conf = ssl_sect$$" /etc/ssl/openssl.cnf 2>/dev/null; then \
	    sed -i '/providers = provider_sect$$/a ssl_conf = ssl_sect' /etc/ssl/openssl.cnf; \
	fi; \
	if ! grep -qw "^\[ssl_sect\]$$" /etc/ssl/openssl.cnf 2>/dev/null; then \
	    printf '\n[ssl_sect]\nsystem_default = hestia_openssl_sect\n\n[hestia_openssl_sect]\nCiphersuites = %s\nOptions = PrioritizeChaCha\n' \
	        "$$TLS13" >> /etc/ssl/openssl.cnf; \
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
	MIN=$$(tr -dc '012345' < /dev/urandom | head -c 2 || true)
	HOUR=$$(tr -dc '1234567' < /dev/urandom | head -c 1 || true)
	mkdir -p /var/spool/cron/crontabs
	{ \
	    echo "MAILTO=\"\""; \
	    echo "CONTENT_TYPE=\"text/plain; charset=utf-8\""; \
	    echo "*/2 * * * * sudo $(HESTIA)/bin/h-update-sys-queue restart"; \
	    echo "10 00 * * * sudo $(HESTIA)/bin/h-update-sys-queue daily"; \
	    echo "15 02 * * * sudo $(HESTIA)/bin/h-update-sys-queue disk"; \
	    echo "10 00 * * * sudo $(HESTIA)/bin/h-update-sys-queue traffic"; \
	    echo "30 03 * * * sudo $(HESTIA)/bin/h-update-sys-queue webstats"; \
	    echo "*/5 * * * * sudo $(HESTIA)/bin/h-update-sys-queue backup"; \
	    echo "10 05 * * * sudo $(HESTIA)/bin/h-backup-users"; \
	    echo "20 00 * * * sudo $(HESTIA)/bin/h-update-user-stats"; \
	    echo "*/5 * * * * sudo $(HESTIA)/bin/h-update-sys-rrd"; \
	    echo "$$MIN $$HOUR * * * sudo $(HESTIA)/bin/h-update-letsencrypt-ssl"; \
	    echo "41 4 * * * sudo $(HESTIA)/bin/h-update-sys-hestia-all"; \
	} > /var/spool/cron/crontabs/hestiaweb
	chmod 600 /var/spool/cron/crontabs/hestiaweb
	chown hestiaweb:hestiaweb /var/spool/cron/crontabs/hestiaweb
	$(HESTIA)/bin/h-add-cron-hestia-autoupdate apt > /dev/null 2>&1 || true
	$(HESTIA)/bin/h-change-sys-port 8083 > /dev/null 2>&1 || true
	$(HESTIA)/bin/h-update-sys-defaults > /dev/null 2>&1 || true
	[ -f /root/.bashrc ] && grep -q 'hestia.sh' /root/.bashrc || \
	    printf 'if [ "$${PATH#*/usr/local/hestia/bin*}" = "$$PATH" ]; then\n    . /etc/profile.d/hestia.sh\nfi\n' >> /root/.bashrc
	touch "$(_DONE_CONFIGURE)"
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
	echo "[ * ] Building initial RRD graphs..."
	$(HESTIA)/bin/h-update-sys-rrd > /dev/null 2>&1 || true
	echo "[ * ] Final package upgrade..."
	apt-get -qq update
	DEBIAN_FRONTEND=noninteractive apt-get -y \
	    -o Dpkg::Progress-Fancy=1 \
	    upgrade >> $(LOG) 2>&1
	HOST_IP=$$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{print $$7; exit}' \
	    || hostname -I | awk '{print $$1}')
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
	echo "  IMPORTANT: Reboot the server to complete the installation."
	echo ""
