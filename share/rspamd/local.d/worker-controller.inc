# HestiaRE — controller (stats / web UI), localhost only. The UI is embedded
# in the panel via Panel-Caddy at /list/rspamd/ (session-gated, no rspamd
# login). password + enable_password (hashes) are appended at install time by
# h-install-hestia, overriding rspamd's stock "q1" default.
bind_socket = "127.0.0.1:11334";
