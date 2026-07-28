<?php
// Shared streaming helper for the panel download handlers (download/{backup,database,
// site}). We stream straight from PHP instead of nginx X-Accel-Redirect (#441): the
// panel is Caddy-fronted and its file_server would run as `caddy`, which cannot read
// the customer-owned files — and granting caddy that read is the capability we avoid
// (same reason as the file manager). The panel pool runs as `hestia`, owner of every
// /backup file, so it can stream them.
//
// serve_download() must survive multi-GB files (#443): the 60 KB #441 corpus hid the
// class readfile() bites in at scale.

// Stream $file to the client as an attachment of type $ctype.
//
// $allow_range: honour a client Range: header (206/416) so an aborted large download
// can resume. ONLY safe for a STATIC file (a stored backup). The db/site archives are
// regenerated per request by h-dump-*, so a resume request would re-run the dump and
// the byte offsets would not match the earlier archive → corrupt file. Those callers
// pass false and we advertise no Accept-Ranges for them.
function serve_download($file, $ctype, $allow_range = false)
{
	// Drain every output buffer so the bytes stream straight to the socket instead
	// of piling up in memory (a 20 GB readfile with a buffer active blows memory_limit)
	// AND so a client disconnect is seen at the next write — with a buffer swallowing
	// the writes it never is, and the FPM worker hangs (only 4 in the panel pool).
	while (ob_get_level()) {
		ob_end_clean();
	}
	// Default is already Off, but be explicit: abort the script when the client goes
	// away so the worker frees immediately rather than streaming into the void.
	ignore_user_abort(false);

	$size = filesize($file);
	header("Content-Type: " . $ctype);
	header('Content-Disposition: attachment; filename="' . basename($file) . '"');

	$start = 0;
	$end = $size - 1;

	if ($allow_range) {
		header("Accept-Ranges: bytes");
		// SINGLE range only (bytes=A-B, bytes=A-, bytes=-N) — a hard cap of one. A
		// comma-separated multi-range list is the classic amplification vector
		// (bytes=0-0,0-0,0-0,… turns a tiny request into a huge multipart response;
		// nginx/Apache cap the count for exactly this reason). We never build multipart:
		// any list (comma), or a malformed/overlapping/descending spec, falls back to the
		// whole file (200). A download resume only ever needs one range, so nothing real
		// is lost. The comma guard is explicit so a later regex tweak can't reopen it.
		if (
			isset($_SERVER["HTTP_RANGE"]) &&
			strpos($_SERVER["HTTP_RANGE"], ",") === false &&
			preg_match('/^bytes=(\d*)-(\d*)$/', $_SERVER["HTTP_RANGE"], $m)
		) {
			if ($m[1] === "" && $m[2] === "") {
				// bytes=- is malformed; ignore and serve whole.
			} elseif ($m[1] === "") {
				// bytes=-N → final N bytes.
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
