<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
$TAB = "USER";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user argument
if (empty($_GET["user"])) {
	header("Location: /list/user/");
	exit();
}

// Edit as someone else?
if ($_SESSION["userContext"] === "admin" && !empty($_GET["user"])) {
	$user = $_GET["user"];
	$v_username = $_GET["user"];
} else {
	$user = $_SESSION["user"];
	$v_username = $_SESSION["user"];
}

// Fail closed: if ROOT_USER is unknown the guard below can't identify what it protects, so
// refuse an admin editing anyone but themselves. Only trips on a broken session/config.
if (
	$_SESSION["userContext"] === "admin" &&
	empty($_SESSION["ROOT_USER"]) &&
	$v_username !== $_SESSION["user"]
) {
	header("Location: /list/user/");
	exit();
}

// Only the real ROOT_USER may edit the ROOT_USER account. #438: gate on effective
// userContext but anchor identity on the durable $_SESSION["user"] (impersonation is in "look").
if (
	$_SESSION["userContext"] === "admin" &&
	!empty($_SESSION["ROOT_USER"]) &&
	$user === $_SESSION["ROOT_USER"] &&
	$_SESSION["user"] !== $_SESSION["ROOT_USER"]
) {
	header("Location: /list/user/");
	exit();
}

// Check token
verify_csrf($_GET);

// List user
exec(HESTIA_CMD . "h-list-user " . quoteshellarg($v_username) . " json", $output, $return_var);
check_return_code_redirect($return_var, $output, "/list/user/");

$data = json_decode(implode("", $output), true);
unset($output);

// Parse user
$v_password = "";
$v_email = $data[$v_username]["CONTACT"];
$v_package = $data[$v_username]["PACKAGE"];
$v_language = $data[$v_username]["LANGUAGE"];
$v_user_theme = $data[$v_username]["THEME"];
$v_sort_order = $data[$v_username]["PREF_UI_SORT"];
$v_name = $data[$v_username]["NAME"];
$v_shell = $data[$v_username]["SHELL"];
$v_twofa = $data[$v_username]["TWOFA"];
$v_qrcode = $data[$v_username]["QRCODE"];
$v_phpcli = $data[$v_username]["PHPCLI"];
$v_role = $data[$v_username]["ROLE"];
$v_login_disabled = $data[$v_username]["LOGIN_DISABLED"];
$v_login_use_iplist = $data[$v_username]["LOGIN_USE_IPLIST"];
$v_login_allowed_ips = $data[$v_username]["LOGIN_ALLOW_IPS"];
$v_file_manager = $data[$v_username]["FILE_MANAGER"] ?? "";
$v_docker_ip = $data[$v_username]["DOCKER_IP"] ?? "";
// Same rule as h-add-user-docker: compose files and the docker CLI need a real shell, and the
// jail is not measured for it. Read before $v_shell picks up its quoted second meaning below.
$v_docker_eligible = !in_array($v_shell, ["nologin", "false", "rssh", "jailbash"], true);
$v_suspended = $data[$v_username]["SUSPENDED"];
if ($v_suspended == "yes") {
	$v_status = "suspended";
} else {
	$v_status = "active";
}
$v_time = $data[$v_username]["TIME"];
$v_date = $data[$v_username]["DATE"];

if (empty($v_phpcli)) {
	$v_phpcli = substr(DEFAULT_PHP_VERSION, 4);
}

// List packages
exec(HESTIA_CMD . "h-list-user-packages json", $output, $return_var);
$packages = json_decode(implode("", $output), true);
unset($output);

// List languages
exec(HESTIA_CMD . "h-list-sys-languages json", $output, $return_var);
$language = json_decode(implode("", $output), true);
foreach ($language as $lang) {
	$languages[$lang] = translate_json($lang);
}
asort($languages);
unset($output);

// List themes
exec(HESTIA_CMD . "h-list-sys-themes json", $output, $return_var);
$themes = json_decode(implode("", $output), true);
unset($output);

// List shells
exec(HESTIA_CMD . "h-list-sys-shells json", $output, $return_var);
$shells = json_decode(implode("", $output), true);
unset($output);

//List PHP Versions
// List supported php versions
exec(HESTIA_CMD . "h-list-sys-php json", $output, $return_var);
$php_versions = json_decode(implode("", $output), true);
unset($output);

