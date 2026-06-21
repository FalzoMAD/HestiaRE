<?php
declare(strict_types=1);
/**
 * HestiaQRCode — single-file pure-PHP SVG QR code generator.
 * Byte mode, ECC Level M, Versions 1-10 (max 216 bytes input).
 * Returns data:image/svg+xml;base64 URI.
 * No dependencies. No PHP extensions required.
 */

function hestia_qrcode_data_uri(string $text, int $scale = 6): string
{
    return 'data:image/svg+xml;base64,' . base64_encode(_hq_svg($text, $scale));
}

// ─── SVG renderer ────────────────────────────────────────────────────────────

function _hq_svg(string $text, int $scale): string
{
    $matrix = _hq_encode($text);
    $n      = count($matrix);
    $quiet  = 4;
    $dim    = ($n + 2 * $quiet) * $scale;
    $rects  = '';
    for ($r = 0; $r < $n; $r++) {
        for ($c = 0; $c < $n; $c++) {
            if ($matrix[$r][$c]) {
                $x = ($quiet + $c) * $scale;
                $y = ($quiet + $r) * $scale;
                $rects .= "<rect x=\"$x\" y=\"$y\" width=\"$scale\" height=\"$scale\"/>";
            }
        }
    }
    return '<?xml version="1.0" encoding="UTF-8"?>'
        . "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$dim\" height=\"$dim\">"
        . "<rect width=\"$dim\" height=\"$dim\" fill=\"#fff\"/>"
        . "<g fill=\"#000\">$rects</g></svg>";
}

// ─── Version / capacity tables (ECC Level M, byte mode) ──────────────────────

// max bytes per version
const _HQ_CAP = [1=>16,2=>28,3=>44,4=>64,5=>86,6=>108,7=>124,8=>154,9=>182,10=>216];

// [ec_cw_per_block, [[count, data_cw_per_block], ...]]
const _HQ_BLK = [
    1  => [10, [[1, 16]]],
    2  => [16, [[1, 28]]],
    3  => [26, [[1, 44]]],
    4  => [18, [[2, 32]]],
    5  => [24, [[2, 43]]],
    6  => [16, [[4, 27]]],
    7  => [18, [[4, 31]]],
    8  => [22, [[2, 38], [2, 39]]],
    9  => [22, [[3, 36], [2, 37]]],
    10 => [26, [[4, 43], [1, 44]]],
];

// alignment pattern center coordinates (empty = version 1)
const _HQ_ALIGN = [
    1=>[], 2=>[6,18], 3=>[6,22], 4=>[6,26], 5=>[6,30],
    6=>[6,34], 7=>[6,22,38], 8=>[6,24,42], 9=>[6,26,46], 10=>[6,28,50],
];

// ─── Top-level encoder ───────────────────────────────────────────────────────

function _hq_encode(string $text): array
{
    $len = strlen($text);
    $v   = 0;
    foreach (_HQ_CAP as $ver => $cap) {
        if ($len <= $cap) { $v = $ver; break; }
    }
    if ($v === 0) {
        throw new \OverflowException("Input too long for QR code (max 216 bytes)");
    }

    $codewords = _hq_add_ecc(_hq_data_codewords($text, $v), $v);

    $bits = [];
    foreach ($codewords as $byte) {
        for ($i = 7; $i >= 0; $i--) {
            $bits[] = ($byte >> $i) & 1;
        }
    }

    $n         = 4 * $v + 17;
    $bestScore = PHP_INT_MAX;
    $best      = null;
    for ($mask = 0; $mask < 8; $mask++) {
        $m     = _hq_matrix($v, $n, $bits, $mask);
        $score = _hq_penalty($m, $n);
        if ($score < $bestScore) { $bestScore = $score; $best = $m; }
    }
    return $best;
}

// ─── Data codeword stream (byte mode) ────────────────────────────────────────

