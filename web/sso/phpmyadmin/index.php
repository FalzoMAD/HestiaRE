<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check token
verify_csrf($_GET);

// SSO must be enabled (PHPMYADMIN_KEY acts as the enabled flag)
if (empty($_SESSION["PHPMYADMIN_KEY"])) {
	header("Location: /list/db/");
	exit();
}

$database = quoteshellarg($_GET["database"] ?? "");
$client_ip = quoteshellarg($_SERVER["REMOTE_ADDR"]);

// Creates a temp DB user and a one-time handoff file for hestia-sso.php
// in the phpMyAdmin webroot; prints the token (see h-add-database-sso-token).
exec(
	HESTIA_CMD . "h-add-database-sso-token " . $user . " " . $database . " " . $client_ip,
	$output,
	$return_var,
);

if ($return_var != 0 || empty($output[0]) || !preg_match('/^[a-f0-9]{64}$/', $output[0])) {
	$_SESSION["error_msg"] = _("Unable to open phpMyAdmin session");
	header("Location: /list/db/");
	exit();
}

$pma_alias = !empty($_SESSION["DB_PMA_ALIAS"]) ? $_SESSION["DB_PMA_ALIAS"] : "phpmyadmin";
header("Location: /" . $pma_alias . "/hestia-sso.php?token=" . $output[0]);
exit();
