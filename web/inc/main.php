<?php

session_start();

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\SMTP;
use PHPMailer\PHPMailer\Exception;

use function Hestiacp\quoteshellarg\quoteshellarg;

require_once __DIR__ . '/lib/quoteshellarg.php';
require_once '/usr/share/php/libphp-phpmailer/autoload.php';

define("HESTIA_DIR_BIN", "/usr/local/hestia/bin/");
define("HESTIA_CMD", "/usr/bin/sudo /usr/local/hestia/bin/");
define("DEFAULT_PHP_VERSION", "php-" . exec('php -r "echo substr(phpversion(),0,3);"'));

// Load Hestia Config directly
load_hestia_config();
require_once dirname(__FILE__) . "/prevent_csrf.php";
require_once dirname(__FILE__) . "/helpers.php";
$root_directory = dirname(__FILE__) . "/../../";

function destroy_sessions()
{
	unset($_SESSION);
	session_unset();
	session_destroy();
	session_start();
	// session_start() picks the id back up from the cookie, so without this every forced logout
	// hands the caller the same id it arrived with. #438 rotates at the impersonation transitions;
	// this is the plainer fixation case and it was the one still open.
	session_regenerate_id(true);
}

// Row counter for the list templates. It looks unused from here and is not: render_page() does
// extract($GLOBALS), and 26 templates count with it. Removing it printed "Undefined variable $i"
// on every list page - grep in this file cannot see that, only a run can.
$i = 0;

// Saving user IPs to the session for preventing session hijacking
$user_combined_ip = get_real_user_ip();

if (!isset($_SESSION["user_combined_ip"])) {
	$_SESSION["user_combined_ip"] = $user_combined_ip;
}

// Checking user to use session from the same IP he has been logged in
if (
	$_SESSION["user_combined_ip"] != $user_combined_ip &&
	isset($_SESSION["user"]) &&
	$_SESSION["DISABLE_IP_CHECK"] != "yes"
) {
	$v_user = quoteshellarg($_SESSION["user"]);
	$v_session_id = quoteshellarg($_SESSION["token"]);
	exec(HESTIA_CMD . "h-log-user-logout " . $v_user . " " . $v_session_id, $output, $return_var);
	destroy_sessions();
	header("Location: /login/");
	exit();
}

// Check system settings
if (!isset($_SESSION["VERSION"]) && !defined("NO_AUTH_REQUIRED")) {
	destroy_sessions();
	header("Location: /login/");
	exit();
}

// Check user session
if (!isset($_SESSION["user"]) && !defined("NO_AUTH_REQUIRED")) {
	destroy_sessions();
	header("Location: /login/");
	exit();
}

// Generate CSRF Token and set user shell variable
if (isset($_SESSION["user"])) {
	if (!isset($_SESSION["token"])) {
		$token = bin2hex(random_bytes(16));
		$_SESSION["token"] = $token;
	}
	$username = $_SESSION["user"];
	if (!empty($_SESSION["look"])) {
		$username = $_SESSION["look"];
	}

	$data = cli_json("h-list-user " . quoteshellarg($username) . " json");
	// The effective user can vanish mid-session - e.g. an admin deletes the
	// impersonated customer from another session (#438 blocks delete/user from
	// within an impersonation session, so it happens elsewhere). Log out cleanly
	// instead of limping on with undefined role/shell values.
	if (empty($data[$username])) {
		destroy_sessions();
		header("Location: /login/");
		exit();
	}
	// Suspension is decided HERE and not in top_panel(), which is where it used to live: render_page()
	// includes header.php before it calls top_panel(), output_buffering is off, so by then the headers
	// are gone and the Location was never sent - measured, a suspended customer got 13883 bytes of
	// rendered page. An admin impersonating a suspended customer is not logged out (they arrived
	// through "look" and need the account visible), which is what POLICY_USER_VIEW_SUSPENDED covers
	// for everyone else.
	if (
		($data[$username]["SUSPENDED"] ?? "") === "yes" &&
		($_SESSION["POLICY_USER_VIEW_SUSPENDED"] ?? "") !== "yes" &&
		empty($_SESSION["look"])
	) {
		destroy_sessions();
		$_SESSION["error_msg"] = _("You are logged out, please log in again.");
		header("Location: /login/");
		exit();
	}
	$_SESSION["login_shell"] = $data[$username]["SHELL"];
	$_SESSION["role"] = $data[$username]["ROLE"];
	// Effective vs real role (#438). Admin-only gates read userContext, so during
	// impersonation it must be the IMPERSONATED user's role ($_SESSION["role"], which
	// $username already resolved to the look account) - otherwise a script running in
	// the impersonation session (same panel origin) reaches admin routes. adminContext
	// holds the real logged-in role for the impersonation controls and off-chain
	// routes. userContext is also written at the look set/unset points (login/logout);
	// this is the belt that keeps it correct on any request that runs main.php.
	if (!empty($_SESSION["look"])) {
		$_SESSION["userContext"] = $_SESSION["role"];
	} elseif (!empty($_SESSION["adminContext"])) {
		$_SESSION["userContext"] = $_SESSION["adminContext"];
	}
	unset($data, $username);
}

