<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check token
verify_csrf($_POST);

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

if (empty($_POST["ip"]) || empty($_POST["action"])) {
	header("Location: /list/firewall/exclude/");
	exit();
}

switch ($_POST["action"]) {
	case "delete":
		$cmd = "h-delete-firewall-exclude";
		break;
	default:
		header("Location: /list/firewall/exclude/");
		exit();
}

foreach ($_POST["ip"] as $ip) {
	$v_ip = quoteshellarg($ip);
	exec(HESTIA_CMD . $cmd . " " . $v_ip, $output, $return_var);
	unset($output);
}

header("Location: /list/firewall/exclude/");
exit();
