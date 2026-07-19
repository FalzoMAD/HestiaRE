<VirtualHost %ip%:%web_port%>
    ServerName %domain_idn%
    ServerAlias %alias_idn%

    IncludeOptional %home%/%user%/conf/mail/%root_domain%/apache2.forcessl.conf*

    # LE http-01: serve the challenge from disk, never proxy it. The apache-only
    # branch of h-add-letsencrypt-domain writes the token to
    # /var/lib/snappymail/.well-known/acme-challenge/.
    ProxyPass /.well-known/acme-challenge/ !
    Alias /.well-known/acme-challenge/ /var/lib/snappymail/.well-known/acme-challenge/
    <Directory /var/lib/snappymail/.well-known/acme-challenge/>
        Require all granted
    </Directory>

    # SnappyMail is rendered by the Panel-Caddy listener on 127.0.0.1:8091
    # (share/panel-caddy/webmail-snappymail.conf). This vhost only reverse-proxies
    # to it — no local docroot, so the caddy-owned /var/lib/snappymail (and its
    # /data) is never served by apache/www-data (#205). Needs mod_proxy_http
    # (enabled at install). With nginx in front this vhost is inert; it is the
    # public entrypoint only in the apache-only profile.
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:8091/ retry=0
    ProxyPassReverse / http://127.0.0.1:8091/
    RequestHeader set X-Forwarded-Proto "http"

    IncludeOptional %home%/%user%/conf/mail/%root_domain%/%web_system%.conf_*
</VirtualHost>
