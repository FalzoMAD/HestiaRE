<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";
include $_SERVER["DOCUMENT_ROOT"] . "/inc/download.php";

// Check token
verify_csrf($_GET);

// basename(): $backup becomes a filesystem path below and the pool can read more
// than the old caddy file_server could — keep it a bare filename, no traversal.
$backup = basename($_GET["backup"]);

if (!file_exists("/backup/" . $backup)) {
	$v_backup = quoteshellarg($backup);
	exec(
		HESTIA_CMD . "h-schedule-user-backup-download " . $user . " " . $v_backup,
		$output,
		$return_var,
	);
	if ($return_var == 0) {
		$_SESSION["error_msg"] = _("Download of remote backup file has been scheduled.");
	} else {
		$_SESSION["error_msg"] = implode("<br>", $output);
		if (empty($_SESSION["error_msg"])) {
			$_SESSION["error_msg"] = _("Error: Hestia did not return any output.");
		}
	}
	unset($output);
	header("Location: /list/backup/");
	exit();
} else {
	// Admin may fetch any backup; a customer only their own. Scope on the EFFECTIVE
	// user ($user_plain is look-aware, set in inc/main.php) — not the raw session
	// user — so an admin impersonating a customer scopes to the customer, not the
	// admin (#438).
	// A stored backup is a static file → Range/resume is safe (3rd arg true).
	if ($_SESSION["userContext"] === "admin") {
		serve_download("/backup/" . $backup, "application/gzip", true);
	}
	if (!empty($user_plain) && $_SESSION["userContext"] != "admin") {
		if (strpos($backup, $user_plain . ".") === 0) {
			serve_download("/backup/" . $backup, "application/gzip", true);
		}
	}
}
