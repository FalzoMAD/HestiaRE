<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

// Web bot rate-limit family table (Layer B, #482). Server-wide policy, so admin-only - a customer
// only ever picks a level per domain (edit_web), never edits the table itself.
$TAB = "SERVER";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

$slots = 10;

// Check POST request
if (!empty($_POST["save"])) {
	// Check token
	verify_csrf($_POST);

	// The whole table is saved in one POST, so every row defers the re-render (APPLY=no) and one
	// h-update-sys-botfamilies applies at the end - otherwise nginx would reload once per row.
	$touched = false;
	for ($i = 0; $i < $slots; $i++) {
		$orig = trim($_POST["orig"][$i] ?? "");
		$fam = strtolower(trim($_POST["fam"][$i] ?? ""));
		$match = trim($_POST["match"][$i] ?? "");
		$lenient = trim($_POST["lenient"][$i] ?? "");
		$strict = trim($_POST["strict"][$i] ?? "");
		$enabled = ($_POST["enabled"][$i] ?? "no") === "yes" ? "yes" : "no";

		// An emptied name (or a rename) drops the old family, which also strips it from every domain
		// that throttled it - a leftover reference would point at a zone that no longer exists.
		if ($orig !== "" && ($fam === "" || $fam !== $orig)) {
			exec(
				HESTIA_CMD . "h-delete-sys-botfamily " . quoteshellarg($orig) . " no",
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			$touched = true;
		}
		if ($fam === "" || $match === "") {
			continue;
		}
		exec(
			HESTIA_CMD .
				"h-change-sys-botfamily " .
				quoteshellarg($fam) .
				" " .
				quoteshellarg($match) .
				" " .
				quoteshellarg($lenient) .
				" " .
				quoteshellarg($strict) .
				" " .
				quoteshellarg($enabled) .
				" no",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$touched = true;
	}

	if ($touched && empty($_SESSION["error_msg"])) {
		exec(HESTIA_CMD . "h-update-sys-botfamilies", $output, $return_var);
		check_return_code($return_var, $output);
		unset($output);
	}

	if (empty($_SESSION["error_msg"])) {
		$_SESSION["ok_msg"] = _("Changes have been saved.");
	}
}

// Current table, padded to the fixed number of slots so empty rows are offered for new families.
exec(HESTIA_CMD . "h-list-sys-botfamily json", $output, $return_var);
$data = json_decode(implode("", $output), true);
unset($output);
if (!is_array($data)) {
	$data = [];
}

$rows = [];
foreach ($data as $fam => $v) {
	$rows[] = [
		"orig" => $fam,
		"fam" => $fam,
		"match" => $v["MATCH"] ?? "",
		"lenient" => $v["LENIENT"] ?? "",
		"strict" => $v["STRICT"] ?? "",
		"enabled" => ($v["ENABLED"] ?? "no") === "yes",
		"burst" => $v["BURST"] ?? "",
		"nodelay" => $v["NODELAY"] ?? "",
	];
}
while (count($rows) < $slots) {
	$rows[] = [
		"orig" => "",
		"fam" => "",
		"match" => "",
		"lenient" => "60r/m",
		"strict" => "20r/m",
		"enabled" => false,
		"burst" => "",
		"nodelay" => "",
	];
}

// Which front actually enforces Layer B, for the hint on the page.
$v_front = !empty($_SESSION["PROXY_SYSTEM"]) ? $_SESSION["PROXY_SYSTEM"] : $_SESSION["WEB_SYSTEM"];

// Render page
render_page($user, $TAB, "edit_server_botlimit");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
