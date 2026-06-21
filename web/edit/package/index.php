<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
$TAB = "PACKAGE";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

// Check package argument
if (empty($_GET["package"])) {
	header("Location: /list/package/");
	exit();
}

// Prevent editing of system package
if ($_GET["package"] === "system") {
	header("Location: /list/package/");
	exit();
}

// List package
$v_package = quoteshellarg($_GET["package"]);
exec(HESTIA_CMD . "h-list-user-package " . $v_package . " 'json'", $output, $return_var);
check_return_code_redirect($return_var, $output, "/list/package/");
$data = json_decode(implode("", $output), true);
unset($output);

// Parse package
$v_package = $_GET["package"];
$v_package_new = $_GET["package"];
$v_web_template = $data[$v_package]["WEB_TEMPLATE"];
$v_backend_template = $data[$v_package]["BACKEND_TEMPLATE"];
$v_proxy_template = $data[$v_package]["PROXY_TEMPLATE"];
$v_web_domains = $data[$v_package]["WEB_DOMAINS"];
$v_web_aliases = $data[$v_package]["WEB_ALIASES"];
$v_mail_domains = $data[$v_package]["MAIL_DOMAINS"];
$v_mail_accounts = $data[$v_package]["MAIL_ACCOUNTS"];
$v_ratelimit = $data[$v_package]["RATE_LIMIT"];
$v_databases = $data[$v_package]["DATABASES"];
$v_cron_jobs = $data[$v_package]["CRON_JOBS"];
$v_disk_quota = $data[$v_package]["DISK_QUOTA"];
$v_bandwidth = $data[$v_package]["BANDWIDTH"];
$v_shell = $data[$v_package]["SHELL"];
$v_cpu_quota = $data[$v_package]["CPU_QUOTA"];
$v_cpu_quota_period = $data[$v_package]["CPU_QUOTA_PERIOD"];
$v_memory_limit = $data[$v_package]["MEMORY_LIMIT"];
$v_swap_limit = $data[$v_package]["SWAP_LIMIT"];
$v_backups = $data[$v_package]["BACKUPS"];
$v_backups_incremental = $data[$v_package]["BACKUPS_INCREMENTAL"];
$v_date = $data[$v_package]["DATE"];
$v_time = $data[$v_package]["TIME"];
$v_status = "active";

// List web templates
exec(HESTIA_CMD . "h-list-web-templates json", $output, $return_var);
$web_templates = json_decode(implode("", $output), true);
unset($output);

// List backend templates
if (!empty($_SESSION["WEB_BACKEND"])) {
	exec(HESTIA_CMD . "h-list-web-templates-backend json", $output, $return_var);
	$backend_templates = json_decode(implode("", $output), true);
	unset($output);
}

// List proxy templates
if (!empty($_SESSION["PROXY_SYSTEM"])) {
	exec(HESTIA_CMD . "h-list-web-templates-proxy json", $output, $return_var);
	$proxy_templates = json_decode(implode("", $output), true);
	unset($output);
}

// List shels
exec(HESTIA_CMD . "h-list-sys-shells json", $output, $return_var);
$shells = json_decode(implode("", $output), true);
unset($output);

