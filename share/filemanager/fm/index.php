<?php
// Phase-1 skeleton PROBE for the FM integration (#419) — NOT the real app. It is
// replaced by the vendored TinyFileManager in Phase 2. It exists so the integration
// skeleton has something to serve, and it proves the request path end to end:
// panel session -> Caddy forward_auth -> private listener (secret-gated) -> the
// customer's own FPM pool, running as that customer with FM_ROOT = their home.
header("Content-Type: text/plain; charset=utf-8");

$uid = function_exists("posix_geteuid") ? posix_geteuid() : getmyuid();
$name = function_exists("posix_getpwuid") ? (posix_getpwuid($uid)["name"] ?? $uid) : $uid;
$root = getenv("FM_ROOT");

echo "HestiaRE file-manager skeleton probe (#419)\n";
echo "running-as:  {$name} (uid={$uid})\n";
echo "FM_ROOT:     " . ($root === false ? "(unset)" : $root) . "\n";
echo "SCRIPT_NAME: " . ($_SERVER["SCRIPT_NAME"] ?? "") . "\n";
echo "PHP_SELF:    " . ($_SERVER["PHP_SELF"] ?? "") . "\n";

if ($root !== false && is_dir($root)) {
	$items = @scandir($root);
	echo "home-listing: " .
		($items === false
			? "(denied)"
			: implode(", ", array_slice(array_diff($items, [".", ".."]), 0, 20))) .
		"\n";
} else {
	echo "home-listing: (FM_ROOT is not a directory for this pool)\n";
}
