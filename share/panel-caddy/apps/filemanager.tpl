# File manager — per-customer FPM pool behind a panel-authenticated proxy (#419).
# Rendered (port + secret substituted) to /etc/caddy/apps/filemanager.conf by
# h-add-sys-filemanager, 0640 root:caddy because it carries the shared secret.
# Removed by h-delete-sys-filemanager → /fm/ becomes a 404 when not installed.
#
# Two OVERWRITTEN headers are the entire Caddy-side trust model (§7.2 invariant —
# guarded by a smoke test). Neither may ever come from the client:
#   Host              fm-<user>.local  — taken from the forward_auth response
#                     (X-Hestia-User), NEVER the client; selects the customer's
#                     vhost on the private listener.
#   X-Hestia-FM-Auth  <secret>         — proves the request came from Caddy; the
#                     private listener 403s without it. A client value is replaced.
# The customer identity is decided ONLY by fm-auth.php (valid panel session + that
# user's FILE_MANAGER='yes'). The pool then runs as that customer, so the kernel
# UID — not this proxy — is the actual file-access boundary.
#
# /fm is deliberately NOT stripped: TFM builds its self-URLs from PHP_SELF, so
# keeping the prefix keeps its links/asset refs correct without patching the app.
handle /fm/* {
    # Structural form of the §7.2 invariant: DROP every inbound X-Hestia-* before
    # auth, so a client can never smuggle one in. The trusted values are set below
    # (X-Hestia-User/Theme from the forward_auth response, X-Hestia-FM-Auth by us).
    # Wildcard, so a future X-Hestia-* header is covered without editing this list.
    request_header -X-Hestia-*
    forward_auth unix//run/hestia-php.sock {
        uri /fm-auth.php
        transport fastcgi {
            env SCRIPT_FILENAME /usr/local/hestia/web/fm-auth.php
            env SCRIPT_NAME /fm-auth.php
        }
        copy_headers X-Hestia-User X-Hestia-Theme
    }
    reverse_proxy 127.0.0.1:%FILE_MANAGER_PORT% {
        header_up Host fm-{http.request.header.X-Hestia-User}.local
        header_up X-Hestia-FM-Auth "%FM_SECRET%"
    }
}
