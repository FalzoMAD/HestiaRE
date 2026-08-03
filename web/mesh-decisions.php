<?php
// CrowdSec fleet-mesh transport, serve side (#485): hands this box's published ban list to a paired
// peer. The peer presents the bearer token it received during pairing; nothing else is accepted, and
// there is no session, no cookie and no fallback path.
//
// Deliberately minimal, like fm-auth.php / rspamd-auth.php: no config or helper includes, no shell
// calls, no writes. It runs in the panel FPM pool (as `hestia`), which cannot read /etc/hestia or
// /var/lib/crowdsec - so h-update-crowdsec-mesh stages what this needs under /run/hestia/mesh: the
// payload, and the per-peer token HASHES. Only hashes: this file can compare, never mint or leak a
// working token, and a read of the staged file buys an attacker nothing.
//
// What crosses the wire is a list of banned IPv4 values, never the CrowdSec LAPI (loopback-only) and
// never any panel object. Access is additionally narrowed by the IP-scoped firewall rule that pairing
// installs for each peer on the panel port.
//
// No rate limit on purpose: the token is 256 bits (openssl rand -hex 32), so guessing is not a threat
// model a lockout would improve - and a lockout on an unauthenticated route would itself be a way to
// cut a peer off. Rejected guesses are logged instead (see below).

$tokens = "/run/hestia/mesh/tokens";
$payload = "/run/hestia/mesh/published.json";

if (($_SERVER["REQUEST_METHOD"] ?? "") !== "GET") {
	http_response_code(405);
	exit();
}

// No staged state = this box serves nothing (mesh off, no peers, or not yet refreshed after a boot).
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
	// "<sha256> <peer>"; hash_equals keeps the comparison constant-time.
	$hash = strtok($line, " ");
	if ($hash !== false && hash_equals($hash, $presented)) {
		$ok = true;
		break;
	}
}
if (!$ok) {
	// A well-formed but unknown token is the only interesting failure: someone guessing at a live
	// credential. Tokens are 256-bit, so a lockout would be theatre - visibility is the point. Caddy's
	// access log holds every 403 (and rotates itself); this line makes the suspicious subset greppable
	// without logging the scanner noise that never gets past the 401 above.
	error_log("hestia-mesh: rejected pull with unknown token from " . ($_SERVER["REMOTE_ADDR"] ?? "?"));
	http_response_code(403);
	exit();
}

header("Content-Type: application/json");
header("Cache-Control: no-store");
readfile($payload);
