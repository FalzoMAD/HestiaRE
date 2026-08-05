<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
$TAB = "FIREWALL";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

// Check POST request
if (!empty($_POST["ok"])) {
	// Check token
	verify_csrf($_POST);

	// Check empty fields
	if (empty($_POST["v_ip"])) {
		$_SESSION["error_msg"] = sprintf(_('Field "%s" can not be blank.'), _("IP Address"));
	}

	// Protect input
	$v_ip = quoteshellarg($_POST["v_ip"]);

	// Add address to the whitelist
	if (empty($_SESSION["error_msg"])) {
		exec(HESTIA_CMD . "h-add-firewall-exclude " . $v_ip, $output, $return_var);
		check_return_code($return_var, $output);
		unset($output);
	}

	// Flush field values on success
	if (empty($_SESSION["error_msg"])) {
		$_SESSION["ok_msg"] = _("IP address has been added to the whitelist successfully.");
		unset($v_ip);
	}
}

if (empty($v_ip)) {
	$v_ip = "";
}

// Render
render_page($user, $TAB, "add_firewall_exclude");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
