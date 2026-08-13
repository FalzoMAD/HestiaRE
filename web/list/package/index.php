<?php

$TAB = "PACKAGE";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

// Data
$data = cli_json("h-list-user-packages json");
if ($_SESSION["userSortOrder"] == "name") {
	ksort($data);
} else {
	$data = array_reverse($data, true);
}

// Render page
render_page($user, $TAB, "list_packages");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
