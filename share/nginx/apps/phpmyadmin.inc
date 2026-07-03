# phpMyAdmin — reverse-proxied to the Panel-Caddy (:8083), which serves it
# from a dedicated caddy FPM pool. Included per customer domain vhost via
# `include /etc/nginx/conf.d/phpmyadmin.inc*;`. %pma_alias% = DB_PMA_ALIAS.
# Delivery is centralised on the panel; this block only proxies the alias.
location /%pma_alias% {
	proxy_pass https://127.0.0.1:8083;
	proxy_set_header Host $host;
	proxy_set_header X-Real-IP $remote_addr;
	proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	proxy_set_header X-Forwarded-Proto $scheme;
	proxy_ssl_server_name on;
	proxy_ssl_verify off;
}
