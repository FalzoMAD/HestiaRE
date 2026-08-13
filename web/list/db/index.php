<?php

$TAB = "DB";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Data
$data = cli_json("h-list-databases $user json");
if ($_SESSION["userSortOrder"] == "name") {
	ksort($data);
} else {
	$data = array_reverse($data, true);
}

// Render page
render_page($user, $TAB, "list_db");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
