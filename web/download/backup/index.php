<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";
include $_SERVER["DOCUMENT_ROOT"] . "/inc/download.php";

// Check token
verify_csrf($_GET);

// basename() → bare filename, no traversal: the pool reads more of the fs than caddy's file_server.
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
	// Admin fetches any backup, a customer only their own. Scope on $user_plain (look-aware, from
	// inc/main.php), not the raw session user, so an impersonating admin scopes to the customer (#438).
	// A stored backup is static, so Range/resume is safe (3rd arg true).
	if ($_SESSION["userContext"] === "admin") {
		serve_download("/backup/" . $backup, "application/gzip", true);
	}
	if (!empty($user_plain) && $_SESSION["userContext"] != "admin") {
		if (strpos($backup, $user_plain . ".") === 0) {
			serve_download("/backup/" . $backup, "application/gzip", true);
		}
	}
	// serve_download() exits; reaching here = a customer asked for a backup that isn't theirs.
	$_SESSION["error_msg"] = _("You are not allowed to access this backup.");
	header("Location: /list/backup/");
	exit();
}
