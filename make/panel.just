# -------------------------------------------------------- #
# panel.just — Caddy + hestia-php.service
# -------------------------------------------------------- #

_install-panel:
    [ ! -f "$CONF_DIR/.done.panel" ] || { echo "[ skip ] panel already configured"; exit 0; }
    source "$HESTIA/make/helpers.sh"
    echo "[ * ] Installing panel packages (Caddy, PHP $PHP_VER FPM)..."
    hestia_apt -y install \
        caddy \
        libphp-phpmailer \
        php${PHP_VER}-fpm php${PHP_VER}-mysql php${PHP_VER}-curl \
        php${PHP_VER}-zip php${PHP_VER}-gmp php${PHP_VER}-mbstring \
        php${PHP_VER}-opcache
    echo "[ * ] Configuring panel PHP-FPM..."
    mkdir -p /etc/php/hestia/fpm/pool.d
    cp -f "$HESTIA/conf/panel-php/php-fpm.conf" /etc/php/hestia/fpm/
    cp -f "$HESTIA/conf/panel-php/pool.d/panel.conf" /etc/php/hestia/fpm/pool.d/
    cp -f "$HESTIA/conf/panel-php/hestia-php.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable hestia-php
    systemctl start hestia-php
    echo "[ * ] Configuring Caddy..."
    mkdir -p /etc/caddy
    cp -f "$HESTIA/conf/panel-caddy/Caddyfile" /etc/caddy/Caddyfile
    cp -f "$HESTIA/conf/panel-caddy/hestia.conf" /etc/caddy/hestia.conf
    systemctl enable caddy
    systemctl start caddy
    touch "$CONF_DIR/.done.panel"
    echo ""
    echo "[ OK ] install-panel complete"
