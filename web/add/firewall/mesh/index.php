<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

// Join another box's CrowdSec mesh (#485) with the one-time code its admin minted there. Both halves
// of the authorisation meet here: this admin session, and that box's code.
ob_start();
$TAB = "FIREWALL";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

// Check POST request
if (!empty($_POST["ok"])) {
	// Check token
	verify_csrf($_POST);

	if (empty($_POST["v_host"])) {
		$errors[] = _("Hostname");
	}
	if (empty($_POST["v_code"])) {
		$errors[] = _("Pairing Code");
	}

	if (!empty($errors[0])) {
		foreach ($errors as $i => $error) {
			if ($i == 0) {
				$error_msg = $error;
			} else {
				$error_msg = $error_msg . ", " . $error;
			}
		}
		$_SESSION["error_msg"] = sprintf(_('Field "%s" can not be blank.'), $error_msg);
	}

	$v_host = $_POST["v_host"];
	$v_port = $_POST["v_port"] ?? "";

	if (empty($_SESSION["error_msg"])) {
		// The code goes to the CLI through a 0600 handoff file, not argv: any local user can read
		// another process's command line via /proc.
		$handoff = "/run/hestia/mesh/in/" . bin2hex(random_bytes(16));
		if (@file_put_contents($handoff, $_POST["v_code"], LOCK_EX) === false) {
			$_SESSION["error_msg"] = _("CrowdSec fleet-mesh is not enabled on this server.");
		} else {
			chmod($handoff, 0600);
			exec(
				HESTIA_CMD .
					"h-add-sys-crowdsec-peer " .
					quoteshellarg($v_host) .
					" " .
					quoteshellarg("@" . $handoff) .
					" " .
					quoteshellarg($v_port),
				$output,
				$return_var,
			);
			@unlink($handoff);
			check_return_code($return_var, $output);
			unset($output);
		}
	}

	// Flush field values on success
	if (empty($_SESSION["error_msg"])) {
		$_SESSION["ok_msg"] = _("Peer has been paired successfully.");
		unset($v_host);
	}
}
if (empty($v_host)) {
	$v_host = "";
}
if (empty($v_port)) {
	$v_port = $_SESSION["BACKEND_PORT"] ?? "8083";
}

// Render
render_page($user, $TAB, "add_firewall_mesh");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
