<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();

include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// The whole-archive restore posts, so it can carry the PHP-fallback consent; the per-object
// links stay GET.
$req = $_SERVER["REQUEST_METHOD"] === "POST" ? $_POST : $_GET;

// Check token
verify_csrf($req);

// Without a backup id there is nothing to schedule; quoteshellarg(null) is a TypeError, so this
// has to refuse before it, not after.
if (empty($req["backup"])) {
	header("Location: /list/backup/");
	exit();
}
$backup = quoteshellarg($req["backup"]);

$web = "no";
// The subsystem is gone; the positional stays for CLI compatibility and is always "no".
$dns = "no";
$mail = "no";
$db = "no";
$cron = "no";
$udir = "no";

if ($req["type"] == "web") {
	$web = quoteshellarg($req["object"]);
}
if ($req["type"] == "mail") {
	$mail = quoteshellarg($req["object"]);
}
if ($req["type"] == "db") {
	$db = quoteshellarg($req["object"]);
}
if ($req["type"] == "cron") {
	$cron = "yes";
}
if ($req["type"] == "udir") {
	$udir = quoteshellarg($req["object"]);
}

if (!empty($req["type"])) {
	$restore_cmd =
		HESTIA_CMD .
		"h-schedule-user-restore " .
		$user .
		" " .
		$backup .
		" " .
		$web .
		" " .
		$dns .
		" " .
		$mail .
		" " .
		$db .
		" " .
		$cron .
		" " .
		$udir;
} else {
	// A whole-archive restore names no object, so nothing in it carries consent by selection. The
	// queue has no terminal to ask at, so the click has to say it (#707). "all" covers the sections
	// and not the PHP fallback - moving domains onto another PHP version stays an explicit choice.
	$consent = empty($req["php_fallback"]) ? "all" : "all,php-fallback";
	$restore_cmd =
		HESTIA_CMD . "h-schedule-user-restore " . $user . " " . $backup . " '' '' '' '' '' '' " . $consent;
}

exec($restore_cmd, $output, $return_var);
if ($return_var == 0) {
	$_SESSION["error_msg"] = _(
		"Task has been added to the queue. You will receive an email notification when your restore has been completed.",
	);
} else {
	$_SESSION["error_msg"] = implode("<br>", $output);
	if (empty($_SESSION["error_msg"])) {
		$_SESSION["error_msg"] = _("Error: Hestia did not return any output.");
	}
	if ($return_var == 4) {
		$_SESSION["error_msg"] = _(
			"An existing restoration task is already running. Please wait for it to finish before launching it again.",
		);
	}
}

header("Location: /list/backup/?backup=" . $req["backup"]);
