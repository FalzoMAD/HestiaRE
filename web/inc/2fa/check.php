<?php

require_once __DIR__ . '/../lib/totp.php';

if (isset($argv[1]) && isset($argv[2])) {
	$secret = $argv[1];
	$token  = $argv[2];
} elseif (isset($_GET['secret']) && isset($_GET['token'])) {
	$secret = htmlspecialchars($_GET['secret']);
	$token  = htmlspecialchars($_GET['token']);
} else {
	echo 'ERROR: Secret or Token is not set as argument!';
	exit();
}

if (hestia_totp_verify($secret, $token)) {
	echo 'ok';
}
