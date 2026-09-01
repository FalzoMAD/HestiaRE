# Rendered for suspended domains in every web model - not user-selectable

server {
	listen      %ip%:%web_port%;
	listen      [%ip6%]:%web_port%;
	server_name %domain_idn% %alias_idn%;
	include %home%/%user%/conf/web/%domain%/nginx.crowdsec.conf*;
	include %home%/%user%/conf/web/%domain%/nginx.botlimit.conf*;
	root        %docroot%;
	index       index.html;
	access_log  /var/log/%web_system%/domains/%domain%.log combined;
	access_log  /var/log/%web_system%/domains/%domain%.bytes bytes;
	error_log   /var/log/%web_system%/domains/%domain%.error.log error;

	include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

	location ~ /\.(?!well-known\/) {
		deny all;
		return 404;
	}

	location / {
		try_files $uri /index.html;

		location ~* ^.+\.(jpeg|jpg|png|webp|gif|bmp|ico|svg|css|js)$ {
			expires max;
		}
	}

	include %home%/%user%/conf/web/%domain%/nginx.conf_lets*;
}
