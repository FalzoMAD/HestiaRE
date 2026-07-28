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
	// $output[1] is the /backup/<file>.zip path; its basename is the display name
	// (== $output[0]). No Range: h-dump-site regenerates the archive per request
	// (see inc/download.php).
	serve_download($output[1], "application/zip");
}
