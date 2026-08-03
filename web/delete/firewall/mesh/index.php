<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

// Check token
verify_csrf($_GET);

if (!empty($_GET["peer"])) {
	exec(HESTIA_CMD . "h-delete-sys-crowdsec-peer " . quoteshellarg($_GET["peer"]), $output, $return_var);
	check_return_code($return_var, $output);
	unset($output);
}

header("Location: /list/firewall/mesh/");
exit();
