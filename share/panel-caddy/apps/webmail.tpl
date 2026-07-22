# Roundcube on the panel URL — :8083/webmail — for admin access without a
# customer domain, the phpMyAdmin/Adminer model (one app route per app, imported
# inside the :8083 site block ahead of the panel catch-all).
#
# Deployed to /etc/caddy/apps/webmail.conf by h-add-sys-roundcube; removed by
# h-delete-sys-roundcube. Shares the panel FPM pool (/run/hestia-webmail-rc.sock)
# with the prefix-less internal listener (127.0.0.1:8090) that the per-domain
# webmail.<domain> vhosts reverse-proxy to — one pool, two Caddy frontends.
#
# Roundcube-only on purpose: handle_path strips the /webmail prefix, and Roundcube
# emits relative asset URLs + detects its sub-path base, so it runs cleanly here.
# SnappyMail is a root-mounted app (assets hard-wired to /snappymail/…, no prefix)
# and cannot live under a sub-path — it stays reachable via webmail.<domain>, where
# it is root-mounted and works. So there is no SnappyMail panel route (#205).
redir /webmail /webmail/ 308
handle_path /webmail/* {
	root * /var/lib/roundcube/public_html
	php_fastcgi unix//run/hestia-webmail-rc.sock
	file_server
}
