<?php
// CrowdSec fleet-mesh pairing, accepting side (#485): completes a coupling that a peer initiated with
// the one-time code an admin minted HERE (h-generate-sys-crowdsec-pairing).
//
// THE INVARIANT: a pairing needs an admin on BOTH boxes. On the joining box, running
// h-add-sys-crowdsec-peer needs root or an admin panel session. On this box, the only thing that
// authorises the request is the one-time code - which only root or an admin panel session can mint.
// So this route is not a way in: while no code is live it is a plain 404, and while one is live it
// accepts exactly one pairing, for at most a handful of wrong guesses, out of 100 bits of entropy.
//
// This file is only the availability gate; authority is asserted by the CLI as root, which alone can
// read the code hash and write the peer record. The source address comes from the connection
// (REMOTE_ADDR), never from the payload - a self-reported address could name anyone.
//
// Deliberately minimal, like fm-auth.php: no config or helper includes, no session. The one shell
// call gets its secret-bearing payload through a 0600 handoff file, because argv is world-readable
// via /proc and would hand any local user a peer token.

$rundir = "/run/hestia/mesh";

if (($_SERVER["REQUEST_METHOD"] ?? "") !== "POST") {
	http_response_code(405);
	exit();
}

// No open window = the route does not exist. Cheap, secret-free, and the reason an idle box exposes
// nothing here at all.
$marker = $rundir . "/pairing";
if (!is_readable($marker) || (int) trim((string) file_get_contents($marker)) < time()) {
	http_response_code(404);
	exit();
}

$ip = $_SERVER["REMOTE_ADDR"] ?? "";
if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
	// The firewall rules that pairing installs are IPv4-only (h-add-firewall-rule).
	http_response_code(400);
	exit();
}

$body = file_get_contents("php://input", false, null, 0, 8192);
$in = json_decode((string) $body, true);
if (
	!is_array($in) ||
	!preg_match('/^[A-Za-z0-9-]{16,64}$/', (string) ($in["code"] ?? "")) ||
	!preg_match('/^[a-f0-9]{32,128}$/', (string) ($in["token"] ?? "")) ||
	!preg_match('/^[0-9]{1,5}$/', (string) ($in["port"] ?? "")) ||
	!preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]{0,253}$/', (string) ($in["host"] ?? ""))
) {
	http_response_code(400);
	exit();
}

$handoff = $rundir . "/in/" . bin2hex(random_bytes(16));
$json = json_encode([
	"code" => $in["code"],
	"token" => $in["token"],
	"port" => $in["port"],
	"host" => $in["host"],
]);
if (file_put_contents($handoff, $json, LOCK_EX) === false) {
	http_response_code(503);
	exit();
}
chmod($handoff, 0600);

// The CLI consumes the handoff file, validates the code as root and prints the reply the peer needs.
exec(
	"/usr/bin/sudo /usr/local/hestia/bin/h-add-sys-crowdsec-peer-request " .
		escapeshellarg($ip) .
		" " .
		escapeshellarg($handoff) .
		" 2>/dev/null",
	$output,
	$return_var,
);
@unlink($handoff);

if ($return_var !== 0) {
	http_response_code(403);
	exit();
}

// Reply verbatim only if it really is the expected object - never echo raw command output.
$reply = json_decode(implode("", $output), true);
if (!is_array($reply) || empty($reply["token"])) {
	http_response_code(500);
	exit();
}
header("Content-Type: application/json");
header("Cache-Control: no-store");
echo json_encode([
	"token" => $reply["token"],
	"port" => $reply["port"] ?? "",
	"host" => $reply["host"] ?? "",
]);
