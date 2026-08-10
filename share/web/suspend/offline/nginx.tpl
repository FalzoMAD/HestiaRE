# Rendered for offline domains in every web model - not user-selectable

server {
	listen      %ip%:%web_port%;
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

	error_page 503 /index.html;
	location = /index.html { }
	location / { return 503; }

	include %home%/%user%/conf/web/%domain%/nginx.conf_lets*;
}
