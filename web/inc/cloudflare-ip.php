<?php
// Static Cloudflare IP ranges (Eigenbau — replaces divinity76/cloudflare-ip-validator).
// Source: https://www.cloudflare.com/ips/ (fetched 2026-06-21)
// Update procedure: run `curl -s https://www.cloudflare.com/ips-v4/` and
// `curl -s https://www.cloudflare.com/ips-v6/` and replace the arrays below.

const CLOUDFLARE_IPV4_CIDRS = [
    '103.21.244.0/22',
    '103.22.200.0/22',
    '103.31.4.0/22',
    '104.16.0.0/13',
    '104.24.0.0/14',
    '108.162.192.0/18',
    '131.0.232.0/22',
    '141.101.64.0/18',
    '162.158.0.0/15',
    '172.64.0.0/13',
    '173.245.48.0/20',
    '188.114.96.0/20',
    '190.93.240.0/20',
    '197.234.240.0/22',
    '198.41.128.0/17',
];

const CLOUDFLARE_IPV6_CIDRS = [
    '2400:cb00::/32',
    '2405:8100::/32',
    '2405:b500::/32',
    '2606:4700::/32',
    '2803:f800::/32',
    '2a06:98c0::/29',
    '2c0f:f248::/32',
];

function hestia_is_cloudflare_ip(string $ip): bool
{
    if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
        return _hestia_ip_in_cidrs($ip, CLOUDFLARE_IPV4_CIDRS, false);
    }
    if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) {
        return _hestia_ip_in_cidrs($ip, CLOUDFLARE_IPV6_CIDRS, true);
    }
    return false;
}

function _hestia_ip_in_cidrs(string $ip, array $cidrs, bool $ipv6): bool
{
    $ip_long = $ipv6 ? inet_pton($ip) : pack('N', ip2long($ip));
    foreach ($cidrs as $cidr) {
        [$base, $prefix] = explode('/', $cidr);
        $base_long = $ipv6 ? inet_pton($base) : pack('N', ip2long($base));
        $bits = (int) $prefix;
        $total_bits = $ipv6 ? 128 : 32;
        $mask_bits = $total_bits - $bits;
        // Build mask: $bits ones followed by $mask_bits zeros
        $mask = '';
        for ($byte = 0; $byte < $total_bits / 8; $byte++) {
            $byte_mask = 0;
            for ($bit = 7; $bit >= 0; $bit--) {
                $global_bit = $byte * 8 + (7 - $bit);
                if ($global_bit < $bits) {
                    $byte_mask |= (1 << $bit);
                }
            }
            $mask .= chr($byte_mask);
        }
        if (($ip_long & $mask) === ($base_long & $mask)) {
            return true;
        }
    }
    return false;
}
