# HestiaRE — controller (stats / web UI). Bound to a unix socket, NOT a TCP
# port: on 127.0.0.1:11334 rspamd treats every localhost connection as secure
# (no password), so any local shell user — including a customer granted SSH —
# could read the controller API (e.g. /history exposes recipients of all
# domains).
#
# The socket is mode 0660, owner _rspamd, group _rspamd-ctrl — a dedicated
# group whose ONLY purpose is reaching this socket (so the grant carries no
# other _rspamd-group file access). h-add-sys-rspamd grants that group to the
# Panel-Caddy *process* via a systemd drop-in (SupplementaryGroups=), NOT to
# the caddy *user* in /etc/group — otherwise the app FPM pools that also run
# as caddy (phpMyAdmin/Adminer/Roundcube) would inherit it through
# initgroups() and reach the controller past forward_auth (#341). _rspamd is a
# member of _rspamd-ctrl only so the worker can chgrp its own socket.
#
# A unix-socket connection is still treated as secure, so the in-panel path
# needs no rspamd login. password + enable_password (hashes) are still
# appended at install time (overriding the stock "q1" default) as defense in
# depth.
bind_socket = "/run/rspamd/controller.sock mode=0660 owner=_rspamd group=_rspamd-ctrl";
