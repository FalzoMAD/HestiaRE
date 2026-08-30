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

// Loaded before the POST handler: the validation below decides on what is actually selectable,
// and an apache web role offers no web template at all.
$backend_templates = [];
$proxy_templates = [];
// Read by the template on the first render, where no POST has set it yet.
$v_backups_mode = "full";
if (!empty($_SESSION["WEB_BACKEND"])) {
	exec(HESTIA_CMD . "h-list-web-templates-backend json", $output, $return_var);
	$backend_templates = json_decode(implode("", $output), true) ?? [];
	unset($output);
}
if (!empty($_SESSION["PROXY_SYSTEM"])) {
	exec(HESTIA_CMD . "h-list-web-templates-proxy json", $output, $return_var);
	$proxy_templates = json_decode(implode("", $output), true) ?? [];
	unset($output);
}

$web_templates = cli_json("h-list-web-templates json");

// One gate per conditionally rendered control: rendered on it, read on it.
// A new package has nothing stored, so an absent control takes the shipped default.
$offer_web_template = !empty($web_templates);
$offer_backend_template = !empty($_SESSION["WEB_BACKEND"]) && !empty($backend_templates);
$offer_proxy_template = !empty($_SESSION["PROXY_SYSTEM"]);
$offer_docker_limit = !empty($_SESSION["DOCKER_SYSTEM"]);
// enforcement capability, not a switch (#211): pending/none boxes hide the control
$offer_quota = ($_SESSION["PROJECT_QUOTA"] ?? "") == "active";

