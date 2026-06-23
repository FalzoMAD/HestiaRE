# -------------------------------------------------------- #
# mail.mk — exim4, dovecot, rspamd, roundcube
#           (standard profile only)
# -------------------------------------------------------- #

.PHONY: _install-mail

_install-mail:
	@[ ! -f $(CONF_DIR)/.done.mail ] || { echo "[ skip ] mail already configured"; exit 0; }
	source $(HESTIA)/make/helpers.sh
	echo "[ * ] Installing mail packages (exim4, dovecot, rspamd)..."
	hestia_apt -y install \
	    exim4 exim4-daemon-heavy \
	    dovecot-imapd dovecot-pop3d dovecot-managesieved dovecot-sieve \
	    rspamd
	echo "[ * ] Configuring Exim4..."
	gpasswd -a $(EXIM_USR) mail > /dev/null 2>&1 || true
	cp -f $(HESTIA_INSTALL_DIR)/exim/exim4.conf.template /etc/exim4/ 2>/dev/null \
	    || cp -f $(HESTIA_INSTALL_DIR)/exim/exim4.conf.4.95.template /etc/exim4/exim4.conf.template
	cp -f $(HESTIA_INSTALL_DIR)/exim/dnsbl.conf /etc/exim4/
	cp -f $(HESTIA_INSTALL_DIR)/exim/spam-blocks.conf /etc/exim4/
	cp -f $(HESTIA_INSTALL_DIR)/exim/limit.conf /etc/exim4/
	cp -f $(HESTIA_INSTALL_DIR)/exim/system.filter /etc/exim4/
	touch /etc/exim4/white-blocks.conf
	SRS=$$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 || true)
	echo "$$SRS" > /etc/exim4/srs.conf
	chmod 640 /etc/exim4/srs.conf /etc/exim4/exim4.conf.template
	chown root:$(EXIM_USR) /etc/exim4/srs.conf
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
	DOVECOT_VER=$$(dovecot --version 2>/dev/null | cut -d. -f1,2 || echo "2.3")
	if [ "$$(printf '%s\n2.4' "$$DOVECOT_VER" | sort -V | head -1)" = "2.4" ]; then \
	    DCDIR="$(HESTIA)/conf/dovecot/2.4"; \
	else \
	    DCDIR="$(HESTIA)/conf/dovecot/2.3"; \
	fi
	cp -f "$$DCDIR/dovecot.conf" /etc/dovecot/
	cp -f "$$DCDIR/conf.d/"* /etc/dovecot/conf.d/
	cp -f "$$DCDIR/sieve/"* /etc/dovecot/conf.d/
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
	wcv() { echo "$$1='$$2'" >> $(HESTIA)/conf/hestia.conf; }
	if [ "$(PROFILE)" = "standard" ]; then \
	    wcv "MAIL_SYSTEM"          "exim4"; \
	    wcv "IMAP_SYSTEM"          "dovecot"; \
	    wcv "ANTISPAM_SYSTEM"      "rspamd"; \
	    wcv "SIEVE_SYSTEM"         "yes"; \
	    wcv "WEBMAIL_SYSTEM"       "roundcube"; \
	    wcv "WEBMAIL_ALIAS"        "webmail"; \
	fi
	echo "[ * ] Installing Roundcube..."
	$(HESTIA)/bin/h-add-sys-roundcube >> $(LOG)
	touch $(CONF_DIR)/.done.mail
	echo ""
	echo "[ OK ] install-mail complete"
