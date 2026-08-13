<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
unset($_SESSION["error_msg"]);
$TAB = "WEB";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// The certificate fields the page carries. Refreshed at four points (initial load, cert upload,
// LE issue, SSL enable) - as four copies, a new field meant four edits and three chances to miss one.
function web_ssl_vars(string $user, string $domain): array
{
	exec(
		HESTIA_CMD . "h-list-web-domain-ssl " . $user . " " . quoteshellarg($domain) . " json",
		$output,
		$return_var,
	);
	$row = (json_decode(implode("", $output), true) ?: [])[$domain] ?? [];
	$vars = [];
	foreach (
		["CRT", "KEY", "CA", "SUBJECT", "ALIASES", "NOT_BEFORE", "NOT_AFTER", "SIGNATURE", "PUB_KEY", "ISSUER"] as $field
	) {
		$vars["v_ssl_" . strtolower($field)] = $row[$field] ?? "";
	}
	return $vars;
}

// Check domain argument
if (empty($_GET["domain"])) {
	header("Location: /list/web/");
	exit();
}

// Edit as someone else?
if ($_SESSION["userContext"] === "admin" && !empty($_GET["user"])) {
	$user = quoteshellarg($_GET["user"]);
	$user_plain = htmlentities($_GET["user"]);
}

// Get all user domains
exec(HESTIA_CMD . "h-list-web-domains " . $user . " json", $output, $return_var);
$all_web = json_decode(implode("", $output), true);
$user_domains = array_keys((array) $all_web);
unset($output);

$v_domain = $_GET["domain"];
exec(
	HESTIA_CMD . "h-list-web-domain " . $user . " " . quoteshellarg($v_domain) . " json",
	$output,
	$return_var,
);
# Check if domain exists if not return /list/web/
check_return_code_redirect($return_var, $output, "/list/web/");
$data = json_decode(implode("", $output), true);
unset($output);

// Parse domain
$v_ip = $data[$v_domain]["IP"];
$v_template = $data[$v_domain]["TPL"];

// Docker publishing (#566/#592): the owner's /24 gates the whole section; the domain carries
// which app it fronts (octet inside the /24 + port). reset(), not [$user]: in the admin path
// $user is already quoteshellarg'd and would miss the plain json key - the json carries
// exactly the one requested user anyway.
$owner_info = cli_json("h-list-user " . $user . " json");
$owner_row = reset($owner_info) ?: [];
$v_docker_net = "";
if (!empty($owner_row["DOCKER_IP"])) {
	$v_docker_net = preg_replace('/\.\d+$/', "", $owner_row["DOCKER_IP"]);
}
$v_docker = $data[$v_domain]["DOCKER"] ?? "";
$v_docker_port = $data[$v_domain]["DOCKER_PORT"] ?? "";
$v_docker_octet = $data[$v_domain]["DOCKER_OCTET"] ?? "";
if (!empty($v_docker) && $v_docker_octet == "") {
	$v_docker_octet = "1";
}
// Prefill for a fresh enable: the classic 3000, and the lowest octet none of the user's OTHER
// docker domains already targets - the duplicate reject would bite on save otherwise
if (!empty($v_docker_net) && empty($v_docker)) {
	if ($v_docker_port == "") {
		$v_docker_port = "3000";
	}
	$used_octets = [];
	foreach ((array) $all_web as $dname => $drow) {
		if ($dname != $v_domain && !empty($drow["DOCKER"]) && ($drow["DOCKER_OCTET"] ?? "") != "") {
			$used_octets[(int) $drow["DOCKER_OCTET"]] = true;
		}
	}
	for ($i = 1; $i <= 254; $i++) {
		if (empty($used_octets[$i])) {
			$v_docker_octet = (string) $i;
			break;
		}
	}
}

// Bot rate limiting (Layer B): the domain stores a compact "fam:level,fam:level" field; the family
// table is server-wide. Customers pick their own levels (an admin can do it for them while
// impersonating); only the table itself stays admin-only.
$v_botlimit = [];
foreach (explode(",", (string) ($data[$v_domain]["BOTLIMIT"] ?? "")) as $entry) {
	if (strpos($entry, ":") === false) {
		continue;
	}
	[$bl_fam, $bl_lvl] = explode(":", $entry, 2);
	$v_botlimit[$bl_fam] = $bl_lvl;
}
$botfamilies = [];
$bf = cli_json("h-list-sys-botfamily json");
// Only enabled families: the server config defines rate zones for those alone, so referencing a
// disabled one would break the nginx config test.
foreach (is_array($bf) ? $bf : [] as $bf_name => $bf_data) {
	if (($bf_data["ENABLED"] ?? "no") === "yes") {
		$botfamilies[$bf_name] = $bf_data;
	}
}
$v_aliases = str_replace(",", "\n", $data[$v_domain]["ALIAS"]);
$valiases = explode(",", $data[$v_domain]["ALIAS"]);

$v_ssl = $data[$v_domain]["SSL"];
// Outside the branch: the POST section reads all three whether or not SSL is on
$v_ssl_forcessl = $data[$v_domain]["SSL_FORCE"] ?? "no";
$v_ssl_hsts = $data[$v_domain]["SSL_HSTS"] ?? "no";
$v_http3 = $data[$v_domain]["HTTP3"] ?? "no";
if (!empty($v_ssl)) {
	extract(web_ssl_vars($user, $v_domain));
}
$v_letsencrypt = $data[$v_domain]["LETSENCRYPT"];
if (empty($v_letsencrypt)) {
	$v_letsencrypt = "no";
}
$v_ssl_home = $data[$v_domain]["SSL_HOME"] ?? "";
$v_backend_template = $data[$v_domain]["BACKEND"] ?? "";
$v_php_version = $data[$v_domain]["PHP_VERSION"] ?? "";
$v_nginx_cache = $data[$v_domain]["FASTCGI_CACHE"] ?? "";
$v_nginx_cache_duration = $data[$v_domain]["FASTCGI_DURATION"] ?? "";
$v_nginx_cache_check = "";
if (empty($v_nginx_cache_duration)) {
	$v_nginx_cache_duration = "2m";
	$v_nginx_cache_check = "";
} else {
	$v_nginx_cache_check = "on";
}
$v_proxy_cache = $data[$v_domain]["PROXY_CACHE"] ?? "";
$v_proxy_cache_duration = $data[$v_domain]["PROXY_CACHE_DURATION"] ?? "";
if ($v_proxy_cache == "yes") {
	$v_proxy_cache_check = "on";
} else {
	$v_proxy_cache_check = "";
	if (empty($v_proxy_cache_duration) || $v_proxy_cache_duration == "0s") {
		$v_proxy_cache_duration = "5m";
	}
}
$v_offline = $data[$v_domain]["OFFLINE"] ?? "";
$v_proxy = $data[$v_domain]["PROXY"];
$v_proxy_template = $data[$v_domain]["PROXY"];
$v_proxy_ext = str_replace(",", ", ", $data[$v_domain]["PROXY_EXT"]);
$v_stats = $data[$v_domain]["STATS"];
$v_stats_user = $data[$v_domain]["STATS_USER"];
$v_stats_password = "";

