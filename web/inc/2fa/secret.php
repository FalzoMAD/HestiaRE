<?php

use RobThree\Auth\TwoFactorAuth;
use RobThree\Auth\Providers\Qr\SvgQRCodeProvider;

require_once __DIR__ . "/../vendor/autoload.php";
$tfa = new TwoFactorAuth(issuer: "Hestia Control Panel", qrcodeprovider: new SvgQRCodeProvider());

$secret = $tfa->createSecret(160); // Though the default is an 80 bits secret (for backwards compatibility reasons) we recommend creating 160+ bits secrets (see RFC 4226 - Algorithm Requirements)
$qrcode = $tfa->getQRCodeImageAsDataUri(gethostname(), $secret);

echo $secret . "-" . $qrcode;
