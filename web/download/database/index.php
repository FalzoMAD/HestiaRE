<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check token
verify_csrf($_GET);

$database = quoteshellarg($_GET["database"]);

exec(
	HESTIA_CMD . "h-dump-database " . $user . " " . $database . " file gzip",
	$output,
	$return_var,
);

if ($return_var == 0) {
	// Stream via PHP (panel pool = hestia), not X-Accel-Redirect (caddy can't read
	// the dump). readfile() binds this worker for the download's duration (#441).
	while (ob_get_level()) {
		ob_end_clean();
	}
	header("Content-type: application/sql");
	header("Content-Disposition: attachment; filename=\"" . basename($output[0]) . "\"");
	header("Content-Length: " . filesize($output[0]));
	readfile($output[0]);
	exit();
}
