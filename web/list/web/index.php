<?php

$TAB = "WEB";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Data
$data = cli_json("h-list-web-domains " . $user . " 'json'");
if ($_SESSION["userSortOrder"] == "name") {
	ksort($data);
} else {
	$data = array_reverse($data, true);
}
$ips = cli_json("h-list-sys-ips json");

// Render page
render_page($user, $TAB, "list_web");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
