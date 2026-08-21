<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

$TAB = "BACKUP";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Data & Render page
if (empty($_GET["backup"])) {
	$data = cli_json("h-list-user-backups $user json");
	if ($_SESSION["userSortOrder"] == "name") {
		ksort($data);
	} else {
		$data = array_reverse($data, true);
	}
	render_page($user, $TAB, "list_backup");
} else {
	$data = array_reverse(cli_json("h-list-user-backup $user " . quoteshellarg($_GET["backup"]) . " json"), true);

	// Named on the consent control, so the choice says where a domain would land. A property of the
	// host, not of the archive - no probe needed.
	$default_php = cli_json("h-list-default-php json")[0] ?? "";

	render_page($user, $TAB, "list_backup_detail");
}

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