function _hq_data_codewords(string $text, int $v): array
{
    $cap   = _HQ_CAP[$v];
    $bytes = array_values(unpack('C*', $text));
    $len   = count($bytes);

    $bits = [0, 1, 0, 0]; // mode indicator: byte = 0100
    for ($i = 7; $i >= 0; $i--) $bits[] = ($len >> $i) & 1; // 8-bit char count
    foreach ($bytes as $b) {
        for ($i = 7; $i >= 0; $i--) $bits[] = ($b >> $i) & 1;
    }

    $total = $cap * 8;
    $term  = min(4, $total - count($bits));
    for ($i = 0; $i < $term; $i++) $bits[] = 0;
    while (count($bits) % 8) $bits[] = 0;

    $pi = 0;
    $pad = [0xEC, 0x11];
    while (count($bits) < $total) {
        $pb = $pad[$pi++ % 2];
        for ($i = 7; $i >= 0; $i--) $bits[] = ($pb >> $i) & 1;
    }

    $cw = [];
    for ($i = 0; $i < count($bits); $i += 8) {
        $b = 0;
        for ($j = 0; $j < 8; $j++) $b = ($b << 1) | $bits[$i + $j];
        $cw[] = $b;
    }
    return $cw;
}

// ─── Reed-Solomon error correction ───────────────────────────────────────────

function _hq_gf(): array
{
    static $t = null;
    if ($t !== null) return $t;
    $exp = array_fill(0, 512, 0);
    $log = array_fill(0, 256, 0);
    $x   = 1;
    for ($i = 0; $i < 255; $i++) {
        $exp[$i] = $x;
        $log[$x] = $i;
        $x = ($x << 1) ^ ($x & 0x80 ? 0x11D : 0);
    }
    for ($i = 255; $i < 512; $i++) $exp[$i] = $exp[$i - 255];
    return $t = [$exp, $log];
}

function _hq_gf_mul(int $a, int $b): int
{
    if ($a === 0 || $b === 0) return 0;
    [$exp, $log] = _hq_gf();
    return $exp[$log[$a] + $log[$b]];
}

function _hq_rs_gen(int $n): array // monic generator polynomial, highest degree first
{
    [$exp] = _hq_gf();
    $g = [1];
    for ($i = 0; $i < $n; $i++) {
        $ai = $exp[$i];
        $ng = array_fill(0, count($g) + 1, 0);
        foreach ($g as $j => $c) {
            $ng[$j]     ^= $c;
            $ng[$j + 1] ^= _hq_gf_mul($c, $ai);
        }
        $g = $ng;
    }
    return $g; // g[0]=1 (leading), g[1..n] = remaining coefficients
}

function _hq_rs(array $msg, int $ecLen): array
{
    $gen  = array_slice(_hq_rs_gen($ecLen), 1); // drop leading 1
    $r    = array_merge($msg, array_fill(0, $ecLen, 0));
    $mlen = count($msg);
    for ($i = 0; $i < $mlen; $i++) {
        if ($r[$i] === 0) continue;
        $c = $r[$i];
        for ($j = 0; $j < $ecLen; $j++) {
            $r[$i + 1 + $j] ^= _hq_gf_mul($c, $gen[$j]);
        }
    }
    return array_slice($r, $mlen);
}

function _hq_add_ecc(array $data, int $v): array
{
    [$ecLen, $groups] = _HQ_BLK[$v];

    $blocks   = [];
    $ecBlocks = [];
    $di       = 0;
    foreach ($groups as [$cnt, $dcw]) {
        for ($b = 0; $b < $cnt; $b++) {
            $block      = array_slice($data, $di, $dcw);
            $blocks[]   = $block;
            $ecBlocks[] = _hq_rs($block, $ecLen);
            $di        += $dcw;
        }
    }

    $result = [];
    $maxDcw = max(array_map('count', $blocks));
    for ($i = 0; $i < $maxDcw; $i++) {
        foreach ($blocks as $blk) {
            if (isset($blk[$i])) $result[] = $blk[$i];
        }
    }
    for ($i = 0; $i < $ecLen; $i++) {
        foreach ($ecBlocks as $ec) {
            $result[] = $ec[$i];
        }
    }
    return $result;
}

// ─── Matrix builder ───────────────────────────────────────────────────────────

