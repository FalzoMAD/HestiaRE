<?php

require_once __DIR__ . '/../lib/totp.php';
require_once __DIR__ . '/../lib/qrcode.php';

$secret = hestia_totp_secret(160);
$otpUri = hestia_totp_uri(gethostname(), $secret, 'Hestia Control Panel');
$qrcode = hestia_qrcode_data_uri($otpUri);

echo $secret . '-' . $qrcode;
