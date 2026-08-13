<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

$TAB = "STATS";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Data
if ($_SESSION["userContext"] === "admin" && $_SESSION["look"] == "") {
	if (empty($_GET["user"])) {
		$data = array_reverse(cli_json("h-list-users-stats json"), true);
	} else {
		$v_user = quoteshellarg($_GET["user"]);
		$data = array_reverse(cli_json("h-list-user-stats $v_user json"), true);
	}

	exec(HESTIA_CMD . "h-list-sys-users 'json'", $output, $return_var);
	$users = json_decode(implode("", $output), true);
	unset($output);
} else {
	$data = array_reverse(cli_json("h-list-user-stats $user json"), true);
}

// Render page
render_page($user, $TAB, "list_stats");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