// Check POST request
if (!empty($_POST["save"])) {
	// Check token
	verify_csrf($_POST);

	// Check empty fields
	if (empty($_POST["v_package"])) {
		$errors[] = _("Package");
	}
	if (empty($_POST["v_web_template"])) {
		$errors[] = _("Web Template");
	}
	if (!empty($_SESSION["WEB_BACKEND"])) {
		if (empty($_POST["v_backend_template"])) {
			$errors[] = _("Backend Template");
		}
	}
	if (!empty($_SESSION["PROXY_SYSTEM"])) {
		if (empty($_POST["v_proxy_template"])) {
			$errors[] = _("Proxy Template");
		}
	}
	if (empty($_POST["v_shell"])) {
		$errrors[] = _("Shell");
	}
	if (!isset($_POST["v_web_domains"])) {
		$errors[] = _("Web Domains");
	}
	if (!isset($_POST["v_web_aliases"])) {
		$errors[] = _("Web Aliases");
	}
	if (!isset($_POST["v_mail_domains"])) {
		$errors[] = _("Mail Domains");
	}
	if (!isset($_POST["v_mail_accounts"])) {
		$errors[] = _("Mail Accounts");
	}
	if (!isset($_POST["v_ratelimit"])) {
		$errors[] = _("Rate Limit");
	}
	if (!isset($_POST["v_databases"])) {
		$errors[] = _("Databases");
	}
	if (!isset($_POST["v_cron_jobs"])) {
		$errors[] = _("Cron Jobs");
	}
	if (!isset($_POST["v_backups"])) {
		$errors[] = _("Backups");
	}
	if (!isset($_POST["v_backups_incremental"])) {
		$errors[] = _("Incremental Backups");
	}
	if (!isset($_POST["v_disk_quota"])) {
		$errors[] = _("Quota");
	}
	if (!isset($_POST["v_bandwidth"])) {
		$errors[] = _("Bandwidth");
	}

	if ($_SESSION["RESOURCES_LIMIT"] == "yes") {
		if (!isset($_POST["v_cpu_quota"])) {
			$errors[] = _("CPU quota");
		}
		if (!isset($_POST["v_cpu_quota_period"])) {
			$errors[] = _("CPU quota period");
		}
		if (!isset($_POST["v_memory_limit"])) {
			$errors[] = _("Memory Limit");
		}
		if (!isset($_POST["v_swap_limit"])) {
			$errors[] = _("Swap Limit");
		}
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

	// Protect input
	$v_package = quoteshellarg($_POST["v_package"]);
	$v_package_new = quoteshellarg($_POST["v_package_new"]);
	$v_web_template = quoteshellarg($_POST["v_web_template"]);
	if (!empty($_SESSION["WEB_BACKEND"])) {
		$v_backend_template = quoteshellarg($_POST["v_backend_template"]);
	}
	if (!empty($_SESSION["PROXY_SYSTEM"])) {
		$v_proxy_template = quoteshellarg($_POST["v_proxy_template"]);
	}
	if (!empty($_POST["v_shell"])) {
		$v_shell = quoteshellarg($_POST["v_shell"]);
	} else {
		$v_shell = "nologin";
	}
	$v_web_domains = quoteshellarg($_POST["v_web_domains"]);
	$v_web_aliases = quoteshellarg($_POST["v_web_aliases"]);
	$v_mail_domains = quoteshellarg($_POST["v_mail_domains"]);
	$v_mail_accounts = quoteshellarg($_POST["v_mail_accounts"]);
	$v_ratelimit = quoteshellarg($_POST["v_ratelimit"]);
	$v_databases = quoteshellarg($_POST["v_databases"]);
	$v_cron_jobs = quoteshellarg($_POST["v_cron_jobs"]);
	$v_backups = quoteshellarg($_POST["v_backups"]);
	$v_backups_incremental = quoteshellarg($_POST["v_backups_incremental"]);
	$v_disk_quota = quoteshellarg($_POST["v_disk_quota"]);
	$v_bandwidth = quoteshellarg($_POST["v_bandwidth"]);

	$v_cpu_quota =
		$_SESSION["RESOURCES_LIMIT"] == "yes" ? quoteshellarg($_POST["v_cpu_quota"]) : "";
	$v_cpu_quota_period =
		$_SESSION["RESOURCES_LIMIT"] == "yes" ? quoteshellarg($_POST["v_cpu_quota_period"]) : "";
	$v_memory_limit =
		$_SESSION["RESOURCES_LIMIT"] == "yes" ? quoteshellarg($_POST["v_memory_limit"]) : "";
	$v_swap_limit =
		$_SESSION["RESOURCES_LIMIT"] == "yes" ? quoteshellarg($_POST["v_swap_limit"]) : "";

	$v_time = quoteshellarg(date("H:i:s"));
	$v_date = quoteshellarg(date("Y-m-d"));

	// Save package file on a fs
	$pkg = "WEB_TEMPLATE=" . $v_web_template . "\n";
	$pkg .= "BACKEND_TEMPLATE=" . $v_backend_template . "\n";
	$pkg .= "PROXY_TEMPLATE=" . $v_proxy_template . "\n";
	$pkg .= "WEB_DOMAINS=" . $v_web_domains . "\n";
	$pkg .= "WEB_ALIASES=" . $v_web_aliases . "\n";
	$pkg .= "MAIL_DOMAINS=" . $v_mail_domains . "\n";
	$pkg .= "MAIL_ACCOUNTS=" . $v_mail_accounts . "\n";
	$pkg .= "RATE_LIMIT=" . $v_ratelimit . "\n";
	$pkg .= "DATABASES=" . $v_databases . "\n";
	$pkg .= "CRON_JOBS=" . $v_cron_jobs . "\n";
	$pkg .= "DISK_QUOTA=" . $v_disk_quota . "\n";
	$pkg .= "CPU_QUOTA=" . $v_cpu_quota . "\n";
	$pkg .= "CPU_QUOTA_PERIOD=" . $v_cpu_quota_period . "\n";
	$pkg .= "MEMORY_LIMIT=" . $v_memory_limit . "\n";
	$pkg .= "SWAP_LIMIT=" . $v_swap_limit . "\n";
	$pkg .= "BANDWIDTH=" . $v_bandwidth . "\n";
	$pkg .= "SHELL=" . $v_shell . "\n";
	$pkg .= "BACKUPS=" . $v_backups . "\n";
	$pkg .= "BACKUPS_INCREMENTAL=" . $v_backups_incremental . "\n";
	$pkg .= "TIME=" . $v_time . "\n";
	$pkg .= "DATE=" . $v_date . "\n";

	$tmpfile = tempnam("/tmp/", "hst_");
	$fp = fopen($tmpfile, "w");
	fwrite($fp, $pkg);
	exec(
		HESTIA_CMD . "h-add-user-package " . $tmpfile . " " . $v_package . " yes",
		$output,
		$return_var,
	);
	check_return_code($return_var, $output);
	unset($output);

	fclose($fp);
	unlink($tmpfile);

	// Propagate new package
	exec(HESTIA_CMD . "h-update-user-package " . $v_package . " 'json'", $output, $return_var);
	check_return_code($return_var, $output);
	unset($output);

	if ($v_package_new != $v_package) {
		exec(
			HESTIA_CMD . "h-rename-user-package " . $v_package . " " . $v_package_new,
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
	}
	// Set success message
	if (empty($_SESSION["error_msg"])) {
		$_SESSION["ok_msg"] = _("Changes have been saved.");
	}
}

// Render page
render_page($user, $TAB, "edit_package");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
