# rspamd controller web UI — reverse-proxied to the localhost-only
# controller worker (127.0.0.1:11334, see share/rspamd/local.d/
# worker-controller.inc). Login uses the controller password; set or
# reset it with h-change-sys-rspamd-password.
# Deployed to /etc/caddy/apps/rspamd.conf by h-install-hestia (mail stage).
redir /rspamd /rspamd/ 308
handle_path /rspamd/* {
    reverse_proxy 127.0.0.1:11334
}