if ($_SESSION["RELEASE_BRANCH"] == "release" && $_SESSION["DEBUG_MODE"] == "false") {
	define("JS_LATEST_UPDATE", "v=" . $_SESSION["VERSION"]);
} else {
	define("JS_LATEST_UPDATE", "r=" . time());
}

if (!defined("NO_AUTH_REQUIRED")) {
	if (empty($_SESSION["LAST_ACTIVITY"]) || empty($_SESSION["INACTIVE_SESSION_TIMEOUT"])) {
		destroy_sessions();
		header("Location: /login/");
		// The sibling branch below exits; without it here the page rendered on against the session
		// that was just destroyed.
		exit();
	} elseif ($_SESSION["INACTIVE_SESSION_TIMEOUT"] * 60 + $_SESSION["LAST_ACTIVITY"] < time()) {
		$v_user = quoteshellarg($_SESSION["user"]);
		$v_session_id = quoteshellarg($_SESSION["token"]);
		exec(
			HESTIA_CMD . "h-log-user-logout " . $v_user . " " . $v_session_id,
			$output,
			$return_var,
		);
		destroy_sessions();
		header("Location: /login/");
		exit();
	} else {
		$_SESSION["LAST_ACTIVITY"] = time();
	}
}

function ipUsed()
{
	$http_host = trim(get_http_host_name(), "[]");
	if (filter_var($http_host, FILTER_VALIDATE_IP)) {
		return true;
	} else {
		return false;
	}
}

if (isset($_SESSION["user"])) {
	$user = quoteshellarg($_SESSION["user"]);
	$user_plain = htmlentities($_SESSION["user"]);
}

if (isset($_SESSION["look"]) && $_SESSION["look"] != "" && $_SESSION["adminContext"] === "admin") {
	$user = quoteshellarg($_SESSION["look"]);
	$user_plain = htmlentities($_SESSION["look"]);
}
if (empty($user_plain)) {
	$user_plain = "";
}
if (!isset($_SESSION["look"])) {
	$_SESSION["look"] = "";
}

// The REAL identity, not the effective one: this stays false while an admin impersonates the root
// user, and true while the root user impersonates someone else. Decided in the one file whose job
// that is, so a page needing it for a gate does not read $_SESSION["user"] itself (#438).
// Both sides non-empty, deliberately: the `?? ""` form compared an empty ROOT_USER against an empty
// user and answered yes - permissive at the one line whose job is to decide who is the root account.
$is_real_root_user = !empty($_SESSION["ROOT_USER"]) && ($_SESSION["user"] ?? "") === $_SESSION["ROOT_USER"];

require_once dirname(__FILE__) . "/i18n.php";

function check_error($return_var)
{
	if ($return_var > 0) {
		header("Location: /error/");
		exit();
	}
}

// Run a CLI command that prints JSON and always hand back an array.
//
// A failed call leaves $output empty, and json_decode("") is null - which behaves like an
// array until something insists on a real one: in_array(x, null) is a TypeError, and on the
// login page that means a white screen instead of a form (#575). Callers get an array either
// way and pick their own fallback.
//
// The `: array` is the point, not decoration: it turns "always an array" from an observation
// about today's body into a checked promise, and callers are entitled to drop their own is_array()
// on the strength of it. It also states the limit - a command whose JSON is a SCALAR loses its
// value here, silently, so those callers take cli_value() below.
function cli_json($cmd): array
{
	$output = [];
	exec(HESTIA_CMD . $cmd, $output, $return_var);
	if ($return_var !== 0) {
		return [];
	}
	$data = json_decode(implode("", $output), true);
	return is_array($data) ? $data : [];
}

