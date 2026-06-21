<?php

use RobThree\Auth\TwoFactorAuth;
use chillerlan\QRCode\QRCode;
use chillerlan\QRCode\QROptions;
use chillerlan\QRCode\Output\QROutputInterface;

require_once __DIR__ . "/../vendor/autoload.php";

$tfa = new TwoFactorAuth(issuer: "Hestia Control Panel");
$secret = $tfa->createSecret(160); // Though the default is an 80 bits secret (for backwards compatibility reasons) we recommend creating 160+ bits secrets (see RFC 4226 - Algorithm Requirements)

$otpUri = $tfa->getQRText(gethostname(), $secret);
$options = new QROptions(['outputType' => QROutputInterface::MARKUP_SVG]);
$qrcode = (new QRCode($options))->render($otpUri);

echo $secret . "-" . $qrcode;
