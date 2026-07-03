# phpPgAdmin — reverse-proxied to the Panel-Caddy (:8083), which serves it
# from a dedicated caddy FPM pool. Included per customer domain vhost via
# `include /etc/nginx/conf.d/phppgadmin.inc*;`. %pga_alias% = DB_PGA_ALIAS.
location /%pga_alias% {
	proxy_pass https://127.0.0.1:8083;
	proxy_set_header Host $host;
	proxy_set_header X-Real-IP $remote_addr;
	proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	proxy_set_header X-Forwarded-Proto $scheme;
	proxy_ssl_server_name on;
	proxy_ssl_verify off;
}
