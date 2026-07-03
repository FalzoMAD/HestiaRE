# phpPgAdmin — served by Panel-Caddy via the dedicated caddy FPM pool.
# Deployed to /etc/caddy/apps/phppgadmin.conf by h-change-sys-db-alias
# (imported inside the :8083 site block). %alias% = DB_PGA_ALIAS.
redir /%alias% /%alias%/ 308
handle_path /%alias%/* {
    root * /usr/share/phppgadmin
    php_fastcgi unix//run/hestia-pga.sock
    file_server
}
