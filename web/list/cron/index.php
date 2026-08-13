<?php

$TAB = "CRON";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Data
$data = cli_json("h-list-cron-jobs $user json");
if ($_SESSION["userSortOrder"] == "name") {
	ksort($data);
} else {
	$data = array_reverse($data, true);
}

// Render page
render_page($user, $TAB, "list_cron");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
