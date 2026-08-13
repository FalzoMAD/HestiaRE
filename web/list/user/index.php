<?php

$TAB = "USER";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Do not show the users list for regular users
if ($_SESSION["userContext"] === "user") {
	header("Location: /login/");
	exit();
}

// Do not show the users list if user is impersonating another user
if (!empty($_SESSION["look"])) {
	header("Location: /login/");
	exit();
}

// Data
$data = cli_json($_SESSION["userContext"] === "admin" ? "h-list-users json" : "h-list-user " . $user . " json");
if ($_SESSION["userSortOrder"] == "name") {
	ksort($data);
} else {
	$data = array_reverse($data, true);
}

// Render page
render_page($user, $TAB, "list_user");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
