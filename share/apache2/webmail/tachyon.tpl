<VirtualHost %ip%:%web_port%>
    ServerName %domain_idn%
    ServerAlias %alias_idn%

    IncludeOptional %home%/%user%/conf/mail/%root_domain%/apache2.forcessl.conf*

    # LE http-01: serve the challenge from disk, never proxy it. The apache-only
    # branch of h-add-letsencrypt-domain writes the token to
    # /var/lib/tachyon/.well-known/acme-challenge/.
    ProxyPass /.well-known/acme-challenge/ !
    Alias /.well-known/acme-challenge/ /var/lib/tachyon/.well-known/acme-challenge/
    # The tachyon docroot ships a .htaccess with directives disallowed in this
    # context; without AllowOverride None Apache aborts the local challenge serve
    # and falls through to the proxy (verified live). We only serve the token here.
    <Directory /var/lib/tachyon>
        AllowOverride None
    </Directory>
    <Directory /var/lib/tachyon/.well-known/acme-challenge/>
        Require all granted
    </Directory>

    # Tachyon is rendered by the Panel-Caddy listener on 127.0.0.1:8091
    # (share/panel-caddy/webmail-tachyon.conf). This vhost only reverse-proxies
    # to it - no local docroot, so the caddy-owned /var/lib/tachyon (and its
    # /data) is never served by apache/www-data (#205). Needs mod_proxy_http
    # (enabled at install). With nginx in front this vhost is inert; it is the
    # public entrypoint only in the apache-only profile.
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:8091/ retry=0
    ProxyPassReverse / http://127.0.0.1:8091/
    # Apache is the public front in the apache-only profile, so REMOTE_ADDR is the real client.
    # set (not add) overwrites any client-supplied value, so both are non-forgeable. X-Real-IP
    # feeds Roundcube, Client-IP feeds Tachyon (X-Forwarded-For is clobbered downstream).
    RequestHeader set X-Real-IP "expr=%{REMOTE_ADDR}"
    RequestHeader set Client-IP "expr=%{REMOTE_ADDR}"
    RequestHeader set X-Forwarded-Proto "http"

    IncludeOptional %home%/%user%/conf/mail/%root_domain%/%web_system%.conf_*
</VirtualHost>
