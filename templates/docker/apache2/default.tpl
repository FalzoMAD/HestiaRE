#=========================================================================#
# Docker Proxy Domain Template (#566)                                     #
# DO NOT MODIFY THIS FILE! CHANGES WILL BE LOST WHEN REBUILDING DOMAINS   #
# apache-only model: apache itself fronts the container. Two lines are    #
# load-bearing for Let's Encrypt: the acme ProxyPass exemption must come  #
# BEFORE the catch-all (apache applies ProxyPass in order), and the       #
# DocumentRoot line must exist - LE greps it from this file and writes    #
# the token under it; without it the fallback computes /.well-known in    #
# the filesystem ROOT and no certificate is ever issued.                  #
#=========================================================================#

<VirtualHost %ip%:%front_port%>

    ServerName %domain_idn%
    IncludeOptional %home%/%user%/conf/web/%domain%/botlimit.apache2.conf*
    %alias_string%
    ServerAdmin %email%
    DocumentRoot %docroot%
    CustomLog /var/log/%web_system%/domains/%domain%.bytes bytes
    CustomLog /var/log/%web_system%/domains/%domain%.log combined
    ErrorLog /var/log/%web_system%/domains/%domain%.error.log

    IncludeOptional %home%/%user%/conf/web/%domain%/apache2.forcessl.conf*

    # acme tokens are served from disk, everything else goes to the container
    ProxyPass "/.well-known/acme-challenge/" "!"
    ProxyPreserveHost On
    ProxyPass "/" "http://%docker_ip%:%docker_port%/" upgrade=websocket
    ProxyPassReverse "/" "http://%docker_ip%:%docker_port%/"
    RequestHeader set X-Forwarded-Proto "http"

    <Directory %docroot%>
        AllowOverride All
        Options -Indexes
    </Directory>

    IncludeOptional %home%/%user%/conf/web/%domain%/%web_system%.conf_*
    IncludeOptional /etc/apache2/conf.d/*.inc
</VirtualHost>
#=HESTIARE-SSL-VHOST=#
#=========================================================================#
# Docker Proxy Domain Template (#566)                                     #
# DO NOT MODIFY THIS FILE! CHANGES WILL BE LOST WHEN REBUILDING DOMAINS   #
#=========================================================================#

<VirtualHost %ip%:%front_ssl_port%>

    ServerName %domain_idn%
    IncludeOptional %home%/%user%/conf/web/%domain%/botlimit.apache2.conf*
    %alias_string%
    ServerAdmin %email%
    DocumentRoot %sdocroot%
    CustomLog /var/log/%web_system%/domains/%domain%.bytes bytes
    CustomLog /var/log/%web_system%/domains/%domain%.log combined
    ErrorLog /var/log/%web_system%/domains/%domain%.error.log

    SSLEngine on
    SSLVerifyClient none
    SSLCertificateFile %ssl_crt%
    SSLCertificateKeyFile %ssl_key%
    %ssl_ca_str%SSLCertificateChainFile %ssl_ca%

    ProxyPass "/.well-known/acme-challenge/" "!"
    ProxyPreserveHost On
    ProxyPass "/" "http://%docker_ip%:%docker_port%/" upgrade=websocket
    ProxyPassReverse "/" "http://%docker_ip%:%docker_port%/"
    RequestHeader set X-Forwarded-Proto "https"

    <Directory %sdocroot%>
        AllowOverride All
        Options -Indexes
    </Directory>

    IncludeOptional %home%/%user%/conf/web/%domain%/%web_system%.ssl.conf_*
    IncludeOptional /etc/apache2/conf.d/*.inc
</VirtualHost>
