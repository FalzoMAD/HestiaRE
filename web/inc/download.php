<?php
// Shared streaming helper for the panel download handlers. We stream from PHP, not nginx
// X-Accel-Redirect (#441): Caddy's file_server would run as `caddy`, which can't read the
// customer-owned files, and granting it that read is the capability we avoid (as with the file
// manager). The panel pool runs as `hestia`, owner of every /backup file. Must hold at GB scale.

// Stream $file as an attachment. $allow_range honours a client Range: header - safe ONLY for a
// static file (a stored backup); db/site archives are regenerated per request, so a resumed range
// would land in a differently-generated file. Those callers leave it false.
function serve_download($file, $ctype, $allow_range = false)
{
	// Stream to the socket, not into memory_limit, and let a client disconnect be seen at the next
	// write - a live output buffer swallows the writes and hangs the worker.
	while (ob_get_level()) {
		ob_end_clean();
	}
	// Free the worker the moment the client goes away (explicit, not relying on the ini default).
	ignore_user_abort(false);

	$size = filesize($file);
	header("Content-Type: " . $ctype);
	header('Content-Disposition: attachment; filename="' . basename($file) . '"');

	$start = 0;
	$end = $size - 1;

	if ($allow_range) {
		header("Accept-Ranges: bytes");
		// Single range only - a hard cap of one. A comma multi-range list is the amplification
		// vector (bytes=0-0,0-0,… → a huge multipart response from a tiny request); we never build
		// multipart, so any list or malformed/descending spec falls back to the whole file. A resume
		// needs one range. The comma guard is explicit so a later regex tweak can't quietly reopen it.
		if (
			isset($_SERVER["HTTP_RANGE"]) &&
			strpos($_SERVER["HTTP_RANGE"], ",") === false &&
			preg_match('/^bytes=(\d*)-(\d*)$/', $_SERVER["HTTP_RANGE"], $m)
		) {
			if ($m[1] === "" && $m[2] === "") {
				// bytes=- : serve whole
			} elseif ($m[1] === "") {
				// suffix: final N bytes
				$start = max(0, $size - (int) $m[2]);
			} else {
				$start = (int) $m[1];
				if ($m[2] !== "") {
					$end = (int) $m[2];
				}
			}
			$end = min($end, $size - 1);
			if ($start > $end || $start >= $size) {
				header($_SERVER["SERVER_PROTOCOL"] . " 416 Range Not Satisfiable");
				header("Content-Range: bytes */" . $size);
				exit();
			}
			header($_SERVER["SERVER_PROTOCOL"] . " 206 Partial Content");
			header("Content-Range: bytes " . $start . "-" . $end . "/" . $size);
		}
	}

	header("Content-Length: " . ($end - $start + 1));

	$fp = fopen($file, "rb");
	if ($fp === false) {
		exit();
	}
	if ($start > 0) {
		fseek($fp, $start);
	}
	$remaining = $end - $start + 1;
	while ($remaining > 0 && !feof($fp) && !connection_aborted()) {
		$read = $remaining > 8192 ? 8192 : $remaining;
		echo fread($fp, $read);
		$remaining -= $read;
		flush();
	}
	fclose($fp);
	exit();
}
