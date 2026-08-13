<?php
// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

function formatNotificationTimestamps(&$note) {
	$dateTime = DateTime::createFromFormat("Y-m-d H:i:s", $note["DATE"] . " " . $note["TIME"]);
	$note["TIMESTAMP_TEXT"] = $dateTime->format("d M Y, H:i");
	$note["TIMESTAMP_ISO"] = $dateTime->format(DateTime::ATOM); // ISO 8601 format
	$note["TIMESTAMP_TITLE"] = $dateTime->format("d F Y, H:i:s");
}

if (($_REQUEST["ajax"] ?? "") == 1 && ($_REQUEST["token"] ?? "") === ($_SESSION["token"] ?? "")) {
	// Data
	exec(HESTIA_CMD . "h-list-user-notifications $user json", $output, $return_var);
	$data = json_decode(implode("", $output), true);

	foreach ($data as $key => &$note) {
		formatNotificationTimestamps($note);
	}
	unset($note);

	function sort_priority_id($element1, $element2) {
		return $element2["PRIORITY"] <=> $element1["PRIORITY"];
	}
	$data = array_reverse($data, true);
	usort($data, "sort_priority_id");

	foreach ($data as $key => $note) {
		$note["ID"] = $key;
		$data[$key] = $note;
	}
	echo json_encode($data);
	exit();
}

$TAB = "NOTIFICATIONS";

// Data
exec(HESTIA_CMD . "h-list-user-notifications $user json", $output, $return_var);
$data = json_decode(implode("", $output), true);
$data = array_reverse($data, true);

// The JSON branch above is the live one - the notification bell reads it. There has never been a
// pages/list_notifications.php, here or upstream, so rendering it only produced an include warning
// and an empty shell. Send the browser somewhere real until the page actually exists.
header("Location: /list/user/");
exit();

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