// Same call for a command that prints ONE value rather than a list, e.g. h-get-user-value.
// Answers null when the call failed or printed nothing, which is the state callers already test
// for; [] would be the wrong answer, because it compares against null and against a number the
// other way round than the value it stands in for.
//
// null therefore means BOTH "the call failed" and "the value is not set", and this helper only
// fits where those two lead to the same decision - in reset/index.php both mean "do not honour an
// expiry". A caller for whom an unset value is a legitimate state must not collapse them here, or
// it repeats one level down exactly what cli_json() was collapsing.
function cli_value($cmd)
{
	$output = [];
	exec(HESTIA_CMD . $cmd, $output, $return_var);
	if ($return_var !== 0) {
		return null;
	}
	$raw = trim(implode("", $output));
	if ($raw === "") {
		return null;
	}
	$data = json_decode($raw, true);
	if (is_array($data)) {
		return null;
	}
	// h-get-user-value prints a bare shell value, not JSON: "nologin", "unlimited", a date. Those
	// decode to null, and answering "no value" for a value that was printed would rebuild the
	// collapse this helper exists to avoid, one level down. A number still comes back typed.
	return $data === null ? $raw : $data;
}

/**
 * Record a failed command: sets error_msg, nothing else. It does NOT stop the request - the
 * caller keeps running, and so does every branch after it. Guard the ones that must not act on
 * a failed save with empty($_SESSION["error_msg"]), or use check_return_code_redirect where the
 * request should end. The name reads like "check and act"; it only notes.
 */
function check_return_code($return_var, $output)
{
	if ($return_var != 0) {
		$error = implode("<br>", $output);
		if (empty($error)) {
			$error = sprintf(_("Error code: %s"), $return_var);
		}

		// Add backtrace if debug mode is activated to find out the cause
		if ($_SESSION["DEBUG_MODE"] == "true") {
			$error .= " | DEBUG BACKTRACE: " . var_export(debug_backtrace(), true);
		}

		$_SESSION["error_msg"] = $error;
	}
}
function check_return_code_redirect($return_var, $output, $location)
{
	if ($return_var != 0) {
		$error = implode("<br>", $output);
		if (empty($error)) {
			$error = sprintf(_("Error code: %s"), $return_var);
		}
		$_SESSION["error_msg"] = $error;
		header("Location:" . $location);
		// Without this the caller carries on parsing a record the command never produced, which is
		// where the null derefs of this issue come from. A redirect means stop, at all 14 call sites.
		exit();
	}
}

function render_page($user, $TAB, $page)
{
	$__template_dir = dirname(__DIR__) . "/templates/";

	// Extract global variables
	// I think those variables should be passed via arguments
	extract($GLOBALS, EXTR_SKIP);

	// Header
	include $__template_dir . "header.php";

	// Panel
	$panel = top_panel(empty($_SESSION["look"]) ? $_SESSION["user"] : $_SESSION["look"], $TAB);

	// Policies controller
	@include_once dirname(__DIR__) . "/inc/policies.php";

	// Body
	include $__template_dir . "pages/" . $page . ".php";

	// Footer
	include $__template_dir . "footer.php";
}

// Match $_SESSION['token'] against $_GET['token'] or $_POST['token']
// Usage: verify_csrf($_POST) or verify_csrf($_GET); Use verify_csrf($_POST,true) to return on failure instead of redirect
function verify_csrf($method, $return = false)
{
	if (
		// A request without a token is the normal hostile case, not an exception - reading the key
		// raw made every one of them log a warning before being refused.
		($method["token"] ?? "") !== ($_SESSION["token"] ?? "") ||
		empty($method["token"]) ||
		empty($_SESSION["token"])
	) {
		if ($return === true) {
			return false;
		} else {
			header("Location: /login/");
			die();
		}
	} else {
		return true;
	}
}

