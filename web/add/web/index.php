<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
$TAB = "WEB";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check POST request
if (!empty($_POST["ok"])) {
	// Check token
	verify_csrf($_POST);

	// Check for empty fields
	if (empty($_POST["v_domain"])) {
		$errors[] = _("Domain");
	}
	if (empty($_POST["v_ip"])) {
		$errors[] = _("IP Address");
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

	// Set domain to lowercase and remove www prefix
	$v_domain = preg_replace("/^www\./i", "", $_POST["v_domain"]);
	$v_domain = strtolower($v_domain);

	// Define domain ip address
	$v_ip = quoteshellarg($_POST["v_ip"]);

	// Using public IP instead of internal IP when creating DNS
	// Gets public IP from 'h-list-user-ips' command (that reads /etc/hestia/ips/ip), precisely from 'NAT' field
	$v_public_ip = $v_ip;
	$v_clean_ip = $_POST["v_ip"]; // clean_ip = IP without quotas
	$ips = cli_json("h-list-user-ips " . $user . " json");
	if (
		isset($ips[$v_clean_ip]) &&
		isset($ips[$v_clean_ip]["NAT"]) &&
		trim($ips[$v_clean_ip]["NAT"]) != ""
	) {
		$v_public_ip = trim($ips[$v_clean_ip]["NAT"]);
		$v_public_ip = quoteshellarg($v_public_ip);
	}

	// Define domain aliases
	$v_aliases = "";

	// Define proxy extensions
	$_POST["v_proxy_ext"] = "";

	$user_config = cli_json("h-list-user " . $user . " json");

	$v_template = $user_config[$user_plain]["WEB_TEMPLATE"];
	$v_backend_template = $user_config[$user_plain]["BACKEND_TEMPLATE"];
	$v_proxy_template = $user_config[$user_plain]["PROXY_TEMPLATE"];

	// Add web domain
	if (empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD .
				"h-add-web-domain " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" " .
				$v_ip .
				" 'yes'",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$domain_added = empty($_SESSION["error_msg"]);
	}

	if (empty($_POST["v_mail"])) {
		$_POST["v_mail"] = "no";
	}

	// Add mail domain
	if ($_POST["v_mail"] == "on" && empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD . "h-add-mail-domain " . $user . " " . quoteshellarg($v_domain),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
	}

	// Flush field values on success
	if (empty($_SESSION["error_msg"])) {
		$_SESSION["ok_msg"] = htmlify_trans(
			sprintf(_("Domain {%s} has been created successfully."), htmlentities($v_domain)),
			"</a>",
			'<a href="/edit/web/?domain=' . htmlentities($v_domain) . '">',
		);
		unset($v_domain);
		unset($v_aliases);
	}
}
// Define user variables
$v_aliases = "";

// List user package
$user_config = cli_json("h-list-user " . $user . " json");
// List web templates and set default values
$templates = cli_json("h-list-web-templates json");
$v_template = !empty($_POST["v_template"])
	? $_POST["v_template"]
	: $user_config[$user_plain]["WEB_TEMPLATE"];
// List backend templates
if (!empty($_SESSION["WEB_BACKEND"])) {
	$backend_templates = cli_json("h-list-web-templates-backend json");
	$v_backend_template = !empty($_POST["v_backend_template"])
		? $_POST["v_backend_template"]
		: $user_config[$user_plain]["BACKEND_TEMPLATE"];
}

// List proxy templates
if (!empty($_SESSION["PROXY_SYSTEM"])) {
	$proxy_templates = cli_json("h-list-web-templates-proxy json");
	$v_proxy_template = !empty($_POST["v_proxy_template"])
		? $_POST["v_proxy_template"]
		: $user_config[$user_plain]["PROXY_TEMPLATE"];
}

// List IP addresses - v4 where the box has one: the v6 side auto-assigns in h-add-web-domain
// (#602). A v6-only box has nothing else to offer, so the v6 list becomes the select and the
// command sorts that address into IP6 (#892).
$ips = cli_json("h-list-user-ips " . $user . " json");
$ips_v4 = array_filter($ips, fn($k) => !str_contains($k, ":"), ARRAY_FILTER_USE_KEY);
$ips = $ips_v4 ?: $ips;

// Get all user domains
$user_domains = array_keys(cli_json("h-list-web-domains " . $user . " json"));

$accept = $_GET["accept"] ?? "";

$v_domain = $_POST["domain"] ?? "";

// Render page
render_page($user, $TAB, "add_web");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
