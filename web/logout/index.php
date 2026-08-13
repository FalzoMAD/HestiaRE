<?php

use function Hestiacp\quoteshellarg\quoteshellarg;

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";
// Check token
verify_csrf($_GET);

if (!empty($_SESSION["look"])) {
	$v_user = quoteshellarg($_SESSION["look"]);
	$v_impersonator = quoteshellarg($_SESSION["user"]);
	exec(
		HESTIA_CMD .
			"h-log-action system 'Warning' 'Security' 'User impersonation session ended (User: $v_user, Administrator: $v_impersonator)'",
		$output,
		$return_var,
	);
	unset($_SESSION["look"]);
	// Restore the real admin role and rotate the session id on return, so an id
	// captured during the impersonation window cannot regain admin afterwards (#438).
	if (!empty($_SESSION["adminContext"])) {
		$_SESSION["userContext"] = $_SESSION["adminContext"];
	}
	session_regenerate_id(true);
	# Remove current path for filemanager
	unset($_SESSION["_sf2_attributes"]);
	unset($_SESSION["_sf2_meta"]);
	header("Location: /");
} else {
	if ($_SESSION["token"] && $_SESSION["user"]) {
		unset($_SESSION["userTheme"]);
		$v_user = quoteshellarg($_SESSION["user"]);
		$v_session_id = quoteshellarg($_SESSION["token"]);
		exec(
			HESTIA_CMD . "h-log-user-logout " . $v_user . " " . $v_session_id,
			$output,
			$return_var,
		);
	}

	// destroy_sessions(), not the same three calls by hand: it also starts a fresh session and
	// rotates the id. Destroying without that left the browser holding the id it arrived with, and
	// the next request adopts it - so an id captured before the logout is the id of the session
	// after the next login. Measured: the cookie did not change across a logout.
	destroy_sessions();
	header("Location: /login/");
}
exit();