function _hq_matrix(int $v, int $n, array $bits, int $mask): array
{
    $m    = array_fill(0, $n, array_fill(0, $n, 0));
    $rsv  = array_fill(0, $n, array_fill(0, $n, false));

    _hq_finder($m, $rsv, 0, 0);
    _hq_finder($m, $rsv, 0, $n - 7);
    _hq_finder($m, $rsv, $n - 7, 0);
    _hq_timing($m, $rsv, $n);
    _hq_alignment($m, $rsv, $v, $n);

    // Dark module at row 4v+9 (1-indexed) = 4v+8 (0-indexed) = n-9
    $m[$n - 9][8] = 1;
    $rsv[$n - 9][8] = true;

    // Reserve format info areas
    foreach (_hq_fmt_positions($n) as [$r, $c]) {
        $rsv[$r][$c] = true;
    }

    _hq_place_data($m, $rsv, $bits, $n);
    _hq_apply_mask($m, $rsv, $mask, $n);
    _hq_write_format($m, $mask, $n);

    return $m;
}

function _hq_finder(array &$m, array &$rsv, int $row, int $col): void
{
    static $pat = [[1,1,1,1,1,1,1],[1,0,0,0,0,0,1],[1,0,1,1,1,0,1],
                   [1,0,1,1,1,0,1],[1,0,1,1,1,0,1],[1,0,0,0,0,0,1],[1,1,1,1,1,1,1]];
    $n = count($m);
    for ($dr = -1; $dr <= 7; $dr++) {
        for ($dc = -1; $dc <= 7; $dc++) {
            $r = $row + $dr; $c = $col + $dc;
            if ($r < 0 || $r >= $n || $c < 0 || $c >= $n) continue;
            $m[$r][$c]   = ($dr >= 0 && $dr < 7 && $dc >= 0 && $dc < 7) ? $pat[$dr][$dc] : 0;
            $rsv[$r][$c] = true;
        }
    }
}

function _hq_timing(array &$m, array &$rsv, int $n): void
{
    for ($i = 8; $i < $n - 8; $i++) {
        $val = ($i % 2 === 0) ? 1 : 0;
        $m[6][$i] = $m[$i][6] = $val;
        $rsv[6][$i] = $rsv[$i][6] = true;
    }
}

function _hq_alignment(array &$m, array &$rsv, int $v, int $n): void
{
    $pos = _HQ_ALIGN[$v];
    $cnt = count($pos);
    for ($i = 0; $i < $cnt; $i++) {
        for ($j = 0; $j < $cnt; $j++) {
            $r = $pos[$i]; $c = $pos[$j];
            // Skip if overlaps finder pattern area
            if ($rsv[$r][$c]) continue;
            for ($dr = -2; $dr <= 2; $dr++) {
                for ($dc = -2; $dc <= 2; $dc++) {
                    $dark = ($dr === -2 || $dr === 2 || $dc === -2 || $dc === 2
                          || ($dr === 0 && $dc === 0)) ? 1 : 0;
                    $m[$r+$dr][$c+$dc]   = $dark;
                    $rsv[$r+$dr][$c+$dc] = true;
                }
            }
        }
    }
}

function _hq_fmt_positions(int $n): array
{
    // Format info copy 1: around top-left finder
    $pos = [
        [8,0],[8,1],[8,2],[8,3],[8,4],[8,5],[8,7],[8,8],
        [7,8],[5,8],[4,8],[3,8],[2,8],[1,8],[0,8],
    ];
    // Format info copy 2: bit 0 at (n-1,8) ... bit 6 at (n-7,8), bit 7 at (8,n-8) ... bit 14 at (8,n-1)
    for ($i = 0; $i < 7; $i++) $pos[] = [$n - 1 - $i, 8];
    for ($i = 0; $i < 8; $i++) $pos[] = [8, $n - 8 + $i];
    return $pos;
}

function _hq_place_data(array &$m, array $rsv, array $bits, int $n): void
{
    $idx = 0;
    $dir = -1;
    $r   = $n - 1;

    for ($col = $n - 1; $col >= 1; $col -= 2) {
        if ($col === 6) $col--;
        for ($step = 0; $step < $n; $step++) {
            foreach ([0, 1] as $dc) {
                $c = $col - $dc;
                if (!$rsv[$r][$c]) {
                    $m[$r][$c] = ($idx < count($bits)) ? $bits[$idx++] : 0;
                }
            }
            $r += $dir;
        }
        $r  -= $dir; // undo overshoot
        $dir = -$dir;
    }
}