$v_custom_doc_root_prepath = "/home/" . $user_plain . "/web/";

$v_custom_doc_root = "";
$v_custom_doc_domain = "";
$v_custom_doc_folder = "";

if (!empty($data[$v_domain]["CUSTOM_DOCROOT"])) {
	// Not realpath(): an ACL denies the panel user inside customer homes, so it returned false and
	// left "/" here - the form then showed empty fields and the next save reset the docroot.
	$v_custom_doc_root = rtrim($data[$v_domain]["CUSTOM_DOCROOT"], "/") . DIRECTORY_SEPARATOR;
}

if (
	!empty($v_custom_doc_root) &&
	false !==
		preg_match(
			"/\/home\/" . preg_quote($user_plain, "/") . "\/web\/([[:alnum:]].*?)\/public_html\/([[:alnum:]].*)?/",
			$v_custom_doc_root,
			$matches,
		)
) {
	// Regex for extracting target web domain and custom document root. Regex test: https://regex101.com/r/2CLvIF/1

	if (!empty($matches[1])) {
		$v_custom_doc_domain = $matches[1];
	}

	if (!empty($matches[2])) {
		$v_custom_doc_folder = rtrim($matches[2], "/");
	}

	if ($v_custom_doc_domain && !in_array($v_custom_doc_domain, $user_domains)) {
		$v_custom_doc_domain = "";
		$v_custom_doc_folder = "";
	}
}

$redirect_code_options = [301, 302];
$v_redirect = $data[$v_domain]["REDIRECT"];
$v_redirect_code = isset($data[$v_domain]["REDIRECT_CODE"])
	? intval($data[$v_domain]["REDIRECT_CODE"])
	: 302;
if (!in_array($v_redirect, ["www." . $v_domain, $v_domain])) {
	$v_redirect_custom = $v_redirect;
}

$v_ftp_user = $data[$v_domain]["FTP_USER"];
$v_ftp_path = $data[$v_domain]["FTP_PATH"];
if (!empty($v_ftp_user)) {
	$v_ftp_password = "";
}
if (isset($v_custom_doc_domain) && $v_custom_doc_domain != "") {
	$v_ftp_user_prepath = "/home/" . $user_plain . "/web/" . $v_custom_doc_domain;
} else {
	$v_ftp_user_prepath = "/home/" . $user_plain . "/web/" . $v_domain;
}

//$v_ftp_email = $panel[$user]['CONTACT'];
$v_ftp_email = "";
$v_suspended = $data[$v_domain]["SUSPENDED"];
if ($v_suspended == "yes") {
	$v_status = "suspended";
} else {
	$v_status = "active";
}
$v_time = $data[$v_domain]["TIME"];
$v_date = $data[$v_domain]["DATE"];

// List ip addresses
$ips = cli_json("h-list-user-ips " . $user . " json");

// A record written by the CLI holds the public address (get_user_ip substitutes NAT), the IP list
// is keyed by the local one. Unmatched, the select preselects nothing and the save rewrites the IP.
if (!isset($ips[$v_ip])) {
	foreach ($ips as $ip_local => $ip_meta) {
		if (($ip_meta["NAT"] ?? "") === $v_ip) {
			$v_ip = $ip_local;
			break;
		}
	}
}

$v_ip_public = empty($ips[$v_ip]["NAT"]) ? $v_ip : $ips[$v_ip]["NAT"];

// List web templates
$templates = cli_json("h-list-web-templates json");

// List backend templates (pool profiles) and installed PHP versions - the version is its
// own field since #591, so it is offered as a separate control
if (!empty($_SESSION["WEB_BACKEND"])) {
	$backend_templates = cli_json("h-list-web-templates-backend json");

	$php_versions = cli_json("h-list-sys-php json");
}

// List proxy templates
if (!empty($_SESSION["PROXY_SYSTEM"])) {
	$proxy_templates = cli_json("h-list-web-templates-proxy json");
}

// List docker templates - only a docker customer can pick one
$docker_templates = [];
if (!empty($v_docker_net)) {
	$docker_templates = cli_json("h-list-web-templates-docker json");
}

// List web stat engines
$stats = cli_json("h-list-web-stats json");

// One gate per conditionally rendered control: rendered on it, read on it.
// Template and pool choices gate on the real identity; the policy can open them to customers.
$can_edit_templates =
	($_SESSION["adminContext"] ?? "") === "admin" ||
	($_SESSION["POLICY_USER_EDIT_WEB_TEMPLATES"] ?? "") == "yes";
$offer_docker = !empty($v_docker_net);
$offer_docker_template = $offer_docker && count($docker_templates) > 1;
$offer_web_template = empty($v_docker) && $can_edit_templates && is_array($templates) && count($templates) > 0;
$offer_backend = empty($v_docker) && !empty($_SESSION["WEB_BACKEND"]);
$offer_backend_template = $offer_backend && $can_edit_templates;
$offer_proxy = empty($v_docker) && !empty($_SESSION["PROXY_SYSTEM"]);
$offer_proxy_template = $offer_proxy && $can_edit_templates && count($proxy_templates ?? []) > 1;
$offer_proxy_cache = !empty($_SESSION["PROXY_SYSTEM"]) && $_SESSION["PROXY_SYSTEM"] == "nginx";
$offer_fastcgi_cache = empty($v_docker) && $_SESSION["WEB_SYSTEM"] == "nginx";
$offer_http3 =
	$_SESSION["WEB_HTTP3"] == "yes" &&
	($_SESSION["WEB_SYSTEM"] == "nginx" ||
		(!empty($_SESSION["PROXY_SYSTEM"]) && $_SESSION["PROXY_SYSTEM"] == "nginx"));
$offer_botlimit = !empty($botfamilies);
$offer_ftp = $_SESSION["FTP_SYSTEM"] == "proftpd";

