# rspamd controller web UI — gated behind the panel admin session, then
# reverse-proxied to the localhost-only controller (127.0.0.1:11334, see
# share/rspamd/local.d/worker-controller.inc). Reached via the panel page
# /list/rspamd/ (iframe, same-origin).
# Deployed to /etc/caddy/apps/rspamd.conf by h-install-hestia (mail stage).
#
# Access control: forward_auth calls the panel (rspamd-auth.php), which
# returns 2xx only for an authenticated admin session — anything else is
# blocked. The controller itself trusts localhost without a password
# (secure_ip), so we strip the X-Forwarded-* headers on the way in; otherwise
# rspamd would see the real client IP, secure_ip would not match, and it would
# demand its own password. With the headers stripped rspamd sees only Caddy
# (localhost) and no rspamd login is needed. The controller password set at
# install only matters for direct :11334 access, which is localhost-only.
redir /rspamd /rspamd/ 308
handle /rspamd/* {
    forward_auth unix//run/hestia-php.sock {
        uri /rspamd-auth.php
        transport fastcgi {
            env SCRIPT_FILENAME /usr/local/hestia/web/rspamd-auth.php
            env SCRIPT_NAME /rspamd-auth.php
        }
    }
    uri strip_prefix /rspamd
    reverse_proxy 127.0.0.1:11334 {
        header_up -X-Forwarded-For
        header_up -X-Forwarded-Proto
        header_up -X-Forwarded-Host
    }
}
