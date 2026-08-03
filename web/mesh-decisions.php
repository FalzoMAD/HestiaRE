<?php
// CrowdSec fleet-mesh transport, serve side: hands this box's published ban list to a paired peer,
// which presents the bearer token it got during pairing. No session, no cookie, no fallback path.
//
// Deliberately minimal, like fm-auth.php / rspamd-auth.php: no includes, no shell calls, no writes.
// The panel pool runs as `hestia` and can read neither /etc/hestia nor /var/lib/crowdsec, so
// h-update-crowdsec-mesh stages the payload and the per-peer token HASHES under /run/hestia/mesh.
// Hashes only: this file can compare, never mint - reading the staged file buys an attacker nothing.
//
// What crosses the wire is a list of banned IPv4 values, never the LAPI (loopback-only) and never a
// panel object; pairing's IP-scoped firewall rule narrows access further.
//
// No rate limit on purpose: the token is 256 bits, so a lockout would not improve the threat model -
// and on an unauthenticated route it would itself be a way to cut a peer off. Rejects are logged.

$tokens = "/run/hestia/mesh/tokens";
$payload = "/run/hestia/mesh/published.json";

if (($_SERVER["REQUEST_METHOD"] ?? "") !== "GET") {
	http_response_code(405);
	exit();
}

// No staged state = nothing to serve (mesh off, no peers, or not yet refreshed after a boot).
if (!is_readable($tokens) || !is_readable($payload)) {
	http_response_code(404);
	exit();
}

$auth = $_SERVER["HTTP_AUTHORIZATION"] ?? ($_SERVER["REDIRECT_HTTP_AUTHORIZATION"] ?? "");
if (!preg_match('/^Bearer\s+([a-f0-9]{32,128})$/i', trim($auth), $m)) {
	http_response_code(401);
	header('WWW-Authenticate: Bearer realm="hestia-mesh"');
	exit();
}
$presented = hash("sha256", strtolower($m[1]));

$ok = false;
foreach (file($tokens, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
	// "<sha256> <peer>"; hash_equals for constant time.
	$hash = strtok($line, " ");
	if ($hash !== false && hash_equals($hash, $presented)) {
		$ok = true;
		break;
	}
}
if (!$ok) {
	// A well-formed but unknown token is the only interesting failure: someone guessing at a live
	// credential. Caddy's access log holds every 403 anyway; this makes the suspicious subset greppable
	// without the scanner noise that stops at the 401 above.
	error_log("hestia-mesh: rejected pull with unknown token from " . ($_SERVER["REMOTE_ADDR"] ?? "?"));
	http_response_code(403);
	exit();
}

header("Content-Type: application/json");
header("Cache-Control: no-store");
readfile($payload);
