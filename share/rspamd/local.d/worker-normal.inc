# HestiaRE — scan worker. Exim talks to this port via
# "spamd_address = 127.0.0.1 11333 variant=rspamd" (exim4.conf.template).
bind_socket = "127.0.0.1:11333";
