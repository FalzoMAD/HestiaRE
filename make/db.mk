# -------------------------------------------------------- #
# db.mk — MariaDB + phpMyAdmin
# -------------------------------------------------------- #

.PHONY: _install-db

_install-db:
	@[ ! -f $(CONF_DIR)/.done.db ] || { echo "[ skip ] db already configured"; exit 0; }
	echo "[ * ] Installing database packages (MariaDB $(MARIADB_VER))..."
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
	echo "[ * ] Securing MariaDB..."
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
	touch $(CONF_DIR)/.done.db
	echo ""
	echo "[ OK ] install-db complete"
