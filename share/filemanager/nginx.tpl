# File manager private listener — nginx variant (#419). Rendered to
# /etc/nginx/conf.d/fm-%user%.conf by h-add-user-filemanager when nginx is the
# front (nginx-only, or nginx+apache where apache is skipped for the FM path).
# Loopback-only; only Panel-Caddy talks to it, proven by the shared secret header.
server {
    listen 127.0.0.1:%FILE_MANAGER_PORT%;
    server_name fm-%user%.local;

    # Only Caddy knows the secret; a local user who reaches the loopback port
    # (or a forged/missing header) gets 403. This is the fail-closed §7.2 gate.
    if ($http_x_hestia_fm_auth != "%FM_SECRET%") { return 403; }

    # Root is the app's PARENT so the /fm/ URL maps 1:1 onto /usr/share/filemanager/fm
    # (Caddy does not strip /fm, so SCRIPT_NAME stays /fm/... and TFM's PHP_SELF links stay correct).
    root /usr/share/filemanager;
    index index.php;

    location ~ ^/fm/.+\.php$ {
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass unix:/run/hestia/fm/%user%.sock;
    }

    location /fm/ {
        try_files $uri $uri/ /fm/index.php$is_args$args;
    }

    # Nothing outside /fm/ is served here.
    location / { return 404; }
}
