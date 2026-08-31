# Rendered for offline domains in every web model - not user-selectable

<VirtualHost %vhost%>

    ServerName %domain_idn%
    IncludeOptional %home%/%user%/conf/web/%domain%/botlimit.apache2.conf*
    %alias_string%
    ServerAdmin %email%
    DocumentRoot %docroot%
    CustomLog /var/log/%web_system%/domains/%domain%.bytes bytes
    CustomLog /var/log/%web_system%/domains/%domain%.log combined
    ErrorLog /var/log/%web_system%/domains/%domain%.error.log

    IncludeOptional %home%/%user%/conf/web/%domain%/apache2.forcessl.conf*

    ErrorDocument 503 /offline/index.html
    Alias /offline/ %docroot%/
    RedirectMatch 503 ^/(?!offline/|\.well-known/)

    <Directory %docroot%>
        AllowOverride All
        Options -Indexes
        # page dir is outside the granted /home paths
        Require all granted
    </Directory>

    IncludeOptional /etc/apache2/conf.d/*.inc
</VirtualHost>
