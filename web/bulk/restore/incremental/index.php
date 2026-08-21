<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();

include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check token
verify_csrf($_POST);

$action = $_POST["action"];
$snapshot = quoteshellarg($_POST["snapshot"]);

// One scheduler call per object: h-schedule-user-restore-restic takes a single value and
// validates it as one domain or database, and its validator rejects a comma.
function schedule_restic($user, $snapshot, $object, $values)
{
	foreach ((array) $values as $value) {
		exec(
			HESTIA_CMD .
				"h-schedule-user-restore-restic " .
				$user .
				" " .
				$snapshot .
				" " .
				$object .
				" " .
				quoteshellarg($value),
			$output,
			$return_var,
		);
	}
}

if ($action == "restore") {
	schedule_restic($user, $snapshot, "web", $_POST["web"] ?? []);
	schedule_restic($user, $snapshot, "mail", $_POST["mail"] ?? []);
	schedule_restic($user, $snapshot, "db", $_POST["db"] ?? []);
	if (!empty($_POST["cron"])) {
		exec(
			HESTIA_CMD . "h-schedule-user-restore-restic " . $user . " " . $snapshot . " " . "cron",
			$output,
			$return_var,
		);
	}
}

if ($return_var == 0) {
	$_SESSION["error_msg"] = _(
		"Task has been added to the queue. You will receive an email notification when your restore has been completed.",
	);
} else {
	$_SESSION["error_msg"] = implode("<br>", $output);
}
header("Location: /list/backup/incremental/?snapshot=" . $_POST["snapshot"]);
