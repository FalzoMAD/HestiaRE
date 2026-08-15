<?php

$_ENV["TACHYON_INCLUDE_AS_API"] = true;
require_once "/var/lib/tachyon/index.php";

$oConfig = \Tachyon\Api::Config();

// Change default login data / key
$oConfig->Set("security", "admin_login", $argv[1]);
$oConfig->Set("security", "admin_panel_key", $argv[2]);
$newPassword = new \Tachyon\Util\SensitiveString($argv[3]);
$oConfig->SetPassword($newPassword);

// Allow Contacts to be saved in database
$oConfig->Set("contacts", "enable", "On");
$oConfig->Set("contacts", "allow_sync", "On");
$oConfig->Set("contacts", "type", "mysql");
$oConfig->Set("contacts", "pdo_dsn", "mysql:host=127.0.0.1;port=3306;dbname=tachyon");
$oConfig->Set("contacts", "pdo_user", "tachyon");
$oConfig->Set("contacts", "pdo_password", $argv[4]);

// Failed-login logging for the fail2ban webmail jail. auth_logging_filename has no {date} token on
// purpose: fail2ban expands a logpath glob once at jail start, so a per-day file would leave the jail
// blind after midnight. path is pinned to a stable location instead of the deep data-dir default, so the
// jail and logrotate have a fixed target. http_client_ip_check_proxy makes {request:ip} read a proxy
// header; the webmail vhost sets Client-IP to the real client (X-Forwarded-For is clobbered downstream).
$oConfig->Set("logs", "auth_logging", "On");
$oConfig->Set("logs", "auth_logging_filename", "fail2ban/auth.txt");
$oConfig->Set("logs", "path", "/var/log/tachyon");
$oConfig->Set("labs", "http_client_ip_check_proxy", true);

// Plugins
$oConfig->Set("plugins", "enable", "On");

\Tachyon\Util\Repository::installPackage("plugin", "change-password");
\Tachyon\Util\Repository::installPackage("plugin", "change-password-hestia");

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
					// $argv[5] = $BACKEND_PORT - NOT $argv[4], which is the DB
					// password (that off-by-one shipped the DB password as the
					// panel port and broke password changes from the webmailer, #234)
					"hestia_port" => $argv[5],
				],
			],
			JSON_PRETTY_PRINT,
		),
	);
}
\Tachyon\Util\Repository::enablePackage("change-password");

\Tachyon\Util\Repository::installPackage("plugin", "add-x-originating-ip-header");
\Tachyon\Util\Repository::enablePackage("add-x-originating-ip-header");
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
