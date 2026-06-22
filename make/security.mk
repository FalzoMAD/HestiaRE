# -------------------------------------------------------- #
# security.mk — fail2ban, iptables, ipset
# -------------------------------------------------------- #

.PHONY: _install-security

_install-security:
	@[ ! -f $(CONF_DIR)/.done.security ] || { echo "[ skip ] security already configured"; exit 0; }
	source $(HESTIA)/make/helpers.sh
	echo "[ * ] Installing security packages (fail2ban, iptables, ipset)..."
	hestia_apt -y install \
	    fail2ban iptables ipset
	echo "[ * ] Configuring fail2ban..."
	mkdir -p /etc/fail2ban/filter.d /etc/fail2ban/jail.d
	cp -rf $(HESTIA_INSTALL_DIR)/fail2ban/filter.d/*.conf /etc/fail2ban/filter.d/
	cp -f $(HESTIA_INSTALL_DIR)/fail2ban/jail.local /etc/fail2ban/
	update-rc.d fail2ban defaults > /dev/null 2>&1
	systemctl enable fail2ban
	systemctl start fail2ban
	echo "[ * ] Configuring iptables/ipset..."
	if [ -d "$(HESTIA_INSTALL_DIR)/iptables" ]; then \
	    mkdir -p /etc/iptables; \
	    cp -f $(HESTIA_INSTALL_DIR)/iptables/rules.v4 /etc/iptables/ 2>/dev/null || true; \
	    cp -f $(HESTIA_INSTALL_DIR)/iptables/rules.v6 /etc/iptables/ 2>/dev/null || true; \
	fi
	if [ -d "$(HESTIA_INSTALL_DIR)/ipset" ]; then \
	    cp -f $(HESTIA_INSTALL_DIR)/ipset/*.conf /etc/ipset/ 2>/dev/null || true; \
	fi
	$(HESTIA)/bin/h-update-sys-ip 2>/dev/null || true
	touch $(CONF_DIR)/.done.security
	echo ""
	echo "[ OK ] install-security complete"
