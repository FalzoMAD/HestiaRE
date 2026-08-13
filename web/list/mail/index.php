<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

$TAB = "MAIL";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Data & Render page
if (empty($_GET["domain"])) {
	$data = cli_json("h-list-mail-domains $user json");
	if ($_SESSION["userSortOrder"] == "name") {
		ksort($data);
	} else {
		$data = array_reverse($data, true);
	}

	render_page($user, $TAB, "list_mail");
} elseif (!empty($_GET["dns"])) {
	$data = array_reverse(cli_json("h-list-mail-domain " . $user . " " . quoteshellarg($_GET["domain"]) . " json"), true);
	$ips = array_reverse(cli_json("h-list-user-ips " . $user . " json"), true);
	$dkim = array_reverse(
		cli_json("h-list-mail-domain-dkim-dns " . $user . " " . quoteshellarg($_GET["domain"]) . " json"),
		true,
	);

	render_page($user, $TAB, "list_mail_dns");
} else {
	$data = cli_json("h-list-mail-accounts " . $user . " " . quoteshellarg($_GET["domain"]) . " json");
	if ($_SESSION["userSortOrder"] == "name") {
		ksort($data);
	} else {
		$data = array_reverse($data, true);
	}

	render_page($user, $TAB, "list_mail_acc");
}

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
