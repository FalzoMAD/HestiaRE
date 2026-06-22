<?php
declare (strict_types = 1);
namespace Hestiacp\quoteshellarg;

/**
 * quotes shell arguments
 * (doing a better job than escapeshellarg)
 *
 * @param string|int|float $arg
 * @throws UnexpectedValueException if $arg contains null bytes
 * @return string
 */

function quoteshellarg(string | int | float $arg): string
{
    if (\is_float($arg)) {
        // 17: >The 53-bit significand precision gives from 15 to 17 significant decimal digits precision.
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
        // PHP's built-in escapeshellarg() for unix is kindof garbage: https://3v4l.org/Hkv7h
        // corrupting-or-stripping UTF-8 unicode characters like "æøå" and non-printable characters like "\x01",
        // both of which are fully legal in unix shell arguments.
        // In single-quoted-unix-shell-arguments there are only 2 bytes that needs special attention: \x00 and \x27
        if (false !== \strpos($arg, "\x00")) {
            throw new \UnexpectedValueException('unix shell arguments cannot contain null bytes!');
        }
        return "'" . \strtr($arg, array("'" => "'\\''")) . "'";
    }
    // todo: quoteshellarg for windows? it's a nightmare though: https://docs.microsoft.com/en-us/archive/blogs/twistylittlepassagesallalike/everyone-quotes-command-line-arguments-the-wrong-way
    // fallback to php's builtin escapeshellarg
    return \escapeshellarg($arg);
}
