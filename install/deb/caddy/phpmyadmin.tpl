# phpMyAdmin — served by Panel-Caddy via the dedicated caddy FPM pool.
# Deployed to /etc/caddy/apps/phpmyadmin.conf by h-change-sys-db-alias
# (imported inside the :8083 site block). %alias% = DB_PMA_ALIAS.
handle_path /%alias%/* {
    root * /usr/share/phpmyadmin
    php_fastcgi unix//run/hestia-pma.sock
    file_server
}
