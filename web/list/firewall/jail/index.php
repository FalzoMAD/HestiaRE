<?php
$TAB = "FIREWALL";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

// Data
exec(HESTIA_CMD . "h-list-firewall-jail json", $output, $return_var);
$data = json_decode(implode("", $output), true) ?? [];
unset($output);

// Render page
render_page($user, $TAB, "list_firewall_jail");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
