<?php

use function Hestiacp\quoteshellarg\quoteshellarg;
$TAB = "SERVER";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user — admin only. The second clause (`&& $user_plain === "$ROOT_USER"`)
// was an auth-bypass (GHSA-fcq6): $ROOT_USER is undefined here, so it always
// evaluated false and let any authenticated user reach this page (which rewrites
// the hestia panel service config + the privileged panel crontab). Gate on the
// role alone.
if ($_SESSION["userContext"] !== "admin") {
	header("Location: /list/user");
	exit();
}

// Check POST request
if (!empty($_POST["save"])) {
	if (!empty($_POST["v_config"])) {
		$fp = tmpfile();
		$new_conf = stream_get_meta_data($fp)["uri"];
		$config = str_replace("\r\n", "\n", $_POST["v_config"]);
		if (!str_ends_with($config, "\n")) {
			$config .= "\n";
		}
		fwrite($fp, $config);
		exec(
			HESTIA_CMD .
				"h-change-sys-service-config " .
				quoteshellarg($new_conf) .
				" hestia yes",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		fclose($fp);
	}
}

$v_config_path = "/var/spool/cron/crontabs/hestia";
$v_service_name = _("Panel Cronjobs");

// Read config
$v_config = shell_exec(HESTIA_CMD . "h-open-fs-config " . $v_config_path);

// Render page
render_page($user, $TAB, "edit_server_service");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
