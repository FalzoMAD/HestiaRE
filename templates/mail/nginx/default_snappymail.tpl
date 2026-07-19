server {
	listen      %ip%:%proxy_port%;
	server_name %domain_idn% %alias_idn%;
	access_log  /var/log/nginx/domains/%domain%.log combined;
	error_log   /var/log/nginx/domains/%domain%.error.log error;

	include %home%/%user%/conf/mail/%root_domain%/nginx.forcessl.conf*;

	# Deny dotfiles, but let ACME http-01 challenges (.well-known/…) through.
	location ~ /\.(?!well-known\/) {
		deny all;
		return 404;
	}

	# SnappyMail is rendered by the Panel-Caddy listener on 127.0.0.1:8091
	# (share/panel-caddy/webmail-snappymail.conf). This customer vhost only
	# terminates TLS for webmail.<domain>/mail.<domain> and reverse-proxies to
	# it — no local docroot, so the caddy-owned /var/lib/snappymail is never
	# served by nginx/www-data, and the old /data leak is gone with it (#205).
	location / {
		proxy_set_header Host $host;
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto $scheme;
		proxy_pass http://127.0.0.1:8091;
	}

	# LE http-01: conf/mail/<domain>/nginx.conf_letsencrypt injects a
	# `location ~ acme-challenge { return 200 … }` that outranks location / above.
	include %home%/%user%/conf/mail/%root_domain%/%proxy_system%.conf_*;
}
