# -------------------------------------------------------- #
# db.mk — MariaDB + phpMyAdmin
# -------------------------------------------------------- #

.PHONY: _install-db

_install-db:
	@[ ! -f $(CONF_DIR)/.done.db ] || { echo "[ skip ] db already configured"; exit 0; }
	source $(HESTIA)/make/helpers.sh
	echo "[ * ] Installing database packages (MariaDB $(MARIADB_VER))..."
	hestia_apt -y install \
	    mariadb-client mariadb-common mariadb-server
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
	MPASS=$$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16 || true)
	printf '[client]\npassword='"'"'%s'"'"'\n' "$$MPASS" > /root/.my.cnf
	chmod 600 /root/.my.cnf
	mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$$MPASS'; FLUSH PRIVILEGES;"
	mariadb -e "UPDATE mysql.global_priv SET priv=json_set(priv, '$$.password_last_changed', UNIX_TIMESTAMP(), '$$.plugin', 'mysql_native_password', '$$.authentication_string', 'invalid', '$$.auth_or', json_array(json_object(), json_object('plugin', 'unix_socket'))) WHERE User='root';"
	mariadb -e "DELETE FROM mysql.global_priv WHERE User='';"
	mariadb -e "DROP DATABASE IF EXISTS test;"
	mariadb -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
	mariadb -e "FLUSH PRIVILEGES;"
	grep -q 'HESTIA_MPASS' "$(INSTALL_CONF)" \
	    || echo "HESTIA_MPASS=\"$$MPASS\"" >> "$(INSTALL_CONF)"
	wcv() { echo "$$1='$$2'" >> $(HESTIA)/conf/hestia.conf; }
	wcv "DB_SYSTEM"                "mysql"
	wcv "DB_PMA_ALIAS"             "phpmyadmin"
	echo "[ * ] Installing phpMyAdmin..."
	$(HESTIA)/bin/h-add-sys-phpmyadmin >> $(LOG)
	touch $(CONF_DIR)/.done.db
	echo ""
	echo "[ OK ] install-db complete"
