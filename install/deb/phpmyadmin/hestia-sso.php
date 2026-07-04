<?php

/* HestiaRE phpMyAdmin single sign-on endpoint (signon auth, see
 * /etc/phpmyadmin/conf.d/hestia-sso.inc.php). Deployed by h-add-sys-pma-sso.
 *
 * Runs in the phpMyAdmin FPM pool (user caddy, unprivileged). The panel
 * creates a temporary database user and a one-time handoff file under
 * /run/hestia-sso/<token> (h-add-database-sso-token, via the panel's sudo),
 * then redirects the browser here. This script consumes the handoff file and
 * opens the signon session — no API, no sudo, no secrets in this pool. */

define("HANDOFF_DIR", "/run/hestia-sso");
/* Seconds a handoff token stays valid (must match TOKEN_TTL in h-add-database-sso-token) */
define("TOKEN_TTL", 60);

/* Need to have cookie visible from parent directory */
session_set_cookie_params(0, "/", "", true, true);
$session_name = "SignonSession";
session_name($session_name);
@session_start();

function session_invalid() {
	global $session_name;
	session_destroy();
	setcookie($session_name, "", -1, "/");
	/* Relative Location: resolves against the current URL directory, so it
	 * works regardless of the alias prefix Caddy strips (dirname(PHP_SELF)
	 * would yield "/" here and "//index.php" is a protocol-relative URL). */
	header("Location: index.php");
	die();
}

if (isset($_GET["logout"])) {
	/* The temporary database user expires on its own (TTL scheduled by
	 * h-add-database-temp-user) — nothing privileged to do here. */
	session_invalid();
}

$token = $_GET["token"] ?? "";
if (!preg_match('/^[a-f0-9]{64}$/', $token)) {
	session_invalid();
}

$handoff_file = HANDOFF_DIR . "/" . $token;
$raw = @file_get_contents($handoff_file);
/* One-time use: consume the file before validating its content */
@unlink($handoff_file);
if ($raw === false) {
	session_invalid();
}

$data = json_decode($raw, true);
if (
	!is_array($data) ||
	empty($data["user"]) ||
	empty($data["password"]) ||
	empty($data["ip"]) ||
	empty($data["time"]) ||
	$data["time"] + TOKEN_TTL < time() ||
	/* Panel and phpMyAdmin are served by the same Caddy, so REMOTE_ADDR is
	 * directly comparable between the issuing and the consuming request. */
	$data["ip"] !== $_SERVER["REMOTE_ADDR"]
) {
	session_invalid();
}

$_SESSION["PMA_single_signon_user"] = $data["user"];
$_SESSION["PMA_single_signon_password"] = $data["password"];
$_SESSION["PMA_single_signon_host"] = "localhost";
@session_write_close();
setcookie($session_name, session_id(), [
	"expires" => 0,
	"path" => "/",
	"secure" => true,
	"httponly" => true,
]);
header("Location: index.php");
die();