function show_alert_message($data)
{
	$msgIcon = "";
	$msgText = "";
	$msgClass = "";
	if (!empty($data["error_msg"])) {
		$msgIcon = "fa-circle-exclamation";
		$msgText = htmlentities($data["error_msg"]);
		$msgClass = "inline-alert-danger";
	} elseif (!empty($data["ok_msg"])) {
		$msgIcon = "fa-circle-check";
		$msgText = $data["ok_msg"];
		$msgClass = "inline-alert-success";
	}

	if (!empty($msgText)) {
		printf(
			'<div class="inline-alert %s u-mb20" role="alert"><i class="fas %s"></i><p>%s</p></div>',
			$msgClass,
			$msgIcon,
			$msgText,
		);
	}
}

function top_panel($user, $TAB)
{
	$command = HESTIA_CMD . "h-list-user " . $user . " 'json'";
	exec($command, $output, $return_var);
	$panel = json_decode(implode("", $output), true);
	unset($output);
	// A row that is not there decides everything below it the wrong way round: the suspension check
	// compares against null and passes, and the role refresh writes null into userContext. Exit 0
	// with no output produces exactly that, so an empty row logs out like a non-zero exit does.
	if ($return_var > 0 || empty($panel[$user])) {
		destroy_sessions();
		$_SESSION["error_msg"] = _("You are logged out, please log in again.");
		header("Location: /login/");
		exit();
	}

	// Suspension is checked in the session block at the top of this file, before a single byte of
	// header.php has gone out. It used to be here, where the redirect could no longer be sent and
	// the function simply carried on against the session it had just destroyed.

	// Reset user permissions if changed while logged in
	if ($panel[$user]["ROLE"] !== $_SESSION["userContext"] && !isset($_SESSION["look"])) {
		unset($_SESSION["userContext"]);
		$_SESSION["userContext"] = $panel[$user]["ROLE"];
	}

	// Load user's selected theme and do not change it when impersonting user
	if (isset($panel[$user]["THEME"]) && !isset($_SESSION["look"])) {
		$_SESSION["userTheme"] = $panel[$user]["THEME"];
	}

	// Unset userTheme override variable if POLICY_USER_CHANGE_THEME is set to no
	if ($_SESSION["POLICY_USER_CHANGE_THEME"] === "no") {
		unset($_SESSION["userTheme"]);
	}

	// Set preferred sort order
	if (!isset($_SESSION["look"])) {
		$_SESSION["userSortOrder"] = $panel[$user]["PREF_UI_SORT"];
	}

	// Set home location URLs
	if ($_SESSION["userContext"] === "admin" && empty($_SESSION["look"])) {
		// Display users list for administrators unless they are impersonating a user account
		$home_url = "/list/user/";
	} else {
		// Set home location URL based on available package features from account
		if ($panel[$user]["WEB_DOMAINS"] != "0") {
			$home_url = "/list/web/";
		} elseif ($panel[$user]["MAIL_DOMAINS"] != "0") {
			$home_url = "/list/mail/";
		} elseif ($panel[$user]["DATABASES"] != "0") {
			$home_url = "/list/db/";
		} elseif ($panel[$user]["CRON_JOBS"] != "0") {
			$home_url = "/list/cron/";
		} elseif ($panel[$user]["BACKUPS"] != "0") {
			$home_url = "/list/backups/";
		}
	}

	// File manager menu visibility follows the EFFECTIVE user's per-user flag (#218
	// Phase 4): a customer sees it when they have it, and an admin impersonating a
	// customer sees that customer's. Kept in its own session key so it never mixes
	// with the legacy system-wide FILE_MANAGER (FileGator) key.
	$_SESSION["USER_FILE_MANAGER"] = (($panel[$user]["FILE_MANAGER"] ?? "") === "yes") ? "yes" : "";

	include dirname(__FILE__) . "/../templates/includes/panel.php";
	return $panel;
}

function translate_date($date)
{
	$date = new DateTime($date);
	return $date->format("d") . " " . _($date->format("M")) . " " . $date->format("Y");
}

function convert_datetime($date, $format = "Y-m-d H:i:s")
{
	$date = new DateTime($date);
	return $date->format($format);
}

