<?php
// Inlined from hestiacp/phpquoteshellarg v1.1.0 (The Unlicense / public domain)
// Source: https://github.com/hestiacp/phpquoteshellarg
// Reason: PHP's native escapeshellarg() corrupts UTF-8 characters (e.g. æøå)
// in certain locale configurations. This implementation handles Unix correctly
// by using single-quote wrapping without locale-dependent character conversion.
declare(strict_types=1);
namespace Hestiacp\quoteshellarg;

function quoteshellarg(string|int|float $arg): string
{
    if (\is_float($arg)) {
        return \escapeshellarg(\sprintf('%.17g', $arg));
    }
    if (\is_int($arg)) {
        return \escapeshellarg((string) $arg);
    }
    static $isUnix = null;
    if ($isUnix === null) {
        $isUnix = \in_array(PHP_OS_FAMILY, array('Linux', 'BSD', 'Darwin', 'Solaris'), true) || PHP_OS === 'CYGWIN';
    }
    if ($isUnix) {
        if (false !== \strpos($arg, "\x00")) {
            throw new \UnexpectedValueException('unix shell arguments cannot contain null bytes!');
        }
        return "'" . \strtr($arg, array("'" => "'\\''")) . "'";
    }
    return \escapeshellarg($arg);
}
