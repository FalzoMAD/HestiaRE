<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";
include $_SERVER["DOCUMENT_ROOT"] . "/inc/download.php";

// Check token
verify_csrf($_GET);

$database = quoteshellarg($_GET["database"]);

exec(
	HESTIA_CMD . "h-dump-database " . $user . " " . $database . " file gzip",
	$output,
	$return_var,
);

if ($return_var == 0) {
	// No Range: h-dump-database regenerates the dump per request, so a resume would stream a different file.
	serve_download($output[0], "application/sql");
}