function humanize_time($usage)
{
	if ($usage > 60) {
		$usage = $usage / 60;
		if ($usage > 24) {
			$usage = $usage / 24;
			$usage = number_format($usage);
			return sprintf(ngettext("%d day", "%d days", $usage), $usage);
		} else {
			$usage = round($usage);
			return sprintf(ngettext("%d hour", "%d hours", $usage), $usage);
		}
	} else {
		$usage = round($usage);
		return sprintf(ngettext("%d minute", "%d minutes", $usage), $usage);
	}
}

function humanize_usage_size($usage, $round = 2)
{
	if ($usage == "unlimited") {
		return "∞";
	}
	if ($usage < 1) {
		$usage = "0";
	}
	$display_usage = $usage;
	if ($usage > 1024) {
		$usage = $usage / 1024;
		if ($usage > 1024) {
			$usage = $usage / 1024;
			if ($usage > 1024) {
				$usage = $usage / 1024;
				$display_usage = number_format($usage, $round);
			} else {
				if ($usage > 999) {
					$usage = $usage / 1024;
				}
				$display_usage = number_format($usage, $round);
			}
		} else {
			if ($usage > 999) {
				$usage = $usage / 1024;
			}
			$display_usage = number_format($usage, $round);
		}
	} else {
		if ($usage > 999) {
			$usage = $usage / 1024;
		}
		$display_usage = number_format($usage, $round);
	}
	return $display_usage;
}

function humanize_usage_measure($usage)
{
	if ($usage == "unlimited") {
		return;
	}

	$measure = "kb";
	if ($usage > 1024) {
		$usage = $usage / 1024;
		if ($usage > 1024) {
			$usage = $usage / 1024;
			$measure = $usage < 1024 ? "tb" : "pb";
			if ($usage > 999) {
				$usage = $usage / 1024;
				$measure = "pb";
			}
		} else {
			$measure = $usage < 1024 ? "gb" : "tb";
			if ($usage > 999) {
				$usage = $usage / 1024;
				$measure = "tb";
			}
		}
	} else {
		$measure = $usage < 1024 ? "mb" : "gb";
		if ($usage > 999) {
			$measure = "gb";
		}
	}
	return $measure;
}

function get_percentage($used, $total)
{
	if ($total === "unlimited") {
		//return 0 if unlimited
		return 0;
	}
	if (!isset($total)) {
		$total = 0;
	}
	if (!isset($used)) {
		$used = 0;
	}
	if ($total == 0) {
		$percent = 0;
	} else {
		$percent = $used / $total;
		$percent = $percent * 100;
		$percent = number_format($percent, 0, "", "");
		if ($percent < 0) {
			$percent = 0;
		} elseif ($percent > 100) {
			$percent = 100;
		}
	}
	return $percent;
}

function send_email($to, $subject, $mailtext, $from, $from_name, $to_name = "")
{
	$mail = new PHPMailer();

	if (isset($_SESSION["USE_SERVER_SMTP"]) && $_SESSION["USE_SERVER_SMTP"] == "true") {
		if (!empty($_SESSION["SERVER_SMTP_ADDR"]) && $_SESSION["SERVER_SMTP_ADDR"] != "") {
			if (filter_var($_SESSION["SERVER_SMTP_ADDR"], FILTER_VALIDATE_EMAIL)) {
				$from = $_SESSION["SERVER_SMTP_ADDR"];
			}
		}

		$mail->isSMTP();
		$mail->Mailer = "smtp";
		$mail->SMTPDebug = 0;
		$mail->SMTPAuth = true;
		$mail->SMTPSecure = $_SESSION["SERVER_SMTP_SECURITY"];
		$mail->Port = $_SESSION["SERVER_SMTP_PORT"];
		$mail->Host = $_SESSION["SERVER_SMTP_HOST"];
		$mail->Username = $_SESSION["SERVER_SMTP_USER"];
		$mail->Password = $_SESSION["SERVER_SMTP_PASSWD"];
	}

	$mail->isHTML(true);
	$mail->clearReplyTos();
	if (empty($to_name)) {
		$mail->addAddress($to);
	} else {
		$mail->addAddress($to, $to_name);
	}
	$mail->setFrom($from, $from_name);

	$mail->CharSet = "utf-8";
	$mail->Subject = $subject;
	$content = $mailtext;
	$content = nl2br($content);
	$mail->msgHTML($content);
	$mail->send();
}

