<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
$TAB = "LOG";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Edit as someone else?
if ($_SESSION["adminContext"] === "admin" && $_SESSION["look"] != "") {
	$user = quoteshellarg($_SESSION["look"]);
} elseif ($_SESSION["userContext"] === "admin" && !empty($_GET["user"])) {
	$user = quoteshellarg($_GET["user"]);
}

exec(HESTIA_CMD . "h-list-user-auth-log " . $user . " json", $output, $return_var);
check_return_code_redirect($return_var, $output, "/");

// Not cli_json(): the redirect above needs the raw $return_var and the command's own error text.
$data = array_reverse(json_decode(implode("", $output), true) ?: []);
unset($output);

// Render page
render_page($user, $TAB, "list_log_auth");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