// Check POST request
if (!empty($_POST["ok"])) {
	// Check token
	verify_csrf($_POST);
	$errors = [];
	// Check empty fields
	if (!isset($_POST["v_package"])) {
		$errors[] = _("Package");
	}
	if ($offer_web_template && !isset($_POST["v_web_template"])) {
		$errors[] = _("Web Template");
	}
	if ($offer_backend_template && !isset($_POST["v_backend_template"])) {
		$errors[] = _("Backend Template");
	}
	if ($offer_proxy_template && !isset($_POST["v_proxy_template"])) {
		$errors[] = _("Proxy Template");
	}
	if (!isset($_POST["v_shell"])) {
		$errors[] = _("Shell");
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
	if (!isset($_POST["v_databases"])) {
		$errors[] = _("Databases");
	}
	if (!isset($_POST["v_cron_jobs"])) {
		$errors[] = _("Cron Jobs");
	}
	if (!isset($_POST["v_backups"])) {
		$errors[] = _("Backups");
	}
	if (!isset($_POST["v_backups_mode"])) {
		$errors[] = _("Backup Mode");
	}
	if ($offer_quota && !isset($_POST["v_disk_quota"])) {
		$errors[] = _("Quota");
	}
	if (!isset($_POST["v_bandwidth"])) {
		$errors[] = _("Bandwidth");
	}
	if (!isset($_POST["v_ratelimit"])) {
		$errors[] = _("Rate Limit");
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
	} else {
		// Protect input
		$v_package = quoteshellarg($_POST["v_package"]);
		// "default" is the name every role resolves; with no backend there is no pool profile to name
		$v_web_template = quoteshellarg(post_or_keep("v_web_template", $offer_web_template, "default"));
		$v_backend_template = quoteshellarg(
			post_or_keep("v_backend_template", $offer_backend_template, empty($_SESSION["WEB_BACKEND"]) ? "" : "default"),
		);
		$v_proxy_template = quoteshellarg(post_or_keep("v_proxy_template", $offer_proxy_template, "default"));
		$v_shell = quoteshellarg(post_or_keep("v_shell", true, "nologin"));
		$v_web_domains = quoteshellarg($_POST["v_web_domains"]);
		$v_web_aliases = quoteshellarg($_POST["v_web_aliases"]);
		$v_mail_domains = quoteshellarg($_POST["v_mail_domains"]);
		$v_mail_accounts = quoteshellarg($_POST["v_mail_accounts"]);
		$v_databases = quoteshellarg($_POST["v_databases"]);
		$v_cron_jobs = quoteshellarg($_POST["v_cron_jobs"]);
		$v_backups = quoteshellarg($_POST["v_backups"]);
		$v_backups_mode = quoteshellarg($_POST["v_backups_mode"]);
		// Only rendered while the box enforces (#211); an unoffered field keeps the default
		$v_disk_quota = quoteshellarg(post_or_keep("v_disk_quota", $offer_quota, "unlimited"));
		$v_bandwidth = quoteshellarg($_POST["v_bandwidth"]);
		$v_ratelimit = quoteshellarg($_POST["v_ratelimit"]);

		// a preset name, not a size - the command rejects anything else
		$v_docker_limit = quoteshellarg(post_or_keep("v_docker_limit", $offer_docker_limit, "unlimited"));

		$v_time = quoteshellarg(date("H:i:s"));
		$v_date = quoteshellarg(date("Y-m-d"));

		// Create package file
		if (empty($_SESSION["error_msg"])) {
			$pkg = "WEB_TEMPLATE=" . $v_web_template . "\n";
			if (!empty($_SESSION["WEB_BACKEND"])) {
				$pkg .= "BACKEND_TEMPLATE=" . $v_backend_template . "\n";
			}
			if (!empty($_SESSION["PROXY_SYSTEM"])) {
				$pkg .= "PROXY_TEMPLATE=" . $v_proxy_template . "\n";
			}
			$pkg .= "WEB_DOMAINS=" . $v_web_domains . "\n";
			$pkg .= "WEB_ALIASES=" . $v_web_aliases . "\n";
			$pkg .= "MAIL_DOMAINS=" . $v_mail_domains . "\n";
			$pkg .= "MAIL_ACCOUNTS=" . $v_mail_accounts . "\n";
			$pkg .= "DATABASES=" . $v_databases . "\n";
			$pkg .= "CRON_JOBS=" . $v_cron_jobs . "\n";
			$pkg .= "DISK_QUOTA=" . $v_disk_quota . "\n";
			$pkg .= "DOCKER_LIMIT=" . $v_docker_limit . "\n";
			$pkg .= "BANDWIDTH=" . $v_bandwidth . "\n";
			$pkg .= "RATE_LIMIT=" . $v_ratelimit . "\n";
			$pkg .= "SHELL=" . $v_shell . "\n";
			$pkg .= "BACKUPS=" . $v_backups . "\n";
			$pkg .= "BACKUPS_MODE=" . $v_backups_mode . "\n";
			$pkg .= "TIME=" . $v_time . "\n";
			$pkg .= "DATE=" . $v_date . "\n";

			$tmpfile = tempnam("/tmp/", "hst_");
			$fp = fopen($tmpfile, "w");
			fwrite($fp, $pkg);
			exec(
				HESTIA_CMD . "h-add-user-package " . $tmpfile . " " . $v_package,
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);

			fclose($fp);
			unlink($tmpfile);
		}
		// Flush field values on success
		if (empty($_SESSION["error_msg"])) {
			$_SESSION["ok_msg"] = htmlify_trans(
				sprintf(
					_("Package {%s} has been created successfully."),
					htmlentities($_POST["v_package"]),
				),
				"</a>",
				'<a href="/edit/package/?package=' . htmlentities($_POST["v_package"]) . '">',
			);
			unset($v_package);
		}
	}
}

// List system shells
$shells = cli_json("h-list-sys-shells json");

// Set default values
if (empty($v_package)) {
	$v_package = "";
}
if (empty($v_web_template)) {
	$v_web_template = "default";
}
if (empty($v_backend_template)) {
	$v_backend_template = "default";
}
if (empty($v_proxy_template)) {
	$v_proxy_template = "default";
}
if (empty($v_shell)) {
	$v_shell = "nologin";
}
if (empty($v_web_domains)) {
	$v_web_domains = "'1'";
}
if (empty($v_web_aliases)) {
	$v_web_aliases = "'5'";
}
if (empty($v_mail_domains)) {
	$v_mail_domains = "'1'";
}
if (empty($v_mail_accounts)) {
	$v_mail_accounts = "'5'";
}
if (empty($v_databases)) {
	$v_databases = "'1'";
}
if (empty($v_cron_jobs)) {
	$v_cron_jobs = "'1'";
}
if (empty($v_backups)) {
	$v_backups = "'1'";
}
if (empty($v_disk_quota)) {
	$v_disk_quota = "'1000'";
}
if (empty($v_bandwidth)) {
	$v_bandwidth = "'1000'";
}
if (empty($v_ratelimit)) {
	$v_ratelimit = "'200'";
}

if (empty($v_docker_limit)) {
	$v_docker_limit = "'unlimited'";
}

// Render page
render_page($user, $TAB, "add_package");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
