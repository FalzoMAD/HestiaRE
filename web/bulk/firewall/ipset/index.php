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
verify_csrf($_POST);

if (empty($_POST["setname"])) {
	header("Location: /list/firewall/ipset/");
	exit();
}
if (empty($_POST["action"])) {
	header("Location: /list/firewall/ipset/");
	exit();
}

$setname = $_POST["setname"];
$action = $_POST["action"];
switch ($action) {
	case "delete":
		$cmd = "h-delete-firewall-ipset";
		break;
	default:
		header("Location: /list/firewall/ipset/");
		exit();
}

foreach ($setname as $value) {
	$v_name = quoteshellarg($value);
	exec(HESTIA_CMD . $cmd . " " . $v_name, $output, $return_var);
}

header("Location: /list/firewall/ipset/");