// One gate per conditionally rendered control (#649): the view renders on it and the POST section
// reads on it, so a control a customer was never offered cannot be read as "cleared". The
// admin-only ones use the REAL identity where the field grants privilege, the effective one where
// it is ordinary scoping (#438).
$offer_admin_fields = $_SESSION["userContext"] === "admin";
$offer_role = $offer_admin_fields && $v_username != "admin" && $_SESSION["user"] != $v_username;
$offer_theme = ($_SESSION["POLICY_USER_CHANGE_THEME"] ?? "") !== "no";
$offer_file_manager = $offer_admin_fields && !empty($_SESSION["FILE_MANAGER_PORT"]);
$offer_docker =
	($_SESSION["adminContext"] ?? "") === "admin" &&
	!empty($_SESSION["DOCKER_SYSTEM"]) &&
	($v_docker_eligible || !empty($v_docker_ip));

// Check POST request
if (!empty($_POST["save"])) {
	// Check token
	verify_csrf($_POST);

	// #5547: same guard on the POST path - the page-render guard alone leaves a crafted POST open.
	if (
		$_SESSION["userContext"] === "admin" &&
		!empty($_SESSION["ROOT_USER"]) &&
		$v_username === $_SESSION["ROOT_USER"] &&
		$_SESSION["user"] !== $_SESSION["ROOT_USER"]
	) {
		header("Location: /list/user/");
		exit();
	}

	// Change password
	if (!empty($_POST["v_password"]) && empty($_SESSION["error_msg"])) {
		// Check password length
		$pw_len = strlen($_POST["v_password"]);
		if (!validate_password($_POST["v_password"])) {
			$_SESSION["error_msg"] = _("Password does not match the minimum requirements.");
		}
		if (empty($_SESSION["error_msg"])) {
			$v_password = tempnam("/tmp", "vst");
			$fp = fopen($v_password, "w");
			fwrite($fp, $_POST["v_password"] . "\n");
			fclose($fp);
			exec(
				HESTIA_CMD .
					"h-change-user-password " .
					quoteshellarg($v_username) .
					" " .
					$v_password,
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			unlink($v_password);
			$v_password = quoteshellarg($_POST["v_password"]);
		}
	}

	// Enable twofa
	if (!empty($_POST["v_twofa"]) && empty($v_twofa) && empty($_SESSION["error_msg"])) {
		exec(HESTIA_CMD . "h-add-user-2fa " . quoteshellarg($v_username), $output, $return_var);
		check_return_code($return_var, $output);
		unset($output);

		// List user
		exec(
			HESTIA_CMD . "h-list-user " . quoteshellarg($v_username) . " json",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		$data = json_decode(implode("", $output), true);
		unset($output);

		// Parse user twofa
		$v_twofa = $data[$v_username]["TWOFA"];
		$v_qrcode = $data[$v_username]["QRCODE"];
	}

	// Disable twofa
	if (empty($_POST["v_twofa"]) && !empty($v_twofa) && empty($_SESSION["error_msg"])) {
		exec(HESTIA_CMD . "h-delete-user-2fa " . quoteshellarg($v_username), $output, $return_var);
		check_return_code($return_var, $output);
		unset($output);
		$v_twofa = "";
		$v_qrcode = "";
	}

	// Change default sort order
	if ($v_sort_order != $_POST["v_sort_order"] && empty($_SESSION["error_msg"])) {
		$v_sort_order = quoteshellarg($_POST["v_sort_order"]);
		exec(
			HESTIA_CMD .
				"h-change-user-sort-order " .
				quoteshellarg($v_username) .
				" " .
				$v_sort_order,
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($_SESSION["userSortOrder"]);
		$_SESSION["userSortOrder"] = $v_sort_order;
		unset($output);
	}

	// Update Control Panel login disabled status (admin only)
	if ($offer_admin_fields && empty($_SESSION["error_msg"])) {
		// Compared in record space, not form space: "on" never equals "yes", so the old comparison
		// rewrote the value on nearly every save
		$v_login_disabled = $v_login_disabled === "yes" ? "yes" : "no";
		$post_login_disabled = post_checkbox("v_login_disabled", $offer_admin_fields, $v_login_disabled, "yes", "no");
		if ($post_login_disabled != $v_login_disabled) {
			exec(
				HESTIA_CMD .
					"h-change-user-config-value " .
					quoteshellarg($v_username) .
					" LOGIN_DISABLED " .
					quoteshellarg($post_login_disabled),
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			$data[$user]["LOGIN_DISABLED"] = $post_login_disabled;
			unset($output);
		}
	}

	// Update File Manager access (admin only, and only while the system module is
	// installed - FILE_MANAGER_PORT is set by h-add-sys-filemanager, cleared by
	// h-delete-sys-filemanager). The dedicated commands build/tear down the
	// per-customer FPM pool + private-listener vhost + socket AND set the flag, so
	// this is NOT a plain h-change-user-config-value.
	if ($offer_file_manager && empty($_SESSION["error_msg"])) {
		$v_file_manager = $v_file_manager === "yes" ? "yes" : "no";
		$v_fm_new = post_checkbox("v_file_manager", $offer_file_manager, $v_file_manager, "yes", "no");
		if ($v_fm_new !== $v_file_manager) {
			$fm_cmd = $v_fm_new === "yes" ? "h-add-user-filemanager " : "h-delete-user-filemanager ";
			exec(HESTIA_CMD . $fm_cmd . quoteshellarg($v_username), $output, $return_var);
			check_return_code($return_var, $output);
			if (empty($_SESSION["error_msg"])) {
				$v_file_manager = $v_fm_new;
			}
			unset($output);
		}
	}

	// Docker access (admin only, addon installed). The commands allocate the customer's /24 and
	// build the companion with its rootless daemon, so this is not a config value either. The
	// switch only acts where it was rendered: an ineligible shell hides it, and an absent
	// checkbox would otherwise read as "turn docker off".
	if ($offer_docker && empty($_SESSION["error_msg"])) {
		$v_docker_new = post_checkbox("v_docker", $offer_docker, empty($v_docker_ip) ? "no" : "yes", "yes", "no");
		// Turning it off deletes the customer's containers, images and volumes and cannot be undone
		// by re-checking the box, so the name has to be typed. Enforced here, not only in the
		// dialog: an unchecked box must never carry that away as a side effect of another save.
		if ($v_docker_new === "no" && !empty($v_docker_ip) && ($_POST["v_docker_confirm"] ?? "") !== $v_username) {
			$_SESSION["error_msg"] = sprintf(
				_("Disabling Docker deletes the containers, images and volumes of %s. Confirm by typing the user name."),
				$v_username,
			);
		} elseif ($v_docker_new !== (empty($v_docker_ip) ? "no" : "yes")) {
			$docker_cmd = $v_docker_new === "yes" ? "h-add-user-docker " : "h-delete-user-docker ";
			exec(HESTIA_CMD . $docker_cmd . quoteshellarg($v_username), $output, $return_var);
			check_return_code($return_var, $output);
			unset($output);
			if (empty($_SESSION["error_msg"])) {
				// the address is allocated by the command - ask for it rather than guess
				exec(HESTIA_CMD . "h-list-user " . quoteshellarg($v_username) . " json", $output, $return_var);
				$docker_row = json_decode(implode("", $output), true) ?: [];
				$v_docker_ip = reset($docker_row)["DOCKER_IP"] ?? "";
				unset($output);
			}
		}
	}

	// Update IP whitelist option
	if (empty($_SESSION["error_msg"])) {
		if (empty($_POST["v_login_use_iplist"])) {
			$_POST["v_login_use_iplist"] = "";
		}
		if ($_POST["v_login_use_iplist"] != $v_login_use_iplist) {
			if ($_POST["v_login_use_iplist"] == "on") {
				$_POST["v_login_use_iplist"] = "yes";
			} else {
				$_POST["v_login_use_iplist"] = "no";
			}
			exec(
				HESTIA_CMD .
					"h-change-user-config-value " .
					quoteshellarg($v_username) .
					" LOGIN_USE_IPLIST " .
					quoteshellarg($_POST["v_login_use_iplist"]),
				$output,
				$return_var,
			);
			if ($_POST["v_login_use_iplist"] === "no") {
				exec(
					HESTIA_CMD .
						"h-change-user-config-value " .
						quoteshellarg($v_username) .
						" LOGIN_ALLOW_IPS ''",
					$output,
					$return_var,
				);
				$v_login_allowed_ips = "";
			} else {
				exec(
					HESTIA_CMD .
						"h-change-user-config-value " .
						quoteshellarg($v_username) .
						" LOGIN_ALLOW_IPS " .
						quoteshellarg($_POST["v_login_allowed_ips"]),
					$output,
					$return_var,
				);
				unset($v_login_allowed_ips);
				$v_login_allowed_ips = $_POST["v_login_allowed_ips"];
			}
			check_return_code($return_var, $output);
			$data[$user]["LOGIN_USE_IPLIST"] = $_POST["v_login_use_iplist"];
			unset($output);
		}
	}

	if ($offer_admin_fields) {
		// Change package (admin only)
		$post_package = post_or_keep("v_package", $v_package);
		if ($v_package != $post_package && empty($_SESSION["error_msg"])) {
			$v_package = quoteshellarg($post_package);
			exec(
				HESTIA_CMD .
					"h-change-user-package " .
					quoteshellarg($v_username) .
					" " .
					$v_package,
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
		}

		// Change phpcli (admin only)
		$post_phpcli = post_or_keep("v_phpcli", $v_phpcli);
		if ($v_phpcli != $post_phpcli && empty($_SESSION["error_msg"])) {
			$v_phpcli = quoteshellarg($post_phpcli);
			exec(
				HESTIA_CMD .
					"h-change-user-php-cli " .
					quoteshellarg($v_username) .
					" " .
					$v_phpcli,
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
		}

		// The select is absent for the admin account and for an admin editing themselves
		$post_role = post_or_keep("v_role", $v_role);
		if (
			$offer_role &&
			$v_role != $post_role &&
			$v_username != $_SESSION["ROOT_USER"] &&
			empty($_SESSION["error_msg"])
		) {
			if (!empty($post_role)) {
				$v_role = quoteshellarg($post_role);
				exec(
					HESTIA_CMD . "h-change-user-role " . quoteshellarg($v_username) . " " . $v_role,
					$output,
					$return_var,
				);
				check_return_code($return_var, $output);
				unset($output);
				$v_role = $post_role;
			}
		}
		// Change shell (admin only)
		$post_shell = post_or_keep("v_shell", $v_shell);
		if (!empty($post_shell)) {
			if ($v_shell != $post_shell && empty($_SESSION["error_msg"])) {
				$v_shell = quoteshellarg($post_shell);

				exec(
					HESTIA_CMD .
						"h-change-user-shell " .
						quoteshellarg($v_username) .
						" " .
						$v_shell,
					$output,
					$return_var,
				);
				check_return_code($return_var, $output);
				unset($output);
			}
		}
	}
	// Change language
	if ($v_language != $_POST["v_language"] && empty($_SESSION["error_msg"])) {
		$v_language = quoteshellarg($_POST["v_language"]);
		exec(
			HESTIA_CMD . "h-change-user-language " . quoteshellarg($v_username) . " " . $v_language,
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		if (empty($_SESSION["error_msg"])) {
			if ($_GET["user"] == $_SESSION["user"]) {
				unset($_SESSION["language"]);
				$_SESSION["language"] = $_POST["v_language"];
				$refresh = $_SERVER["REQUEST_URI"];
				header("Location: $refresh");
			}
		}
		unset($output);
	}

	// Change contact email
	if ($v_email != $_POST["v_email"] && empty($_SESSION["error_msg"])) {
		if (!filter_var($_POST["v_email"], FILTER_VALIDATE_EMAIL)) {
			$_SESSION["error_msg"] = _("Please enter a valid email address.");
		} else {
			$v_email = quoteshellarg($_POST["v_email"]);
			exec(
				HESTIA_CMD . "h-change-user-contact " . quoteshellarg($v_username) . " " . $v_email,
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
		}
	}

	// Change full name
	if ($v_name != $_POST["v_name"]) {
		if (empty($_POST["v_name"])) {
			$_SESSION["error_msg"] = _("Please enter a valid contact name.");
		} else {
			$v_name = quoteshellarg($_POST["v_name"]);
			exec(
				HESTIA_CMD . "h-change-user-name " . quoteshellarg($v_username) . " " . $v_name,
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			$v_name = $_POST["v_name"];
		}
	}

	// Update theme
	if (empty($_SESSION["error_msg"])) {
		if (empty($_SESSION["userTheme"])) {
			$_SESSION["userTheme"] = "";
		}
		// Compare against the theme THIS user has, falling back to the box default - not against the
		// session of whoever is editing. An admin editing someone else carries their own theme there,
		// so every save looked like a change and wrote one.
		$current_theme = !empty($v_user_theme) ? $v_user_theme : ($_SESSION["THEME"] ?? "");
		$post_user_theme = post_or_keep("v_user_theme", $current_theme);
		if ($offer_theme && $post_user_theme != $current_theme) {
			exec(
				HESTIA_CMD .
					"h-change-user-theme " .
					quoteshellarg($v_username) .
					" " .
					quoteshellarg($post_user_theme),
				$output,
				$return_var,
			);
			check_return_code($return_var, $output);
			unset($output);
			$v_user_theme = $post_user_theme;
			if ($_SESSION["user"] === $v_username) {
				unset($_SESSION["userTheme"]);
				$_SESSION["userTheme"] = $v_user_theme;
			}
		}
	}

	// Set success message
	if (empty($_SESSION["error_msg"])) {
		$_SESSION["ok_msg"] = _("Changes have been saved.");
	}
}

// Render page
render_page($user, $TAB, "edit_user");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
