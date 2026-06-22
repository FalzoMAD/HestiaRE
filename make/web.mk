# -------------------------------------------------------- #
# web.mk — nginx, PHP multi (5.6–8.4), web pool config
# -------------------------------------------------------- #

.PHONY: _install-web

_install-web:
	@[ ! -f $(CONF_DIR)/.done.web ] || { echo "[ skip ] web already configured"; exit 0; }
	source $(HESTIA)/make/helpers.sh
	echo "[ * ] Installing web packages (nginx, PHP $(PHP_VER) extensions)..."
	hestia_apt -y install \
	    nginx \
	    php$(PHP_VER) php$(PHP_VER)-apcu php$(PHP_VER)-bz2 php$(PHP_VER)-cgi \
	    php$(PHP_VER)-cli php$(PHP_VER)-common php$(PHP_VER)-gd \
	    php$(PHP_VER)-imagick php$(PHP_VER)-imap php$(PHP_VER)-intl \
	    php$(PHP_VER)-ldap php$(PHP_VER)-pgsql php$(PHP_VER)-pspell \
	    php$(PHP_VER)-readline php$(PHP_VER)-xml
	wcv() { echo "$$1='$$2'" >> $(HESTIA)/conf/hestia.conf; }
	wcv "WEB_SYSTEM"               "nginx"
	wcv "WEB_PORT"                 "80"
	wcv "WEB_SSL_PORT"             "443"
	wcv "WEB_SSL"                  "openssl"
	wcv "PROXY_SYSTEM"             ""
	wcv "STATS_SYSTEM"             "awstats"
	wcv "WEB_BACKEND"              "php-fpm"
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
	resolver=""; \
	for ns in $$(grep -is '^nameserver' /etc/resolv.conf | awk '{print $$2}'); do \
	    if echo "$$ns" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$$'; then \
	        resolver="$${resolver:+$$resolver }$$ns"; \
	    fi; \
	done; \
	[ -n "$$resolver" ] && \
	    sed -i "s/1.0.0.1 8.8.4.4 1.1.1.1 8.8.8.8/$$resolver/g" /etc/nginx/nginx.conf || true
	echo "[ * ] Updating Cloudflare IP ranges..."
	cf_ips=$$(curl -fsLm5 --retry 2 https://api.cloudflare.com/client/v4/ips 2>/dev/null || echo ""); \
	if [ -n "$$cf_ips" ] && [ "$$(echo "$$cf_ips" | jq -r '.success//""')" = "true" ]; then \
	    cf_inc="/etc/nginx/conf.d/cloudflare.inc"; \
	    { echo "# Cloudflare IP Ranges"; echo ""; echo "# IPv4"; \
	      echo "$$cf_ips" | jq -r '.result.ipv4_cidrs[]//""' | sort | sed 's/^/set_real_ip_from /;s/$$/;/'; \
	      echo ""; echo "# IPv6"; \
	      echo "$$cf_ips" | jq -r '.result.ipv6_cidrs[]//""' | sort | sed 's/^/set_real_ip_from /;s/$$/;/'; \
	      echo ""; echo "real_ip_header CF-Connecting-IP;"; \
	    } > $$cf_inc; \
	    echo "  Cloudflare ranges updated"; \
	fi
	update-rc.d nginx defaults > /dev/null 2>&1
	systemctl start nginx
	echo "[ * ] Installing PHP multi-version ($(MULTIPHP_VER))..."
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
	printf '#!/bin/sh\nfind -O3 /home/*/tmp/ -ignore_readdir_race -depth -mindepth 1 -name '"'"'sess_*'"'"' -type f -cmin '"'"'+10080'"'"' -delete > /dev/null 2>&1\nfind -O3 %s/data/sessions/ -ignore_readdir_race -depth -mindepth 1 -name '"'"'sess_*'"'"' -type f -cmin '"'"'+10080'"'"' -delete > /dev/null 2>&1\n' \
	    "$(HESTIA)" > /etc/cron.daily/php-session-cleanup
	chmod 755 /etc/cron.daily/php-session-cleanup
	mkdir -p /var/www/html /var/www/document_errors
	cp -rf $(HESTIA_COMMON_DIR)/templates/web/unassigned/index.html /var/www/html/
	cp -rf $(HESTIA_COMMON_DIR)/templates/web/skel/document_errors/* /var/www/document_errors/
	cp -f $(HESTIA_INSTALL_DIR)/logrotate/httpd-prerotate/* /etc/logrotate.d/httpd-prerotate/ 2>/dev/null || true
	rm -f /etc/cron.d/awstats
	touch $(CONF_DIR)/.done.web
	echo ""
	echo "[ OK ] install-web complete"
