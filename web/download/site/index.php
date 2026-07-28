<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";
include $_SERVER["DOCUMENT_ROOT"] . "/inc/download.php";

// Check token
verify_csrf($_GET);

$site = quoteshellarg($_GET["site"]);

exec(HESTIA_CMD . "h-dump-site " . $user . " " . $site . " full", $output, $return_var);

if ($return_var == 0) {
	// $output[1] = the /backup/<file>.zip path (basename == the $output[0] display name). No Range:
	// h-dump-site regenerates the archive per request.
	serve_download($output[1], "application/zip");
}
