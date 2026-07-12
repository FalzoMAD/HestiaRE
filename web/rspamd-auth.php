<?php
// Forward-auth endpoint for the rspamd web UI reverse proxy (Panel-Caddy).
// Caddy calls this for every /rspamd/* request; a 2xx response lets the
// request reach the controller, anything else blocks it. This is what keeps
// the controller — which trusts localhost without a password (secure_ip) —
// from being reachable by anyone who hits port 8083: only an authenticated
// admin panel session passes.
//
// Deliberately minimal: no config/helper includes, no shell calls. It runs in
// the panel FPM pool, so it shares the session save path and sees the same
// PHPSESSID cookie the browser sends with the framed request. The IP-based
// session-hijacking check stays in inc/main.php on the real panel pages; here
// REMOTE_ADDR would be Caddy's own address, so it is intentionally not checked.
session_start();

if (!empty($_SESSION["user"]) && ($_SESSION["userContext"] ?? "") === "admin") {
	http_response_code(204);
} else {
	http_response_code(401);
}