function _hq_apply_mask(array &$m, array $rsv, int $mask, int $n): void
{
    for ($r = 0; $r < $n; $r++) {
        for ($c = 0; $c < $n; $c++) {
            if ($rsv[$r][$c]) continue;
            $flip = match ($mask) {
                0 => (($r + $c) % 2) === 0,
                1 => ($r % 2) === 0,
                2 => ($c % 3) === 0,
                3 => (($r + $c) % 3) === 0,
                4 => ((intdiv($r, 2) + intdiv($c, 3)) % 2) === 0,
                5 => (($r * $c) % 2 + ($r * $c) % 3) === 0,
                6 => ((($r * $c) % 2 + ($r * $c) % 3) % 2) === 0,
                7 => ((($r + $c) % 2 + ($r * $c) % 3) % 2) === 0,
            };
            if ($flip) $m[$r][$c] ^= 1;
        }
    }
}

function _hq_format_bits(int $mask): int
{
    $data = (0b00 << 3) | $mask; // ECC Level M = 00 (L=01, M=00, Q=11, H=10)
    $gen  = 0b10100110111;
    $rem  = $data << 10;
    for ($i = 14; $i >= 10; $i--) {
        if (($rem >> $i) & 1) $rem ^= ($gen << ($i - 10));
    }
    return (($data << 10) | ($rem & 0x3FF)) ^ 0x5412;
}

function _hq_write_format(array &$m, int $mask, int $n): void
{
    $fmt = _hq_format_bits($mask);
    $pos = _hq_fmt_positions($n);
    for ($i = 0; $i < 15; $i++) {
        $bit = ($fmt >> (14 - $i)) & 1;
        [$r, $c] = $pos[$i];
        $m[$r][$c] = $bit;
        $bit2 = ($fmt >> $i) & 1;
        [$r2, $c2] = $pos[15 + $i];
        $m[$r2][$c2] = $bit2;
    }
}

// ─── Mask penalty scoring ─────────────────────────────────────────────────────

function _hq_penalty(array $m, int $n): int
{
    $score = 0;

    // Rule 1: runs of 5+ same color in rows and columns
    foreach ([true, false] as $row_mode) {
        for ($i = 0; $i < $n; $i++) {
            $run = 1;
            $prev = $row_mode ? $m[$i][0] : $m[0][$i];
            for ($j = 1; $j < $n; $j++) {
                $cur = $row_mode ? $m[$i][$j] : $m[$j][$i];
                if ($cur === $prev) {
                    $run++;
                    if ($run === 5) $score += 3;
                    elseif ($run > 5) $score++;
                } else {
                    $run = 1; $prev = $cur;
                }
            }
        }
    }

    // Rule 2: 2×2 blocks of same color
    for ($r = 0; $r < $n - 1; $r++) {
        for ($c = 0; $c < $n - 1; $c++) {
            $v = $m[$r][$c];
            if ($v === $m[$r][$c+1] && $v === $m[$r+1][$c] && $v === $m[$r+1][$c+1]) {
                $score += 3;
            }
        }
    }

    // Rule 3: finder-like patterns
    $p1 = [1,0,1,1,1,0,1,0,0,0,0];
    $p2 = [0,0,0,0,1,0,1,1,1,0,1];
    for ($r = 0; $r < $n; $r++) {
        for ($c = 0; $c <= $n - 11; $c++) {
            $match1 = $match2 = true;
            for ($k = 0; $k < 11; $k++) {
                if ($m[$r][$c+$k] !== $p1[$k]) $match1 = false;
                if ($m[$r][$c+$k] !== $p2[$k]) $match2 = false;
            }
            if ($match1 || $match2) $score += 40;
        }
    }
    for ($c = 0; $c < $n; $c++) {
        for ($r = 0; $r <= $n - 11; $r++) {
            $match1 = $match2 = true;
            for ($k = 0; $k < 11; $k++) {
                if ($m[$r+$k][$c] !== $p1[$k]) $match1 = false;
                if ($m[$r+$k][$c] !== $p2[$k]) $match2 = false;
            }
            if ($match1 || $match2) $score += 40;
        }
    }

    // Rule 4: proportion of dark modules
    $dark = 0;
    for ($r = 0; $r < $n; $r++) {
        $dark += array_sum($m[$r]);
    }
    $pct  = intdiv($dark * 100, $n * $n);
    $prev = intdiv($pct, 5) * 5;
    $next = $prev + 5;
    $score += min(abs($prev - 50), abs($next - 50)) * 2;

    return $score;
}
