<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

$TAB = "SEARCH";

$_SESSION["back"] = $_SERVER["REQUEST_URI"];

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check token
verify_csrf($_GET);

if (empty($_GET["u"])) {
	$_GET["u"] = "";
}
if (empty($_GET["q"])) {
	$_GET["q"] = "";
}
// Data
$q = quoteshellarg($_GET["q"]);
$u = quoteshellarg($_GET["u"]);

$output = [];
// An empty query would reach the h-search-* commands as an empty pattern, which is a grep usage
// error on stderr, not a result set. Render the empty page instead.
if ($_GET["q"] !== "") {
	if ($_SESSION["userContext"] === "admin" && $_SESSION["look"] == "") {
		if (!empty($_GET["u"])) {
			$user = $u;
			exec(
				HESTIA_CMD . "h-search-user-object " . $user . " " . $q . " json",
				$output,
				$return_var,
			);
		} else {
			exec(HESTIA_CMD . "h-search-object " . $q . " json", $output, $return_var);
		}
	} else {
		exec(HESTIA_CMD . "h-search-user-object " . $user . " " . $q . " json", $output, $return_var);
	}
}

$data = json_decode(implode("", $output), true);
// Empty query, or a search command that failed: either way the template iterates this, and a
// null there is a fatal rather than an empty result list (#578).
if (!is_array($data)) {
	$data = [];
}

// Render page
render_page($user, $TAB, "list_search");
