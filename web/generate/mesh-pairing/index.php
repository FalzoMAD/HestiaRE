<?php
// Mint a one-time CrowdSec mesh pairing code for another box to join with (#485). Being logged in
// here as admin IS the local half of the pairing authorisation - the joining box needs its own admin
// as well, so neither side can pair on its own.
ob_start();

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

// Check token
verify_csrf($_POST);

exec(HESTIA_CMD . "h-generate-sys-crowdsec-pairing", $output, $return_var);
if ($return_var !== 0) {
	check_return_code($return_var, $output);
} else {
	// The code is printed on the first line and never stored in plaintext anywhere - the list page
	// shows it once, from the session, and forgets it. The validity note follows after a blank line.
	$_SESSION["mesh_pairing_code"] = trim($output[0] ?? "");
	$_SESSION["mesh_pairing_note"] = "";
	foreach ($output as $line) {
		if (strpos($line, "Valid for") === 0) {
			$_SESSION["mesh_pairing_note"] = trim($line);
			break;
		}
	}
}
unset($output);

header("Location: /list/firewall/mesh/");
exit();
