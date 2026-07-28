<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check token
verify_csrf($_GET);

// Stream a file straight from PHP. We do NOT use X-Accel-Redirect (#441): the panel
// is Caddy-fronted and its file_server would run as `caddy`, which cannot read the
// customer-owned backups — and granting caddy that read is the capability we avoid
// (same reason as the file manager). The panel pool runs as `hestia`, the owner of
// every /backup file, so it can stream them. readfile() streams in chunks; note it
// binds this FPM worker for the download's duration.
function serve_download($file, $ctype)
{
	while (ob_get_level()) {
		ob_end_clean();
	}
	header("Content-Type: " . $ctype);
	header("Content-Disposition: attachment; filename=\"" . basename($file) . "\"");
	header("Content-Length: " . filesize($file));
	readfile($file);
	exit();
}

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
	if ($_SESSION["userContext"] === "admin") {
		serve_download("/backup/" . $backup, "application/gzip");
	}
	if (!empty($user_plain) && $_SESSION["userContext"] != "admin") {
		if (strpos($backup, $user_plain . ".") === 0) {
			serve_download("/backup/" . $backup, "application/gzip");
		}
	}
}
