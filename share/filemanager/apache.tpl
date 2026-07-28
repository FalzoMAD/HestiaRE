# File manager private listener - apache variant (#419). Rendered to
# /etc/apache2/conf.d/fm-%user%.conf by h-add-user-filemanager only in the
# apache-only case (no nginx front). Needs `Listen 127.0.0.1:%FILE_MANAGER_PORT%`
# added once by h-add-sys-filemanager and mod_proxy_fcgi (already used by web pools).
# Loopback-only; only Panel-Caddy reaches it, proven by the shared secret header.
<VirtualHost 127.0.0.1:%FILE_MANAGER_PORT%>
    ServerName fm-%user%.local
    # Root is the app's PARENT so /fm/ maps 1:1 onto /usr/share/filemanager/fm
    # (Caddy does not strip /fm → SCRIPT_NAME stays /fm/..., PHP_SELF links stay correct).
    DocumentRoot /usr/share/filemanager

    <Directory /usr/share/filemanager>
        # Only Caddy knows the secret; a forged/missing header is 403 - the §7.2 gate.
        # This gates the STATIC assets; the .php twin below re-asserts the SAME check
        # in <FilesMatch> (apache authorizes proxied .php there, not here). Both copies
        # must stay identical - do NOT "de-duplicate" one away.
        Require expr "%{HTTP:X-Hestia-FM-Auth} == '%FM_SECRET%'"
        DirectoryIndex index.php
        AllowOverride None
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/hestia/fm/%user%.sock|fcgi://localhost"
        # The Directory Require above only gates static assets; a .php handled by
        # SetHandler proxy is authorized in THIS FilesMatch context, where the
        # server-wide "Require all denied" fallback (conf.d/hestia-event.conf, #397)
        # otherwise wins. Re-assert the secret gate here so index.php runs.
        Require expr "%{HTTP:X-Hestia-FM-Auth} == '%FM_SECRET%'"
    </FilesMatch>
</VirtualHost>
