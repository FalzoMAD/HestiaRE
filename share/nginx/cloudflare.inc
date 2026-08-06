# Cloudflare IP Ranges
#
# This is the FALLBACK: the installer overwrites this file wholesale from the CF API and
# only then, so a failed fetch leaves exactly what stands here. real_ip_header must
# therefore be part of it - without the directive nginx falls back to its own default,
# X-Real-IP, which Cloudflare does not manage and forwards from the client verbatim. That
# ignores CF-Connecting-IP entirely (measured on 1.26.3), so every visitor is logged as the
# CF edge and fail2ban eventually bans the edge itself, while a forged X-Real-IP is taken
# as the client and propagates through proxy_set_header into apache and the webmail jails.
# IPv4
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 131.0.72.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
# IPv6
set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;

real_ip_header CF-Connecting-IP;
