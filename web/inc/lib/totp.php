<?php
declare(strict_types=1);
/**
 * HestiaTOTP — single-file pure-PHP TOTP implementation.
 * RFC 6238 (TOTP) + RFC 4226 (HOTP), SHA-1, 6 digits, 30 s period.
 * No dependencies. Requires only PHP built-ins: random_bytes, hash_hmac, hash_equals.
 */

function hestia_totp_secret(int $bits = 160): string
{
    $bytes = (int)ceil($bits / 5); // 5 usable bits per byte after masking to 0-31
    $rnd = random_bytes($bytes);
    $b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    $out = '';
    for ($i = 0; $i < $bytes; $i++) {
        $out .= $b32[ord($rnd[$i]) & 31];
    }
    return $out;
}

function hestia_totp_uri(string $label, string $secret, string $issuer): string
{
    return 'otpauth://totp/' . rawurlencode($label)
        . '?secret='    . rawurlencode($secret)
        . '&issuer='    . rawurlencode($issuer)
        . '&period=30&algorithm=SHA1&digits=6';
}

function hestia_totp_verify(string $secret, string $code, int $discrepancy = 1): bool
{
    $key = _hestia_totp_b32decode($secret);
    $now = (int)floor(time() / 30);
    $matched = 0;
    // Iterate all windows even after a match to avoid timing side-channels
    for ($i = -$discrepancy; $i <= $discrepancy; $i++) {
        $slot = $now + $i;
        $hmac = hash_hmac('sha1', pack('J', $slot), $key, true);
        $offset = ord($hmac[19]) & 0x0F;
        $value  = unpack('N', substr($hmac, $offset, 4))[1] & 0x7FFFFFFF;
        $totp   = str_pad((string)($value % 1_000_000), 6, '0', STR_PAD_LEFT);
        if (hash_equals($totp, $code)) $matched = $slot;
    }
    return $matched > 0;
}

function _hestia_totp_b32decode(string $secret): string
{
    static $lookup = null;
    if ($lookup === null) {
        $lookup = array_flip(str_split('ABCDEFGHIJKLMNOPQRSTUVWXYZ234567='));
    }
    $bits = '';
    foreach (str_split(strtoupper($secret)) as $c) {
        if ($c !== '=') {
            $bits .= str_pad(decbin($lookup[$c]), 5, '0', STR_PAD_LEFT);
        }
    }
    $key = '';
    for ($i = 0; $i + 8 <= strlen($bits); $i += 8) {
        $key .= chr(bindec(substr($bits, $i, 8)));
    }
    return $key;
}
