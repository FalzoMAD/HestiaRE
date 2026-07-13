# Adminer — served by Panel-Caddy via the dedicated caddy FPM pool.
# Deployed to /etc/caddy/apps/adminer.conf by h-add-sys-adminer (imported
# inside the :8083 site block). Fixed alias /adminer/. Same exposure model as
# phpMyAdmin: served on the panel port, NOT behind forward_auth — the gate is
# Adminer's own login (DB credentials required) plus firewall on :8083. The
# unauthenticated login form can reach arbitrary DB hosts (SSRF); restricting
# that is the #350 follow-up. Removed by h-remove-sys-adminer.
redir /adminer /adminer/ 308
handle_path /adminer/* {
    root * /usr/share/adminer
    php_fastcgi unix//run/hestia-adminer.sock
    file_server
}
