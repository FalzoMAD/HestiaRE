server {
	listen %ip%:%proxy_port% default_server;
	listen [%ip6%]:%proxy_port% default_server;
	server_name _;
	access_log off;
	error_log /dev/null;

	location / {
		proxy_pass http://%backend_addr%:%web_port%;
   }
}

server {
	listen %ip%:%proxy_ssl_port% default_server ssl;
	listen [%ip6%]:%proxy_ssl_port% default_server ssl;
	server_name _;
	access_log off;
	error_log /dev/null;

	ssl_certificate     /etc/ssl/hestia/certificate.crt;
	ssl_certificate_key /etc/ssl/hestia/certificate.key;

	return 301 http://$host$request_uri;

	location / {
		root /var/www/document_errors/;
	}

	location /error/ {
		alias /var/www/document_errors/;
	}
}
