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

// Route by source: a CrowdSec ban is a cscli decision, a fail2ban ban is a banlist.conf/chain entry.
$output = [];
$return_var = 0;
if (!empty($_GET["ip"]) && ($_GET["source"] ?? "") === "crowdsec") {
	$v_ip = quoteshellarg($_GET["ip"]);
	exec(HESTIA_CMD . "h-delete-firewall-crowdsec-ban " . $v_ip, $output, $return_var);
	check_return_code($return_var, $output);
} elseif (!empty($_GET["ip"]) && !empty($_GET["chain"])) {
	$v_ip = quoteshellarg($_GET["ip"]);
	$v_chain = quoteshellarg($_GET["chain"]);
	exec(HESTIA_CMD . "h-delete-firewall-ban " . $v_ip . " " . $v_chain, $output, $return_var);
	check_return_code($return_var, $output);
}
unset($output);

$back = $_SESSION["back"];
if (!empty($back)) {
	header("Location: " . $back);
	exit();
}

header("Location: /list/firewall/banlist/");
exit();
