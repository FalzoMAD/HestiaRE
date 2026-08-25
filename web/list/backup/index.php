<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

$TAB = "BACKUP";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// One tab, branching by mode (#217 stage 5): BACKUPS_MODE is the single truth about a customer's
// mode, so the Backups tab shows what that customer actually has instead of hiding snapshots behind
// a second button. The snapshot views keep their own URLs for links that already exist.
// ?archives=1 is the way back: a restic customer still has the archives from before the switch and
// their exports, and both live in this list - without the escape the button here would bounce
// straight back into the redirect.
//
// Read here, not from $panel: that array is built inside render_page, so at this point it does not
// exist yet and every customer would look like an archive customer. Measured over HTTP - the tab
// answered 200 with no redirect for a restic customer.
$backup_mode = cli_json("h-list-user $user json")[$user_plain]["BACKUPS_MODE"] ?? "";
if ($backup_mode === "restic" && empty($_GET["backup"]) && empty($_GET["archives"])) {
	header("Location: /list/backup/incremental/?" . http_build_query(["token" => $_SESSION["token"]]));
	exit();
}

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
