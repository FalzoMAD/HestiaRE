<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

require_once __DIR__ . '/cloudflare-ip.php';

# Return codes
const E_ARGS = 1;
const E_INVALID = 2;
const E_NOTEXIST = 3;
const E_EXISTS = 4;
const E_SUSPENDED = 5;
const E_UNSUSPENDED = 6;
const E_INUSE = 7;
const E_LIMIT = 8;
const E_PASSWORD = 9;
const E_FORBIDEN = 10;
const E_FORBIDDEN = 10;
const E_DISABLED = 11;
const E_PARSING = 12;
const E_DISK = 13;
const E_LA = 14;
const E_CONNECT = 15;
const E_FTP = 16;
const E_DB = 17;
const E_RRD = 18;
const E_UPDATE = 19;
const E_RESTART = 20;
const E_API_DISABLED = 21;

if (!function_exists("tohtml")) {
	function tohtml(string|int|float|bool|null $str): string
	{
		if ($str === null || $str === "") {
			return "";
		}
		if (is_int($str) || is_float($str)) {
			return (string) $str;
		}
		if (is_bool($str)) {
			return $str ? "1" : "0";
		}

		return htmlentities(
			$str,
			ENT_QUOTES | ENT_SUBSTITUTE | ENT_DISALLOWED | ENT_HTML5,
			"UTF-8",
			true,
		);
	}
}

/**
 * Looks for a code equivalent to "exit_code" to use in http_code.
 *
 * @param int $exit_code
 * @param int $default
 * @return int
 */
function exit_code_to_http_code(int $exit_code, int $default = 400): int
{
	switch ($exit_code) {
		case 0:
			return 200;
		case E_ARGS:
			// return 500;
			return 400;
		case E_INVALID:
			return 422;
			// case E_NOTEXIST:
			// 	return 404;
			// case E_EXISTS:
			// 	return 302;
		case E_PASSWORD:
			return 401;
		case E_SUSPENDED:
		case E_UNSUSPENDED:
		case E_FORBIDEN:
		case E_FORBIDDEN:
		case E_API_DISABLED:
			return 401;
			// return 403;
		case E_DISABLED:
			return 400;
			// return 503;
	}

	return $default;
}

function get_real_user_ip()
{
	$ip = "";

	if (
		!empty($_SERVER["REMOTE_ADDR"]) &&
		filter_var($_SERVER["REMOTE_ADDR"], FILTER_VALIDATE_IP)
	) {
		$ip = $_SERVER["REMOTE_ADDR"];
	}

	if (
		!empty($_SERVER["HTTP_CF_CONNECTING_IP"]) &&
		filter_var($_SERVER["HTTP_CF_CONNECTING_IP"], FILTER_VALIDATE_IP) &&
		!empty($ip) &&
		hestia_is_cloudflare_ip($ip)
	) {
		$ip = $_SERVER["HTTP_CF_CONNECTING_IP"];
	}

	// Handling IPv4-mapped IPv6 address
	if (strpos($ip, ":") === 0 && strpos($ip, ".") > 0) {
		$ip = substr($ip, strrpos($ip, ":") + 1); // Strip IPv4 Compatibility notation
	}
	return $ip;
}

/**
 * Create a history log using 'h-log-action' script.
 *
 * @param string $message The message for log.
 * @param string $category A category for log. Ex: Auth, Firewall, API...
 * @param string $level Info|Warning|Error.
 * @param string $user A username for save in the user history ou 'system' to save in Hestia history.
 * @return int The script result code.
 */
function hst_add_history_log($message, $category = "System", $level = "Info", $user = "system")
{
	//$message = ucfirst($message);
	//$message = str_replace("'", "`", $message);
	$category = ucfirst(strtolower($category));
	$level = ucfirst(strtolower($level));

	$command_args =
		quoteshellarg($user) .
		" " .
		quoteshellarg($level) .
		" " .
		quoteshellarg($category) .
		" " .
		quoteshellarg($message);
	exec(HESTIA_CMD . "h-log-action " . $command_args, $output, $return_var);
	unset($output);

	return $return_var;
}

function get_hostname()
{
	$badValues = [
		false,
		null,
		0,
		"",
		"localhost",
		"127.0.0.1",
		"::1",
		"0000:0000:0000:0000:0000:0000:0000:0001",
	];
	$ret = gethostname();
	if (in_array($ret, $badValues, true)) {
		throw new Exception("gethostname() failed");
	}
	$ret2 = gethostbyname($ret);
	if (in_array($ret2, $badValues, true)) {
		return $ret;
	}
	$ret3 = gethostbyaddr($ret2);
	if (in_array($ret3, $badValues, true)) {
		return $ret2;
	}
	return $ret3;
}

function display_title($tab)
{
	$array1 = ["{{page}}", "{{hostname}}", "{{ip}}", "{{appname}}"];
	$array2 = [$tab, get_hostname(), $_SERVER["REMOTE_ADDR"], $_SESSION["APP_NAME"]];
	return str_replace($array1, $array2, $_SESSION["TITLE"]);
}

/**
 * A control the form did not render sends no key at all. Reading it as "" turns "not offered" into
 * "cleared", which is a silent rewrite (THEME, SHELL, DOCKER_LIMIT) or a fatal at the CLI boundary
 * (quoteshellarg(null)).
 *
 * $offered is the server-side gate the view rendered on, and it is what decides - not the presence
 * of the key, which comes from the client. Deciding on presence alone would let a POST carry a
 * control the user was never offered, which is a policy bypass wherever a select sits behind one
 * (POLICY_USER_CHANGE_THEME is the plain case).
 *
 * The gate is evaluated at write time. That is not always the state the submitted form was rendered
 * under - a second session can flip a model switch in between - but it is server-side and cannot be
 * forged, which a hidden witness field in the form could be.
 */
function post_or_keep(string $key, bool $offered, $stored)
{
	if (!$offered) {
		return $stored;
	}
	return array_key_exists($key, $_POST) ? $_POST[$key] : $stored;
}

/**
 * Checkboxes need the gate for a second reason: unchecked is an absent key too, so "keep" alone
 * would make the box impossible to clear.
 *
 * $on and $off carry no default on purpose. The record space (yes/no) and the form space (on/"")
 * are not the same, and a default would make the convenient call the wrong one - writing "" where
 * the record wants "no" is the silent rewrite this whole path exists to prevent.
 */
function post_checkbox(string $key, bool $offered, $stored, string $on, string $off)
{
	if (!$offered) {
		return $stored;
	}
	return empty($_POST[$key]) ? $off : $on;
}

/**
 * Hand a secret to an h-* command through a 0600 tempfile instead of argv: only the path reaches
 * the process arguments, sudo's log and /proc/<pid>/cmdline. Pass the returned path where the
 * plaintext would go and unlink it after exec. The "/tmp" prefix is required - is_password_valid
 * anchors on ^/tmp/.
 *
 * Returns false and sets error_msg rather than throwing - this runs on the save route, where an
 * uncaught exception is a white page. The shutdown handler covers a request that dies before the
 * unlink, which would otherwise leave the cleartext in /tmp.
 */
function secret_tmpfile(string $value)
{
	$path = @tempnam("/tmp", "hst-sec-");
	if ($path === false) {
		$_SESSION["error_msg"] = _("An internal error occurred");
		return false;
	}
	chmod($path, 0600);
	if (file_put_contents($path, $value . "\n") === false) {
		@unlink($path);
		$_SESSION["error_msg"] = _("An internal error occurred");
		return false;
	}
	register_shutdown_function(static function () use ($path) {
		if (is_file($path)) {
			@unlink($path);
		}
	});
	return $path;
}
