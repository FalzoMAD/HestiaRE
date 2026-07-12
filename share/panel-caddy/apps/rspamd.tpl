# rspamd controller web UI — gated behind the panel admin session, then
# reverse-proxied to the controller's unix socket (/run/rspamd/controller.sock,
# see share/rspamd/local.d/worker-controller.inc). Reached via the panel page
# /list/rspamd/ (iframe, same-origin).
# Deployed to /etc/caddy/apps/rspamd.conf by h-install-hestia (mail stage).
#
# Access control has two independent layers:
#  1. forward_auth calls the panel (rspamd-auth.php), which returns 2xx only
#     for an authenticated admin session — anything else is blocked. This is
#     what keeps non-admins out.
#  2. The controller listens on a unix socket (mode 0660, group _rspamd), not
#     a TCP port, so it is NOT reachable by arbitrary local users — only the
#     _rspamd group (which the installer adds `caddy` to). This is what keeps
#     a customer with shell/SSH access from reading the controller directly.
#
# A unix-socket connection is treated by rspamd as secure, so no rspamd login
# is needed on the panel path. We still strip X-Forwarded-* so a forged header
# can never make rspamd fall back to password auth against a spoofed client.
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
    reverse_proxy unix//run/rspamd/controller.sock {
        header_up -X-Forwarded-For
        header_up -X-Forwarded-Proto
        header_up -X-Forwarded-Host
    }
}
