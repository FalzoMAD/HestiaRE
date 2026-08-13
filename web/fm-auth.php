<?php

// Forward-auth endpoint for the File Manager reverse proxy (Panel-Caddy, #419).
// Caddy calls this for every /fm/* request; a 204 + `X-Hestia-User` lets the
// request through to that customer's own FPM pool, anything else blocks it.
// This is the ONLY authorization stop: the FM pool listens on a private loopback
// listener the browser can never reach directly, so the app itself runs with its
// login disabled ($use_auth = false) - the process is the tenant.
//
// Deliberately minimal, like rspamd-auth.php: no config/helper includes, no shell
// calls. It runs in the panel FPM pool (as `hestia`) and sees the same PHPSESSID
// the browser sends with the proxied request. The IP-based hijacking check stays in
// inc/main.php on the real panel pages; here REMOTE_ADDR would be Caddy's own
// address, so it is intentionally not checked.
session_start();

if (empty($_SESSION["user"])) {
	http_response_code(401);
	exit();
}

// Effective user: admin impersonation via "look", otherwise the session user.
// This is an OFF-CHAIN route (it does not run inc/main.php), so it reads the
// DURABLE adminContext + look, never the derived userContext (#438 principle).
$user =
	!empty($_SESSION["look"]) && ($_SESSION["adminContext"] ?? "") === "admin"
		? $_SESSION["look"]
		: $_SESSION["user"];

// Defence in depth: the name feeds the socket path below. It comes from a trusted
// session, but a strict charset + no "." / ".." makes traversal structurally
// impossible regardless (Hestia usernames are [A-Za-z0-9._-]).
if (!preg_match('/^[A-Za-z0-9._-]+$/', $user) || $user === "." || $user === "..") {
	http_response_code(403);
	exit();
}

// "Enabled?" gate = the customer's FM pool exists. h-add-user-filemanager creates
// the pool (listen socket /run/hestia/fm/<user>.sock), h-delete-user-filemanager
// removes it. We test the socket, NOT the FILE_MANAGER flag in user.conf: this runs
// as `hestia`, which cannot read /etc/hestia (700 root:root) without a sudo h-list-user
// per request - whereas /run/hestia is world-traversable (0755), so the socket is a
// cheap stat. Its existence IS the structural truth of "enabled" (no pool → the proxy
// to fm-<user>.local has no vhost anyway → fail-closed).
if (file_exists("/run/hestia/fm/" . $user . ".sock")) {
	// Caddy copies this onto the proxied request and derives the pool Host from it;
	// the vhost side overwrites any client-supplied value, so it is authoritative.
	header("X-Hestia-User: " . $user);
	// Pass the customer's panel theme through so the FM matches light/dark (#218 S2).
	// The panel stores it in the session (userTheme, THEME fallback - see css.php);
	// the FM maps light*/dark* families onto Bootstrap's data-bs-theme.
	$theme = !empty($_SESSION["userTheme"]) ? $_SESSION["userTheme"] : ($_SESSION["THEME"] ?? "");
	if (preg_match('/^[A-Za-z0-9._-]+$/', $theme)) {
		header("X-Hestia-Theme: " . $theme);
	}
	http_response_code(204);
} else {
	http_response_code(403);
}
