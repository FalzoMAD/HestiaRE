<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

// Init
ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check token
verify_csrf($_GET);

if ($_SESSION["userContext"] === "admin") {
	if (!empty($_GET["srv"])) {
		// The firewall is our own ruleset, not a systemd unit, so it is handled directly. Match the
		// CONFIGURED name rather than a literal: the value became "nftables" with the renderer swap,
		// and a stale literal here sends the request to systemctl for a unit that is not ours.
		if (!empty($_SESSION["FIREWALL_SYSTEM"]) && $_GET["srv"] == $_SESSION["FIREWALL_SYSTEM"]) {
			exec(HESTIA_CMD . "h-update-firewall", $output, $return_var);
		} else {
			$v_service = quoteshellarg($_GET["srv"]);
			exec(HESTIA_CMD . "h-start-service " . $v_service, $output, $return_var);
		}
	}
	if ($return_var != 0) {
		$error = implode("<br>", $output);
		if (empty($error)) {
			$error = _('Start "%s" failed', $v_service);
		}
		$_SESSION["error_srv"] = $error;
	}
	unset($output);
}

header("Location: /list/server/");
exit();
