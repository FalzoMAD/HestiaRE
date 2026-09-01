#=========================================================================#
# Docker Proxy Domain Template (#566)                                     #
# DO NOT MODIFY THIS FILE! CHANGES WILL BE LOST WHEN REBUILDING DOMAINS   #
# The whole site is served by the customer's container: no docroot, no    #
# static branch - everything is proxied, WebSockets included. The include #
# globs are load-bearing: Let's Encrypt, CrowdSec, botlimit, forcessl and #
# hsts all attach through them and their absence is silent.               #
#=========================================================================#

server {
	listen      %ip%:%front_port%;
	listen      [%ip6%]:%front_port%;
	server_name %domain_idn% %alias_idn%;
	include %home%/%user%/conf/web/%domain%/nginx.crowdsec.conf*;
	include %home%/%user%/conf/web/%domain%/nginx.botlimit.conf*;
	error_log   /var/log/%web_system%/domains/%domain%.error.log error;
	access_log  /var/log/%web_system%/domains/%domain%.log combined;
	access_log  /var/log/%web_system%/domains/%domain%.bytes bytes;

	include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

	# dotfiles stay hidden; .well-known passes (ACME wins via its own regex location,
	# anything else under it reaches the container - matrix-style well-known works)
	location ~ /\.(?!well-known\/) {
		deny all;
		return 404;
	}

	location / {
		proxy_pass http://%docker_ip%:%docker_port%;

		# any proxy_set_header here cancels ALL inherited ones, so the standard set is
		# repeated next to the WebSocket pair
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection $connection_upgrade;
		proxy_set_header Host $host;
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto $scheme;
		# idle WebSockets die at the 60s default
		proxy_read_timeout 3600s;

		# per-domain fragments (a location / block cannot be replaced by a later include)
		include %home%/%user%/conf/web/%domain%/nginx.location.d/*.conf;
	}

	include %home%/%user%/conf/web/%domain%/nginx.conf_*;
}
#=HESTIARE-SSL-VHOST=#
#=========================================================================#
# Docker Proxy Domain Template (#566)                                     #
# DO NOT MODIFY THIS FILE! CHANGES WILL BE LOST WHEN REBUILDING DOMAINS   #
#=========================================================================#

server {
	listen      %ip%:%front_ssl_port% ssl;
	listen      [%ip6%]:%front_ssl_port% ssl;
	server_name %domain_idn% %alias_idn%;
	include %home%/%user%/conf/web/%domain%/nginx.crowdsec.conf*;
	include %home%/%user%/conf/web/%domain%/nginx.botlimit.conf*;
	error_log   /var/log/%web_system%/domains/%domain%.error.log error;
	access_log  /var/log/%web_system%/domains/%domain%.log combined;
	access_log  /var/log/%web_system%/domains/%domain%.bytes bytes;

	ssl_certificate     %ssl_pem%;
	ssl_certificate_key %ssl_key%;

	# TLS 1.3 0-RTT anti-replay
	if ($anti_replay = 307) { return 307 https://$host$request_uri; }
	if ($anti_replay = 425) { return 425; }

	include %home%/%user%/conf/web/%domain%/nginx.hsts.conf*;

	location ~ /\.(?!well-known\/) {
		deny all;
		return 404;
	}

	# no proxy_hide_header Upgrade here (the hosting stpl carries it): it would strip
	# exactly the handshake header WebSockets need
	location / {
		proxy_pass http://%docker_ip%:%docker_port%;

		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection $connection_upgrade;
		proxy_set_header Host $host;
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto $scheme;
		proxy_read_timeout 3600s;

		# same fragment dir as the plain vhost: one file drives http and https
		include %home%/%user%/conf/web/%domain%/nginx.location.d/*.conf;
	}

	include %home%/%user%/conf/web/%domain%/nginx.ssl.conf_*;
}
