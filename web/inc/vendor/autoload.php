<?php
// HestiaRE Build-Time-Vendor autoloader (replaces Composer-generated autoload).
// Packages: phpmailer/phpmailer 7.0.2, robthree/twofactorauth 3.0.3
// Generated manually — run `composer install --no-dev` in web/inc/ to regenerate
// if adding or upgrading packages.

spl_autoload_register(function (string $class): void {
    static $prefixes = [
        'PHPMailer\\PHPMailer\\' => __DIR__ . '/phpmailer/phpmailer/src/',
        'RobThree\\Auth\\'       => __DIR__ . '/robthree/twofactorauth/lib/',
    ];
    foreach ($prefixes as $prefix => $dir) {
        if (strncmp($class, $prefix, strlen($prefix)) !== 0) {
            continue;
        }
        $file = $dir . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
        if (is_file($file)) {
            require $file;
            return;
        }
    }
});
