# HestiaRE — scan worker. Exim hands messages over via
# "spamd_address = /run/rspamd/normal.sock variant=rspamd" (exim4.conf.template).
# A unix socket, not 127.0.0.1:11333: on a TCP port any local shell user —
# including a customer granted SSH — could read /symbols (the active rule and
# score configuration) and submit scan jobs. The socket is mode 0660 owned by
# _rspamd; the installer adds Debian-exim to the _rspamd group. Same pattern
# as the controller (worker-controller.inc).
bind_socket = "/run/rspamd/normal.sock mode=0660 owner=_rspamd";
