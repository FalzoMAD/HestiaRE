<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

// Init
define("NO_AUTH_REQUIRED", true);
define("NO_AUTH_REQUIRED2", true);
header("Content-Type: text/plain; charset=utf-8");

include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Checking IP of incoming connection, checking is it NAT address
$ok = 0;
$ip = $_SERVER["REMOTE_ADDR"];

// cli_json() rather than exec+decode: a failed h-list-sys-ips decodes to null, and iterating that is
// a TypeError - a 500 in an endpoint that is reachable without a session (#578).
$arr = cli_json("h-list-sys-ips json");
foreach ($arr as $arr_key => $arr_val) {
	// search for NAT IPs and allow them
	if ($ip == $arr_key || $ip == ($arr_val["NAT"] ?? "")) {
		$ok = 1;
		break;
	}
}
// There used to be an "$ip == $_SERVER[SERVER_ADDR]" branch here. Caddy's php_fastcgi does not pass
// SERVER_ADDR (nginx did, via fastcgi_params), so on this panel the key is absent on every request:
// the branch never fired and only produced a warning inside an access gate. Dropping it does not
// narrow anything - the loop above already walks every address h-list-sys-ips knows, NAT included,
// which is where the box's own address comes from.
if ($ip == "127.0.0.1") {
	$ok = 1;
}
if ($ok == 0) {
	exit();
}
if (isset($_SERVER["HTTP_X_REAL_IP"]) || isset($_SERVER["HTTP_X_FORWARDED_FOR"])) {
	exit();
}

// Check arguments

if (empty($_POST["email"])) {
	echo "error email address not provided";
	exit();
}
if (empty($_POST["password"])) {
	echo "error old password provided";
	exit();
}
if (empty($_POST["new"])) {
	echo "error new password not provided";
	exit();
}

[$v_account, $v_domain] = explode("@", $_POST["email"]);
$v_domain = quoteshellarg($v_domain);
$v_account = quoteshellarg($v_account);
$v_password = $_POST["password"];

// Get domain owner
exec(HESTIA_CMD . "h-search-domain-owner " . $v_domain . " 'mail'", $output, $return_var);
if ($return_var != 0 || empty($output[0])) {
	echo "error domain owner not found";
	exit();
}
$v_user = $output[0];
unset($output);

// Get current password hash (called "md5" for legacy reasons, it's not guaranteed to be md5)
exec(
	HESTIA_CMD .
		"h-get-mail-account-value " .
		quoteshellarg($v_user) .
		" " .
		$v_domain .
		" " .
		$v_account .
		" 'md5'",
	$output,
	$return_var,
);
if ($return_var != 0 || empty($output[0])) {
	echo "error unable to get current account password hash";
	exit();
}
$v_hash = $output[0];
unset($output);

// v_hash use doveadm password hash format, which is basically {HASH_NAME}normal_crypt_format,
// so we just need to remove the {HASH_NAME} before we can ask password_verify if its correct or not.
$hash_for_password_verify = explode("}", $v_hash, 2);
$hash_for_password_verify = end($hash_for_password_verify);
if (!password_verify($v_password, $hash_for_password_verify)) {
	die("error old password does not match");
}

// Change password
$fp = tmpfile();
$new_password_file = stream_get_meta_data($fp)["uri"];
fwrite($fp, $_POST["new"] . "\n");
exec(
	HESTIA_CMD .
		"h-change-mail-account-password " .
		quoteshellarg($v_user) .
		" " .
		$v_domain .
		" " .
		$v_account .
		" " .
		quoteshellarg($new_password_file),
	$output,
	$return_var,
);
fclose($fp);
if ($return_var == 0) {
	echo "==ok==";
	exit();
}
echo "error h-change-mail-account-password returned non-zero: " . $return_var;
exit();
