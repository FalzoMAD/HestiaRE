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

if (empty($_POST["ipchain"])) {
	header("Location: /list/firewall/banlist/");
	exit();
}
if (empty($_POST["action"])) {
	header("Location: /list/firewall/banlist/");
	exit();
}

$ipchain = $_POST["ipchain"];
$action = $_POST["action"];

if ($action !== "delete") {
	header("Location: /list/firewall/banlist/");
	exit();
}

// Each value is "source|ip|chain" - "|" not ":" because an IPv6 address contains colons, and the source
// picks the unban command (fail2ban banlist vs a CrowdSec cscli decision).
foreach ($ipchain as $value) {
	$parts = explode("|", $value, 3);
	if (count($parts) < 2) {
		continue;
	}
	$src = $parts[0];
	$v_ip = quoteshellarg($parts[1]);
	if ($src === "crowdsec") {
		exec(HESTIA_CMD . "h-delete-firewall-crowdsec-ban " . $v_ip, $output, $return_var);
	} else {
		$v_chain = quoteshellarg($parts[2] ?? "");
		exec(HESTIA_CMD . "h-delete-firewall-ban " . $v_ip . " " . $v_chain, $output, $return_var);
	}
}

header("Location: /list/firewall/banlist");
