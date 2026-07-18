<?php

$_ENV["SNAPPYMAIL_INCLUDE_AS_API"] = true;
require_once "/var/lib/snappymail/index.php";

$oConfig = \RainLoop\Api::Config();

// Change default login data / key
$oConfig->Set("security", "admin_login", $argv[1]);
$oConfig->Set("security", "admin_panel_key", $argv[2]);
$newPassword = new \SnappyMail\SensitiveString($argv[3]);
$oConfig->SetPassword($newPassword);

// Allow Contacts to be saved in database
$oConfig->Set("contacts", "enable", "On");
$oConfig->Set("contacts", "allow_sync", "On");
$oConfig->Set("contacts", "type", "mysql");
$oConfig->Set("contacts", "pdo_dsn", "mysql:host=127.0.0.1;port=3306;dbname=snappymail");
$oConfig->Set("contacts", "pdo_user", "snappymail");
$oConfig->Set("contacts", "pdo_password", $argv[4]);

// Plugins
$oConfig->Set("plugins", "enable", "On");

\SnappyMail\Repository::installPackage("plugin", "change-password");
\SnappyMail\Repository::installPackage("plugin", "change-password-hestia");

$sFile = APP_PRIVATE_DATA . "configs/plugin-change-password.json";
if (!file_exists($sFile)) {
	file_put_contents(
		"$sFile",
		json_encode(
			[
				"plugin" => [
					"pass_min_length" => 8,
					"pass_min_strength" => 60,
					"driver_hestia_enabled" => true,
					"driver_hestia_allowed_emails" => "*",
					"hestia_host" => gethostname(),
					// $argv[5] = $BACKEND_PORT — NOT $argv[4], which is the DB
					// password (that off-by-one shipped the DB password as the
					// panel port and broke password changes from SnappyMail, #234)
					"hestia_port" => $argv[5],
				],
			],
			JSON_PRETTY_PRINT,
		),
	);
}
\SnappyMail\Repository::enablePackage("change-password");

\SnappyMail\Repository::installPackage("plugin", "add-x-originating-ip-header");
\SnappyMail\Repository::enablePackage("add-x-originating-ip-header");
$sFile = APP_PRIVATE_DATA . "configs/plugin-add-x-originating-ip-header.json";
if (!file_exists($sFile)) {
	file_put_contents(
		"$sFile",
		json_encode(
			[
				"plugin" => [
					"check_proxy" => true,
				],
			],
			JSON_PRETTY_PRINT,
		),
	);
}

$oConfig->Save();

$sFile = APP_PRIVATE_DATA . "domains/hestia.json";
if (!file_exists($sFile)) {
	// file_get_contents, not the bare path: json_decode(<path string>) returns
	// null, so hestia.json used to contain ONLY the two shortLogin keys instead
	// of a full clone of default.json (#234).
	$config = json_decode(file_get_contents(APP_PRIVATE_DATA . "domains/default.json"), true);
	if (!is_array($config)) {
		$config = [];
	}
	$config["IMAP"]["shortLogin"] = true;
	$config["SMTP"]["shortLogin"] = true;
	file_put_contents($sFile, json_encode($config, JSON_PRETTY_PRINT));
}