// Check POST request
if (!empty($_POST["save"])) {
	$v_domain = $_POST["v_domain"];
	if (!in_array($v_domain, $user_domains)) {
		check_return_code(3, ["Unknown domain"]);
	}
	// Check token
	verify_csrf($_POST);

	// Change web domain IP
	if ($v_ip != $_POST["v_ip"] && empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD .
				"h-change-web-domain-ip " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" " .
				quoteshellarg($_POST["v_ip"]) .
				" 'no'",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		$restart_web = "yes";
		$restart_proxy = "yes";
		unset($output);
	}

	// Change mail domain IP
	if ($v_ip != $_POST["v_ip"] && empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD . "h-list-mail-domain " . $user . " " . quoteshellarg($v_domain) . " json",
			$output,
			$return_var,
		);
		unset($output);
		if ($return_var == 0) {
			exec(
				HESTIA_CMD . "h-rebuild-mail-domain " . $user . " " . quoteshellarg($v_domain),
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			$restart_email = "yes";
		}
	}

	if ($can_edit_templates) {
		// Hidden on apache-web models: the vhost renders from share/, nothing to select
		$post_template = post_or_keep("v_template", $offer_web_template, $v_template);
		if ($offer_web_template && $v_template != $post_template && empty($_SESSION["error_msg"])) {
			exec(
				HESTIA_CMD .
					"h-change-web-domain-tpl " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					quoteshellarg($post_template) .
					" 'no'",
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			$restart_web = "yes";
		}

		// A docker domain has no pool at all
		$post_backend_template = post_or_keep("v_backend_template", $offer_backend_template, $v_backend_template);
		if (
			$offer_backend_template &&
			$v_backend_template != $post_backend_template &&
			empty($_SESSION["error_msg"])
		) {
			$v_backend_template = $post_backend_template;
			exec(
				HESTIA_CMD .
					"h-change-web-domain-backend-tpl " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					quoteshellarg($v_backend_template),
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
		}

	}
	// Change PHP version (its own field since #591)
	$post_php_version = post_or_keep("v_php_version", $offer_backend, $v_php_version);
	if ($offer_backend && $v_php_version != $post_php_version && empty($_SESSION["error_msg"])) {
		$v_php_version = $post_php_version;
		exec(
			HESTIA_CMD .
				"h-change-web-domain-php " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" " .
				quoteshellarg($v_php_version),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
	}

	// Enable/Disable nginx cache. With nothing stored the field shows a 2m default, so what is
	// stored and what the form shows are not the same value.
	$post_nginx_cache_check = post_checkbox("v_nginx_cache_check", $offer_fastcgi_cache, $v_nginx_cache_check, "on", "");
	$post_nginx_cache_duration = post_or_keep("v_nginx_cache_duration", $offer_fastcgi_cache, $v_nginx_cache_duration);
	if (
		$offer_fastcgi_cache &&
		($v_nginx_cache_check != $post_nginx_cache_check ||
			($post_nginx_cache_check == "on" &&
				$v_nginx_cache_duration != $post_nginx_cache_duration)) &&
		empty($_SESSION["error_msg"])
	) {
		if ($post_nginx_cache_check == "on") {
			if (empty($post_nginx_cache_duration)) {
				$post_nginx_cache_duration = "2m";
			}
			exec(
				HESTIA_CMD .
					"h-add-fastcgi-cache " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					quoteshellarg($post_nginx_cache_duration),
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
		} else {
			exec(
				HESTIA_CMD . "h-delete-fastcgi-cache " . $user . " " . quoteshellarg($v_domain),
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
		}
		$restart_web = "yes";
	}

	// Proxy support, template and extensions. A docker domain renders none of it.
	$post_proxy = post_checkbox("v_proxy", $offer_proxy, empty($v_proxy) ? "" : "on", "on", "");
	$post_proxy_ext = post_or_keep("v_proxy_ext", $offer_proxy, $v_proxy_ext);
	if ($offer_proxy && !empty($v_proxy) && empty($post_proxy) && empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD .
				"h-delete-web-domain-proxy " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" 'no'",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		unset($v_proxy);
		$restart_web = "yes";
	}

	// Change proxy template / Update extension list
	if ($offer_proxy && !empty($v_proxy) && !empty($post_proxy) && empty($_SESSION["error_msg"])) {
		$ext = preg_replace("/\n/", " ", $post_proxy_ext);
		$ext = preg_replace("/,/", " ", $ext);
		$ext = preg_replace("/\s+/", " ", $ext);
		$ext = trim($ext);
		$ext = str_replace(" ", ", ", $ext);
		// Absent for a customer and wherever there is only one to pick
		$post_proxy_template = post_or_keep("v_proxy_template", $offer_proxy_template, $v_proxy_template);
		if ($v_proxy_template != $post_proxy_template || $v_proxy_ext != $ext) {
			$ext = str_replace(", ", ",", $ext);
			$v_proxy_template = $post_proxy_template;
			exec(
				HESTIA_CMD .
					"h-change-web-domain-proxy-tpl " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					quoteshellarg($v_proxy_template) .
					" " .
					quoteshellarg($ext) .
					" 'no'",
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			$v_proxy_ext = str_replace(",", ", ", $ext);
			unset($output);
			$restart_proxy = "yes";
		}
	}

	// Add proxy support
	if ($offer_proxy && empty($v_proxy) && !empty($post_proxy) && empty($_SESSION["error_msg"])) {
		// template choice stays behind the real-identity gate; a customer enable gets default
		$v_proxy_template = post_or_keep("v_proxy_template", $offer_proxy_template, "default");
		if (!empty($post_proxy_ext)) {
			$ext = preg_replace("/\n/", " ", $post_proxy_ext);
			$ext = preg_replace("/,/", " ", $ext);
			$ext = preg_replace("/\s+/", " ", $ext);
			$ext = trim($ext);
			$ext = str_replace(" ", ",", $ext);
			$v_proxy_ext = str_replace(",", ", ", $ext);
		}
		exec(
			HESTIA_CMD .
				"h-add-web-domain-proxy " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" " .
				quoteshellarg($v_proxy_template) .
				" " .
				quoteshellarg($ext) .
				" 'no'",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$restart_proxy = "yes";
	}

	// Enable/Disable proxy cache
	$post_proxy_cache_check = post_checkbox("v_proxy_cache_check", $offer_proxy_cache, $v_proxy_cache_check, "on", "");
	$post_proxy_cache_duration = post_or_keep("v_proxy_cache_duration", $offer_proxy_cache, $v_proxy_cache_duration);
	if (
		$offer_proxy_cache &&
		($v_proxy_cache_check != $post_proxy_cache_check ||
			($post_proxy_cache_check == "on" &&
				$v_proxy_cache_duration != $post_proxy_cache_duration)) &&
		empty($_SESSION["error_msg"])
	) {
		if ($post_proxy_cache_check == "on") {
			if (empty($post_proxy_cache_duration)) {
				$post_proxy_cache_duration = "5m";
			}
			exec(
				HESTIA_CMD .
					"h-add-web-domain-cache " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					quoteshellarg($post_proxy_cache_duration),
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
		} else {
			exec(
				HESTIA_CMD . "h-delete-web-domain-cache " . $user . " " . quoteshellarg($v_domain),
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
		}
		$restart_web = "yes";
	}

	// Take the website offline / back online (customer switch, serves 503)
	if (empty($_POST["v_offline_check"])) {
		$_POST["v_offline_check"] = "";
	}
	$v_offline_check = $v_offline == "yes" ? "on" : "";
	if ($v_offline_check != $_POST["v_offline_check"] && empty($_SESSION["error_msg"])) {
		$offline_cmd =
			$_POST["v_offline_check"] == "on"
				? "h-add-web-domain-offline"
				: "h-delete-web-domain-offline";
		exec(
			HESTIA_CMD . $offline_cmd . " " . $user . " " . quoteshellarg($v_domain),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$restart_web = "yes";
	}

	// Change aliases
	if (empty($_SESSION["error_msg"])) {
		$waliases = preg_replace("/\n/", " ", $_POST["v_aliases"]);
		$waliases = preg_replace("/,/", " ", $waliases);
		$waliases = preg_replace("/\s+/", " ", $waliases);
		$waliases = trim($waliases);
		$aliases = explode(" ", $waliases);
		$v_aliases = str_replace(" ", "\n", $waliases);
		$result = array_diff($valiases, $aliases);
		foreach ($result as $alias) {
			if (empty($_SESSION["error_msg"]) && !empty($alias)) {
				$restart_web = "yes";
				$restart_proxy = "yes";
				exec(
					HESTIA_CMD .
						"h-delete-web-domain-alias " .
						$user .
						" " .
						quoteshellarg($v_domain) .
						" " .
						quoteshellarg($alias) .
						" 'no'",
					$output,
					$return_var,
				);
				check_return_code($return_var, $output);
				unset($output);

			}
		}

		$result = array_diff($aliases, $valiases);
		foreach ($result as $alias) {
			if (empty($_SESSION["error_msg"]) && !empty($alias)) {
				$restart_web = "yes";
				$restart_proxy = "yes";
				exec(
					HESTIA_CMD .
						"h-add-web-domain-alias " .
						$user .
						" " .
						quoteshellarg($v_domain) .
						" " .
						quoteshellarg($alias) .
						" 'no'",
					$output,
					$return_var,
				);
				check_return_code($return_var, $output);
				unset($output);
			}
		}

		// Regenerate LE if aliases are different
		if (
			!empty($_POST["v_ssl"]) &&
			$v_letsencrypt == "yes" &&
			!empty($_POST["v_letsencrypt"]) &&
			empty($_SESSION["error_msg"])
		) {
			// If aliases are different from stored aliases
			if (array_diff($valiases, $aliases) || array_diff($aliases, $valiases)) {
				// Add certificate with new aliases
				$l_aliases = str_replace("\n", ",", $v_aliases);
				exec(
					HESTIA_CMD .
						"h-add-letsencrypt-domain " .
						$user .
						" " .
						quoteshellarg($v_domain) .
						" " .
						quoteshellarg($l_aliases) .
						" ''",
					$output,
					$return_var,
				);
				check_return_code($return_var, $output);
				unset($output);
				$v_letsencrypt = "yes";
				$v_ssl = "yes";
				$restart_web = "yes";
				$restart_proxy = "yes";

				extract(web_ssl_vars($user, $v_domain));
			}
		}

		if (!empty($v_stats) && $_POST["v_stats"] == $v_stats && empty($_SESSION["error_msg"])) {
			// Update statistics configuration when changing domain aliases
			$v_stats = quoteshellarg($_POST["v_stats"]);
			exec(
				HESTIA_CMD .
					"h-change-web-domain-stats " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					$v_stats,
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
		}
	}

	// Change SSL certificate
	if (
		$v_letsencrypt == "no" &&
		empty($_POST["v_letsencrypt"]) &&
		$v_ssl == "yes" &&
		!empty($_POST["v_ssl"]) &&
		empty($_SESSION["error_msg"])
	) {
		if (
			$v_ssl_crt != str_replace("\r\n", "\n", $_POST["v_ssl_crt"]) ||
			$v_ssl_key != str_replace("\r\n", "\n", $_POST["v_ssl_key"]) ||
			$v_ssl_ca != str_replace("\r\n", "\n", $_POST["v_ssl_ca"])
		) {
			exec("mktemp -d", $mktemp_output, $return_var);
			$tmpdir = $mktemp_output[0];

			// Certificate
			if (!empty($_POST["v_ssl_crt"])) {
				$fp = fopen($tmpdir . "/" . $v_domain . ".crt", "w");
				fwrite($fp, str_replace("\r\n", "\n", $_POST["v_ssl_crt"]));
				fwrite($fp, "\n");
				fclose($fp);
			}

			// Key
			if (!empty($_POST["v_ssl_key"])) {
				$fp = fopen($tmpdir . "/" . $v_domain . ".key", "w");
				fwrite($fp, str_replace("\r\n", "\n", $_POST["v_ssl_key"]));
				fwrite($fp, "\n");
				fclose($fp);
			}

			// CA
			if (!empty($_POST["v_ssl_ca"])) {
				$fp = fopen($tmpdir . "/" . $v_domain . ".ca", "w");
				fwrite($fp, str_replace("\r\n", "\n", $_POST["v_ssl_ca"]));
				fwrite($fp, "\n");
				fclose($fp);
			}

			exec(
				HESTIA_CMD .
					"h-change-web-domain-sslcert " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					$tmpdir .
					" 'no'",
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			$restart_web = "yes";
			$restart_proxy = "yes";

			extract(web_ssl_vars($user, $v_domain));

			// Cleanup certificate tempfiles
			if (!empty($_POST["v_ssl_crt"])) {
				unlink($tmpdir . "/" . $v_domain . ".crt");
			}
			if (!empty($_POST["v_ssl_key"])) {
				unlink($tmpdir . "/" . $v_domain . ".key");
			}
			if (!empty($_POST["v_ssl_ca"])) {
				unlink($tmpdir . "/" . $v_domain . ".ca");
			}
			rmdir($tmpdir);
		}
	}

	// Delete Lets Encrypt support
	if (
		$v_letsencrypt == "yes" &&
		(empty($_POST["v_letsencrypt"]) || empty($_POST["v_ssl"])) &&
		empty($_SESSION["error_msg"])
	) {
		exec(
			HESTIA_CMD .
				"h-delete-letsencrypt-domain " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" ''",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$v_ssl_crt = "";
		$v_ssl_key = "";
		$v_ssl_ca = "";
		$v_letsencrypt = "no";
		$v_letsencrypt_deleted = "yes";
		$v_ssl = "no";
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	// Delete SSL certificate
	if ($v_ssl == "yes" && empty($_POST["v_ssl"]) && empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD .
				"h-delete-web-domain-ssl " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" 'no'",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$v_ssl_crt = "";
		$v_ssl_key = "";
		$v_ssl_ca = "";
		$v_ssl = "no";
		$v_ssl_forcessl = "no";
		$v_ssl_hsts = "no";
		$v_http3 = "no";
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	// Add Lets Encrypt support
	if (
		!empty($_POST["v_ssl"]) &&
		$v_letsencrypt == "no" &&
		!empty($_POST["v_letsencrypt"]) &&
		empty($_SESSION["error_msg"])
	) {
		$l_aliases = str_replace("\n", ",", $v_aliases);
		exec(
			HESTIA_CMD .
				"h-add-letsencrypt-domain " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" " .
				quoteshellarg($l_aliases) .
				" ''",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		if ($return_var != 0) {
			$v_letsencrypt = "no";
		} else {
			$v_letsencrypt = "yes";
		}
		$v_ssl = "yes";
		if ($_POST["v_ssl_forcessl"] == "on") {
			$v_ssl_forcessl = "yes";
		} else {
			$v_ssl_forcessl = "no";
		}
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	// Add SSL certificate
	if (
		$v_ssl == "no" &&
		!empty($_POST["v_ssl"]) &&
		empty($v_letsencrypt_deleted) &&
		empty($_SESSION["error_msg"])
	) {
		if (empty($_POST["v_ssl_crt"])) {
			$errors[] = "ssl certificate";
		}
		if (empty($_POST["v_ssl_key"])) {
			$errors[] = "ssl key";
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
			exec("mktemp -d", $mktemp_output, $return_var);
			$tmpdir = $mktemp_output[0];

			// Certificate
			if (!empty($_POST["v_ssl_crt"])) {
				$fp = fopen($tmpdir . "/" . $v_domain . ".crt", "w");
				fwrite($fp, str_replace("\r\n", "\n", $_POST["v_ssl_crt"]));
				fclose($fp);
			}

			// Key
			if (!empty($_POST["v_ssl_key"])) {
				$fp = fopen($tmpdir . "/" . $v_domain . ".key", "w");
				fwrite($fp, str_replace("\r\n", "\n", $_POST["v_ssl_key"]));
				fclose($fp);
			}

			// CA
			if (!empty($_POST["v_ssl_ca"])) {
				$fp = fopen($tmpdir . "/" . $v_domain . ".ca", "w");
				fwrite($fp, str_replace("\r\n", "\n", $_POST["v_ssl_ca"]));
				fclose($fp);
			}
			//keep using the original value for v_ssl_home
			exec(
				HESTIA_CMD .
					"h-add-web-domain-ssl " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					$tmpdir .
					" " .
					quoteshellarg($v_ssl_home) .
					" 'no'",
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			$v_ssl = "yes";
			$restart_web = "yes";
			$restart_proxy = "yes";

			extract(web_ssl_vars($user, $v_domain));

			// Cleanup certificate tempfiles
			if (!empty($_POST["v_ssl_crt"])) {
				unlink($tmpdir . "/" . $v_domain . ".crt");
			}
			if (!empty($_POST["v_ssl_key"])) {
				unlink($tmpdir . "/" . $v_domain . ".key");
			}
			if (!empty($_POST["v_ssl_ca"])) {
				unlink($tmpdir . "/" . $v_domain . ".ca");
			}
			rmdir($tmpdir);
		}
	}

	// Add Force SSL
	if (
		!empty($_POST["v_ssl_forcessl"]) &&
		!empty($_POST["v_ssl"]) &&
		empty($_SESSION["error_msg"])
	) {
		exec(
			HESTIA_CMD . "h-add-web-domain-ssl-force " . $user . " " . quoteshellarg($v_domain),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$v_ssl_forcessl = "yes";
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	// Add SSL HSTS
	if (!empty($_POST["v_ssl_hsts"]) && !empty($_POST["v_ssl"]) && empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD . "h-add-web-domain-ssl-hsts " . $user . " " . quoteshellarg($v_domain),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$v_ssl_hsts = "yes";
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	// Add HTTP/3 (nginx front only; the command refuses where nginx lacks http_v3). Both arms run
	// off the difference to the stored field, so an unoffered checkbox moves nothing.
	$post_http3 = post_checkbox("v_http3", $offer_http3, $v_http3 == "yes" ? "on" : "", "on", "");
	if (
		!empty($post_http3) &&
		$v_http3 != "yes" &&
		!empty($_POST["v_ssl"]) &&
		empty($_SESSION["error_msg"])
	) {
		exec(
			HESTIA_CMD . "h-add-web-domain-http3 " . $user . " " . quoteshellarg($v_domain),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$v_http3 = "yes";
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	// Delete Force SSL
	if (
		$v_ssl_forcessl == "yes" &&
		empty($_POST["v_ssl_forcessl"]) &&
		empty($_SESSION["error_msg"])
	) {
		exec(
			HESTIA_CMD . "h-delete-web-domain-ssl-force " . $user . " " . quoteshellarg($v_domain),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$v_ssl_forcessl = "no";
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	// Delete SSL HSTS
	if ($v_ssl_hsts == "yes" && empty($_POST["v_ssl_hsts"]) && empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD . "h-delete-web-domain-ssl-hsts " . $user . " " . quoteshellarg($v_domain),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$v_ssl_hsts = "no";
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	// Delete HTTP/3. The field is what a rebuild reconciles from, so it must survive an absent box.
	if ($v_http3 == "yes" && empty($post_http3) && empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD . "h-delete-web-domain-http3 " . $user . " " . quoteshellarg($v_domain),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$v_http3 = "no";
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	// Docker proxy (#566/#592): enable or retarget re-runs the add command (it updates the
	// fields and rebuilds); the command itself validates port, octet, duplicates and wildcards
	if ($offer_docker && empty($_SESSION["error_msg"])) {
		$post_docker = post_checkbox("v_docker", $offer_docker, empty($v_docker) ? "" : "on", "on", "");
		// Digits only, then the same ranges the command enforces - so a typo comes back as a
		// sentence here instead of a command error, and nothing but a number ever reaches the shell.
		$post_docker_port = preg_replace("/\D/", "", post_or_keep("v_docker_port", $offer_docker, $v_docker_port));
		$post_docker_octet = preg_replace("/\D/", "", post_or_keep("v_docker_octet", $offer_docker, $v_docker_octet));
		if (!empty($post_docker)) {
			if ($post_docker_port === "" || (int) $post_docker_port < 1024 || (int) $post_docker_port > 65535) {
				$_SESSION["error_msg"] = _("Container port must be a number between 1024 and 65535.");
			} elseif ($post_docker_octet === "" || (int) $post_docker_octet < 1 || (int) $post_docker_octet > 254) {
				$_SESSION["error_msg"] = _("Container address must end in a number between 1 and 254.");
			}
		}
		// Absent select (single template, or none offered) keeps what the domain has
		$post_docker_tpl = post_or_keep("v_docker_template", $offer_docker_template, $v_docker ?: "default");
		if (
			!empty($post_docker) &&
			empty($_SESSION["error_msg"]) &&
			(empty($v_docker) ||
				$post_docker_port != $v_docker_port ||
				$post_docker_octet != $v_docker_octet ||
				$post_docker_tpl != $v_docker)
		) {
			exec(
				HESTIA_CMD .
					"h-add-web-domain-docker " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					quoteshellarg($post_docker_port) .
					" " .
					quoteshellarg($post_docker_octet) .
					" " .
					quoteshellarg($post_docker_tpl),
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			if (empty($_SESSION["error_msg"])) {
				$v_docker = $post_docker_tpl;
				$v_docker_port = $post_docker_port;
				$v_docker_octet = $post_docker_octet;
				$restart_web = "yes";
				$restart_proxy = "yes";
			}
		} elseif (empty($post_docker) && !empty($v_docker)) {
			exec(
				HESTIA_CMD . "h-delete-web-domain-docker " . $user . " " . quoteshellarg($v_domain),
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			$v_docker = "";
			$restart_web = "yes";
			$restart_proxy = "yes";
		}
	}

	// One command per changed family, each deferring the restart. Safe for customers: $user is the
	// effective session user, and the CLI validates the domain against that user's own object file.
	if ($offer_botlimit && is_array($_POST["v_botlimit"] ?? null)) {
		foreach ($botfamilies as $bl_fam => $bl_unused) {
			// The family name is a key from the server-side table, never from the request.
			$bl_new = $_POST["v_botlimit"][$bl_fam] ?? "off";
			if (!in_array($bl_new, ["off", "lenient", "strict"], true)) {
				continue;
			}
			$bl_old = $v_botlimit[$bl_fam] ?? "off";
			if ($bl_new === $bl_old || !empty($_SESSION["error_msg"])) {
				continue;
			}
			exec(
				HESTIA_CMD .
					"h-change-web-domain-botlimit " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					quoteshellarg($bl_fam) .
					" " .
					quoteshellarg($bl_new) .
					" 'no'",
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			if ($bl_new === "off") {
				unset($v_botlimit[$bl_fam]);
			} else {
				$v_botlimit[$bl_fam] = $bl_new;
			}
			$restart_web = "yes";
			$restart_proxy = "yes";
		}
	}

	// Delete web stats
	if (!empty($v_stats) && $_POST["v_stats"] == "none" && empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD . "h-delete-web-domain-stats " . $user . " " . quoteshellarg($v_domain),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$v_stats = "";
	}

	// Change web stats engine
	if (!empty($v_stats) && $_POST["v_stats"] != $v_stats && empty($_SESSION["error_msg"])) {
		$v_stats = quoteshellarg($_POST["v_stats"]);
		exec(
			HESTIA_CMD .
				"h-change-web-domain-stats " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" " .
				$v_stats,
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
	}

	// Add web stats
	if (empty($v_stats) && $_POST["v_stats"] != "none" && empty($_SESSION["error_msg"])) {
		$v_stats = quoteshellarg($_POST["v_stats"]);
		exec(
			HESTIA_CMD .
				"h-add-web-domain-stats " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" " .
				$v_stats,
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
	}

	// Delete web stats authorization
	if (!empty($v_stats_user) && empty($_POST["v_stats_auth"]) && empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD . "h-delete-web-domain-stats-user " . $user . " " . quoteshellarg($v_domain),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		$v_stats_user = "";
		$v_stats_password = "";
	}

	// Change web stats user or password
	if (empty($v_stats_user) && !empty($_POST["v_stats_auth"]) && empty($_SESSION["error_msg"])) {
		if (empty($_POST["v_stats_user"])) {
			$errors[] = _("Username");
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
			$v_stats_user = quoteshellarg($_POST["v_stats_user"]);
			$v_stats_password = tempnam("/tmp", "vst");
			$fp = fopen($v_stats_password, "w");
			fwrite($fp, $_POST["v_stats_password"] . "\n");
			fclose($fp);
			exec(
				HESTIA_CMD .
					"h-add-web-domain-stats-user " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					$v_stats_user .
					" " .
					$v_stats_password,
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			unlink($v_stats_password);
			$v_stats_password = quoteshellarg($_POST["v_stats_password"]);
		}
	}

	// Add web stats authorization
	if (!empty($v_stats_user) && !empty($_POST["v_stats_auth"]) && empty($_SESSION["error_msg"])) {
		if (empty($_POST["v_stats_user"])) {
			$errors[] = _("Username");
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
		if (
			$v_stats_user != $_POST["v_stats_user"] ||
			(!empty($_POST["v_stats_password"]) && empty($_SESSION["error_msg"]))
		) {
			$v_stats_user = quoteshellarg($_POST["v_stats_user"]);
			$v_stats_password = tempnam("/tmp", "vst");
			$fp = fopen($v_stats_password, "w");
			fwrite($fp, $_POST["v_stats_password"] . "\n");
			fclose($fp);
			exec(
				HESTIA_CMD .
					"h-add-web-domain-stats-user " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					$v_stats_user .
					" " .
					$v_stats_password,
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			unlink($v_stats_password);
			$v_stats_password = quoteshellarg($_POST["v_stats_password"]);
		}
	}

	// Update ftp account. No proftpd, no section - and no way in for a hand-made POST either.
	if ($offer_ftp && !empty($_POST["v_ftp_user"])) {
		$v_ftp_users_updated = [];
		foreach ($_POST["v_ftp_user"] as $i => $v_ftp_user_data) {
			if (empty($v_ftp_user_data["v_ftp_user"])) {
				continue;
			}

			// $user is shell-quoted ('bob'), so this pattern never matched and the prefix stayed
			$v_ftp_user_data["v_ftp_user"] = preg_replace(
				"/^" . preg_quote($user_plain, "/") . "_/i",
				"",
				$v_ftp_user_data["v_ftp_user"],
			);
			if ($v_ftp_user_data["is_new"] == 1 && !empty($_POST["v_ftp"])) {
				if (
					!empty($v_ftp_user_data["v_ftp_email"]) &&
					!filter_var($v_ftp_user_data["v_ftp_email"], FILTER_VALIDATE_EMAIL)
				) {
					$_SESSION["error_msg"] = _("Please enter a valid email address.");
				}
				// per account: a shared list made every later account inherit the first one's error,
				// and $i here would shadow the key of the loop this sits in
				$errors = [];
				if (empty($v_ftp_user_data["v_ftp_user"])) {
					$errors[] = "ftp user";
				}
				if (!empty($errors[0])) {
					foreach ($errors as $err_i => $error) {
						if ($err_i == 0) {
							$error_msg = $error;
						} else {
							$error_msg = $error_msg . ", " . $error;
						}
					}
					$_SESSION["error_msg"] = sprintf(_('Field "%s" can not be blank.'), $error_msg);
				}

				// Add ftp account
				$v_ftp_username_for_emailing = $v_ftp_user_data["v_ftp_user"];
				$v_ftp_username = $v_ftp_user_data["v_ftp_user"];
				$v_ftp_username_full = $user . "_" . $v_ftp_user_data["v_ftp_user"];
				$v_ftp_user = quoteshellarg($v_ftp_username);
				$v_ftp_path = quoteshellarg(trim($v_ftp_user_data["v_ftp_path"]));
				if (empty($_SESSION["error_msg"])) {
					$v_ftp_password = tempnam("/tmp", "vst");
					$fp = fopen($v_ftp_password, "w");
					fwrite($fp, $v_ftp_user_data["v_ftp_password"] . "\n");
					fclose($fp);
					exec(
						HESTIA_CMD .
							"h-add-web-domain-ftp " .
							$user .
							" " .
							quoteshellarg($v_domain) .
							" " .
							$v_ftp_user .
							" " .
							$v_ftp_password .
							" " .
							$v_ftp_path,
						$output,
						$return_var,
					);
					check_return_code($return_var, $output);
					if (!empty($v_ftp_user_data["v_ftp_email"]) && empty($_SESSION["error_msg"])) {
						$to = $v_ftp_user_data["v_ftp_email"];
						$hostname = get_hostname();
						$from = !empty($_SESSION["FROM_EMAIL"])
							? $_SESSION["FROM_EMAIL"]
							: "noreply@" . $hostname;
						$from_name = !empty($_SESSION["FROM_NAME"])
							? $_SESSION["FROM_NAME"]
							: $_SESSION["APP_NAME"];
						// $data holds the domain, not the user - its LANGUAGE key was always null
						$template = get_email_template("ftpaccount_created", $_SESSION["language"]);
						if (!empty($template)) {
							preg_match("/<subject>(.*?)<\/subject>/si", $template, $matches);
							$subject = $matches[1];
							$subject = str_replace(
								["{{hostname}}", "{{appname}}", "{{username}}", "{{domain}}"],
								[
									get_hostname(),
									$_SESSION["APP_NAME"],
									$user_plain . "_" . $v_ftp_username_for_emailing,
									$v_domain,
								],
								$subject,
							);
							$template = str_replace($matches[0], "", $template);
						} else {
							$template = _(
								"FTP account has been created and ready to use.\n" .
									"\n" .
									"Hostname: {{domain}}\n" .
									"Username: {{username}}\n" .
									"Password: {{password}}\n" .
									"\n" .
									"Best regards,\n" .
									"\n" .
									"--\n" .
									"{{appname}}",
							);
						}
						if (empty($subject)) {
							$subject = str_replace(
								["{{subject}}", "{{hostname}}", "{{appname}}"],
								[
									sprintf(
										_("FTP Account Credentials: %s"),
										$user_plain . "_" . $v_ftp_username_for_emailing,
									),
									get_hostname(),
									$_SESSION["APP_NAME"],
								],
								$_SESSION["SUBJECT_EMAIL"],
							);
						}

						$mailtext = translate_email($template, [
							"domain" => htmlentities($v_domain),
							"username" => htmlentities(
								$user_plain . "_" . $v_ftp_username_for_emailing,
							),
							"password" => htmlentities($v_ftp_user_data["v_ftp_password"]),
							"appname" => $_SESSION["APP_NAME"],
						]);

						send_email($to, $subject, $mailtext, $from, $from_name);
						unset($v_ftp_email);
					}
					unset($output);
					unlink($v_ftp_password);
					$v_ftp_password = quoteshellarg($v_ftp_user_data["v_ftp_password"]);
				}

				if ($return_var == 0) {
					$v_ftp_password = "";
					$v_ftp_user_data["is_new"] = 0;
				} else {
					$v_ftp_user_data["is_new"] = 1;
				}

				$v_ftp_users_updated[] = [
					"is_new" => empty($_SESSION["error_msg"]) ? 0 : 1,
					"v_ftp_user" => $v_ftp_username_full,
					"v_ftp_password" => $v_ftp_password,
					"v_ftp_path" => $v_ftp_user_data["v_ftp_path"],
					"v_ftp_email" => $v_ftp_user_data["v_ftp_email"],
					"v_ftp_pre_path" => $v_ftp_user_prepath,
				];

				continue;
			}

			// Delete FTP account
			if ($v_ftp_user_data["delete"] == 1) {
				$v_ftp_username = $user_plain . "_" . $v_ftp_user_data["v_ftp_user"];
				exec(
					HESTIA_CMD .
						"h-delete-web-domain-ftp " .
						$user .
						" " .
						quoteshellarg($v_domain) .
						" " .
						quoteshellarg($v_ftp_username),
					$output,
					$return_var,
				);
				check_return_code($return_var, $output);
				unset($output);

				continue;
			}

			if (!empty($_POST["v_ftp"])) {
				$errors = [];
				if (empty($v_ftp_user_data["v_ftp_user"])) {
					$errors[] = _("Username");
				}
				if (!empty($errors[0])) {
					foreach ($errors as $err_i => $error) {
						if ($err_i == 0) {
							$error_msg = $error;
						} else {
							$error_msg = $error_msg . ", " . $error;
						}
					}
					$_SESSION["error_msg"] = sprintf(_('Field "%s" can not be blank.'), $error_msg);
				}

				// Change FTP account path
				$v_ftp_username_for_emailing = $v_ftp_user_data["v_ftp_user"];
				$v_ftp_username = $user_plain . "_" . $v_ftp_user_data["v_ftp_user"]; //preg_replace("/^".$user."_/", "", $v_ftp_user_data['v_ftp_user']);
				$v_ftp_username = quoteshellarg($v_ftp_username);
				$v_ftp_path = quoteshellarg(trim($v_ftp_user_data["v_ftp_path"]));
				if (quoteshellarg(trim($v_ftp_user_data["v_ftp_path_prev"])) != $v_ftp_path) {
					exec(
						HESTIA_CMD .
							"h-change-web-domain-ftp-path " .
							$user .
							" " .
							quoteshellarg($v_domain) .
							" " .
							$v_ftp_username .
							" " .
							$v_ftp_path,
						$output,
						$return_var,
					);
					check_return_code($return_var, $output);
					unset($output);
				}
				// Change FTP account password
				if (!empty($v_ftp_user_data["v_ftp_password"])) {
					$v_ftp_password = tempnam("/tmp", "vst");
					$fp = fopen($v_ftp_password, "w");
					fwrite($fp, $v_ftp_user_data["v_ftp_password"] . "\n");
					fclose($fp);
					exec(
						HESTIA_CMD .
							"h-change-web-domain-ftp-password " .
							$user .
							" " .
							quoteshellarg($v_domain) .
							" " .
							$v_ftp_username .
							" " .
							$v_ftp_password,
						$output,
						$return_var,
					);
					check_return_code($return_var, $output);
					unset($output);
					unlink($v_ftp_password);
				}
				if (!empty($v_ftp_user_data["v_ftp_email"]) && empty($_SESSION["error_msg"])) {
					$to = $v_ftp_user_data["v_ftp_email"];
					$hostname = get_hostname();
					$from = !empty($_SESSION["FROM_EMAIL"])
						? $_SESSION["FROM_EMAIL"]
						: "noreply@" . $hostname;
					$from_name = !empty($_SESSION["FROM_NAME"])
						? $_SESSION["FROM_NAME"]
						: $_SESSION["APP_NAME"];
					$template = get_email_template("ftpaccount_created", $_SESSION["language"]);
					if (!empty($template)) {
						preg_match("/<subject>(.*?)<\/subject>/si", $template, $matches);
						$subject = $matches[1];
						$subject = str_replace(
							["{{hostname}}", "{{appname}}", "{{username}}", "{{domain}}"],
							[
								get_hostname(),
								$_SESSION["APP_NAME"],
								$user_plain . "_" . $v_ftp_username_for_emailing,
								$v_domain,
							],
							$subject,
						);
						$template = str_replace($matches[0], "", $template);
					} else {
						$template = _(
							"FTP account has been created and ready to use.\n" .
								"\n" .
								"Hostname: {{domain}}\n" .
								"Username: {{username}}\n" .
								"Password: {{password}}\n" .
								"\n" .
								"Best regards,\n" .
								"\n" .
								"--\n" .
								"{{appname}}",
						);
					}
					if (empty($subject)) {
						$subject = str_replace(
							["{{subject}}", "{{hostname}}", "{{appname}}"],
							[
								sprintf(
									_("FTP Account Credentials: %s"),
									$user_plain . "_" . $v_ftp_username_for_emailing,
								),
								get_hostname(),
								$_SESSION["APP_NAME"],
							],
							$_SESSION["SUBJECT_EMAIL"],
						);
					}

					$mailtext = translate_email($template, [
						"domain" => $v_domain,
						"username" => $user_plain . "_" . $v_ftp_username_for_emailing,
						"password" => $v_ftp_user_data["v_ftp_password"],
						"appname" => $_SESSION["APP_NAME"],
					]);

					send_email($to, $subject, $mailtext, $from, $from_name);
					unset($v_ftp_email);
				}
				if (empty($v_ftp_user_data["v_ftp_email"])) {
					$v_ftp_user_data["v_ftp_email"] = "";
				}
				$v_ftp_users_updated[] = [
					"is_new" => 0,
					"v_ftp_user" => $v_ftp_username,
					"v_ftp_password" => $v_ftp_user_data["v_ftp_password"],
					"v_ftp_path" => $v_ftp_user_data["v_ftp_path"],
					"v_ftp_email" => $v_ftp_user_data["v_ftp_email"],
					"v_ftp_pre_path" => $v_ftp_user_prepath,
				];
			}
		}
	}
	//custom docoot with check box disabled
	if (!empty($v_custom_doc_root) && empty($_POST["v_custom_doc_root_check"])) {
		exec(
			HESTIA_CMD .
				"h-change-web-domain-docroot " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" default",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		unset($_POST["h-custom-doc-domain"], $_POST["h-custom-doc-folder"]);
		$v_custom_doc_root = "";
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	if (
		!empty($_POST["h-custom-doc-domain"]) &&
		!empty($_POST["v_custom_doc_root_check"]) &&
		$v_custom_doc_root_prepath . $v_custom_doc_domain . "/public_html" . $v_custom_doc_folder !=
			$v_custom_doc_root
	) {
		if ($_POST["h-custom-doc-domain"] == $v_domain && empty($_POST["h-custom-doc-folder"])) {
			exec(
				HESTIA_CMD .
					"h-change-web-domain-docroot " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" default",
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
		} else {
			$v_custom_doc_folder = quoteshellarg(rtrim($_POST["h-custom-doc-folder"], "/"));
			$v_custom_doc_domain = quoteshellarg($_POST["h-custom-doc-domain"]);

			exec(
				HESTIA_CMD .
					"h-change-web-domain-docroot " .
					$user .
					" " .
					quoteshellarg($v_domain) .
					" " .
					$v_custom_doc_domain .
					" " .
					$v_custom_doc_folder .
					" yes",
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			$v_custom_doc_root =
				$v_custom_doc_root_prepath .
				trim($_POST["h-custom-doc-domain"], "'") .
				"/public_html" .
				rtrim($_POST["h-custom-doc-folder"] ?? "", "/");
		}
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	if (!empty($v_redirect) && empty($_POST["h-redirect-checkbox"])) {
		exec(
			HESTIA_CMD . "h-delete-web-domain-redirect " . $user . " " . quoteshellarg($v_domain),
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
		unset($_POST["h-redirect"]);
		$restart_web = "yes";
		$restart_proxy = "yes";
	}

	if (!empty($_POST["h-redirect"]) && !empty($_POST["h-redirect-checkbox"])) {
		if (empty($v_redirect)) {
			if ($_POST["h-redirect"] == "custom" && empty($_POST["h-redirect-custom"])) {
			} else {
				if ($_POST["h-redirect"] == "custom") {
					$_POST["h-redirect"] = $_POST["h-redirect-custom"];
				}
				exec(
					HESTIA_CMD .
						"h-add-web-domain-redirect " .
						$user .
						" " .
						quoteshellarg($v_domain) .
						" " .
						quoteshellarg($_POST["h-redirect"]) .
						" " .
						quoteshellarg($_POST["h-redirect-code"]),
					$output,
					$return_var,
				);
				check_return_code($return_var, $output);
				unset($output);
				$restart_web = "yes";
				$restart_proxy = "yes";
			}
		} else {
			if ($_POST["h-redirect"] == "custom") {
				$_POST["h-redirect"] = $_POST["h-redirect-custom"];
			}
			if (
				$_POST["h-redirect"] != $v_redirect ||
				$_POST["h-redirect-code"] != $v_redirect_code
			) {
				exec(
					HESTIA_CMD .
						"h-add-web-domain-redirect " .
						$user .
						" " .
						quoteshellarg($v_domain) .
						" " .
						quoteshellarg($_POST["h-redirect"]) .
						" " .
						quoteshellarg($_POST["h-redirect-code"]),
					$output,
					$return_var,
				);
				check_return_code($return_var, $output);
				unset($output);
				$restart_web = "yes";
				$restart_proxy = "yes";
			}
		}
	}
	// Restart web server
	if (!empty($restart_web) && empty($_SESSION["error_msg"])) {
		exec(HESTIA_CMD . "h-restart-web", $output, $return_var);
		check_return_code($return_var, $output);
		unset($output);
	}

	// Restart proxy server
	if (
		!empty($_SESSION["PROXY_SYSTEM"]) &&
		!empty($restart_proxy) &&
		empty($_SESSION["error_msg"])
	) {
		exec(HESTIA_CMD . "h-restart-proxy", $output, $return_var);
		check_return_code($return_var, $output);
		unset($output);
	}

	// Set success message
	if (empty($_SESSION["error_msg"])) {
		$_SESSION["ok_msg"] = _("Changes have been saved.");
		header("Location: /edit/web/?domain=" . $v_domain);
		exit();
	}
}

$v_ftp_users_raw = explode(":", $v_ftp_user);
$v_ftp_users_paths_raw = explode(":", $data[$v_domain]["FTP_PATH"]);
$v_ftp_users = [];
foreach ($v_ftp_users_raw as $v_ftp_user_index => $v_ftp_user_val) {
	if (empty($v_ftp_user_val)) {
		continue;
	}
	$v_ftp_users[] = [
		"is_new" => 0,
		"v_ftp_user" => preg_replace("/^" . preg_quote($user_plain, "/") . "_/", "", $v_ftp_user_val),
		"v_ftp_password" => $v_ftp_password,
		"v_ftp_path" => isset($v_ftp_users_paths_raw[$v_ftp_user_index])
			? $v_ftp_users_paths_raw[$v_ftp_user_index]
			: "",
		"v_ftp_email" => $v_ftp_email,
		"v_ftp_pre_path" => $v_ftp_user_prepath,
	];
}

if (empty($v_ftp_users)) {
	$v_ftp_user = null;
	$v_ftp_users[] = [
		"is_new" => 1,
		"v_ftp_user" => "",
		"v_ftp_password" => "",
		"v_ftp_path" => isset($v_ftp_users_paths_raw[$v_ftp_user_index])
			? $v_ftp_users_paths_raw[$v_ftp_user_index]
			: "",
		"v_ftp_email" => "",
		"v_ftp_pre_path" => $v_ftp_user_prepath,
	];
}

// set default pre path for newly created users
$v_ftp_pre_path_new_user = $v_ftp_user_prepath;
if (isset($v_ftp_users_updated)) {
	$v_ftp_users = $v_ftp_users_updated;
	if (empty($v_ftp_users_updated)) {
		$v_ftp_user = null;
		$v_ftp_users[] = [
			"is_new" => 1,
			"v_ftp_user" => "",
			"v_ftp_password" => "",
			"v_ftp_path" => isset($v_ftp_users_paths_raw[$v_ftp_user_index])
				? $v_ftp_users_paths_raw[$v_ftp_user_index]
				: "",
			"v_ftp_email" => "",
			"v_ftp_pre_path" => $v_ftp_user_prepath,
		];
	}
}

// Render page
render_page($user, $TAB, "edit_web");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
