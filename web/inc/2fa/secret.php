<?php

use RobThree\Auth\TwoFactorAuth;

require_once __DIR__ . "/../vendor/autoload.php";
require_once __DIR__ . "/../lib/qrcode.php";

$tfa = new TwoFactorAuth(issuer: "Hestia Control Panel");
$secret = $tfa->createSecret(160);

$otpUri = $tfa->getQRText(gethostname(), $secret);
$qrcode = hestia_qrcode_data_uri($otpUri);

echo $secret . "-" . $qrcode;
