# HestiaRE — controller (stats / web UI). Bound to a unix socket, NOT a TCP
# port: on 127.0.0.1:11334 rspamd treats every localhost connection as secure
# (no password), so any local shell user — including a customer granted SSH —
# could read the controller API (e.g. /history exposes recipients of all
# domains). The socket is mode 0660 owned by _rspamd; only members of the
# _rspamd group reach it. The installer adds `caddy` to that group so the
# panel proxy works; customer accounts are not in it. A unix-socket
# connection is still treated as secure, so the in-panel path needs no rspamd
# login. password + enable_password (hashes) are still appended at install
# time (overriding the stock "q1" default) as defense in depth.
bind_socket = "/run/rspamd/controller.sock mode=0660 owner=_rspamd";
