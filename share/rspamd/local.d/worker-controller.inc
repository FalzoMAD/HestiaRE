# HestiaRE — controller (stats / web UI), localhost only. The UI is
# reverse-proxied by Panel-Caddy at /rspamd/ (share/panel-caddy/apps/).
# enable_password (hash) is appended at install time by h-install-hestia;
# reset any time with: h-change-sys-rspamd-password
bind_socket = "127.0.0.1:11334";