function list_timezones()
{
	foreach (
		["AKST", "AKDT", "PST", "PDT", "MST", "MDT", "CST", "CDT", "EST", "EDT", "AST", "ADT"] as $timezone
	) {
		$tz = new DateTimeZone($timezone);
		$timezone_offsets[$timezone] = $tz->getOffset(new DateTime());
	}

	foreach (DateTimeZone::listIdentifiers() as $timezone) {
		$tz = new DateTimeZone($timezone);
		$timezone_offsets[$timezone] = $tz->getOffset(new DateTime());
	}

	foreach ($timezone_offsets as $timezone => $offset) {
		$offset_prefix = $offset < 0 ? "-" : "+";
		$offset_formatted = gmdate("H:i", abs($offset));
		$pretty_offset = "UTC{$offset_prefix}{$offset_formatted}";
		$c = new DateTime(gmdate("Y-M-d H:i:s"), new DateTimeZone("UTC"));
		$c->setTimezone(new DateTimeZone($timezone));
		$current_time = $c->format("H:i:s");
		$timezone_list[$timezone] = "$timezone [ $current_time ] {$pretty_offset}";
		#$timezone_list[$timezone] = "$timezone ${pretty_offset}";
	}
	return $timezone_list;
}

/**
 * A function that tells is it MySQL installed on the system, or it is MariaDB.
 *
 * Explanation:
 * $_SESSION['DB_SYSTEM'] has 'mysql' value even if MariaDB is installed, so you can't figure out is it really MySQL or it's MariaDB.
 * So, this function will make it clear.
 *
 * If MySQL is installed, function will return 'mysql' as a string.
 * If MariaDB is installed, function will return 'mariadb' as a string.
 *
 * Hint: if you want to check if PostgreSQL is installed - check value of $_SESSION['DB_SYSTEM']
 *
 * @return string
 */
function is_it_mysql_or_mariadb()
{
	$data = cli_json("h-list-sys-services json");
	$mysqltype = "mysql";
	if (isset($data["mariadb"])) {
		$mysqltype = "mariadb";
	}
	return $mysqltype;
}

function load_hestia_config()
{
	// Check system configuration
	$data = cli_json("h-list-sys-config json");
	$sys_arr = $data["config"] ?? [];
	// Without the config there is no policy set, and an absent key is the PERMISSIVE reading at
	// every gate that consumes one: POLICY_SYSTEM_PASSWORD_RESET is honoured as "not no",
	// POLICY_SYSTEM_PROTECTED_ADMIN as "not yes", same for the log policies. Seeding a closed
	// default per policy would be a hand-kept table that goes stale the day a policy is added, so
	// the panel serves nothing rather than decide without its own configuration. Runs before the
	// translations are loaded, hence the untranslated text.
	if (!$sys_arr) {
		http_response_code(503);
		exit("Hestia configuration unavailable.\n");
	}
	foreach ($sys_arr as $key => $value) {
		$_SESSION[$key] = $value;
	}
}

/**
 * Returns the list of all web domains from all users grouped by Backend Template used and owner
 *
 * @return array
 */
function backendtpl_with_webdomains()
{
	$users = cli_json("h-list-users json");

	$backend_list = [];
	foreach ($users as $user => $user_details) {
		$domains = cli_json("h-list-web-domains " . quoteshellarg($user) . " json");
		foreach ($domains as $domain => $domain_details) {
			// The version is its own field now (#591); group by it under the PHP-X_Y key the
			// server page looks up. 'none' domains run no PHP and are not counted.
			$ver = $domain_details["PHP_VERSION"] ?? "";
			if ($ver === "" || $ver === "none") {
				continue;
			}
			$key = "PHP-" . str_replace(".", "_", $ver);
			$backend_list[$key][$user][] = $domain;
		}
	}
	return $backend_list;
}
/**
 * Check if password is valid
 *
 * @return int; 1 / 0
 */
function validate_password($password)
{
	return preg_match('/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(.){8,}$/', $password);
}

function unset_alerts()
{
	if (!empty($_SESSION["unset_alerts"])) {
		if (!empty($_SESSION["error_msg"])) {
			unset($_SESSION["error_msg"]);
		}
		if (!empty($_SESSION["ok_msg"])) {
			unset($_SESSION["ok_msg"]);
		}
		unset($_SESSION["unset_alerts"]);
	}
}
register_shutdown_function("unset_alerts");
