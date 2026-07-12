<?php
$TAB = "SERVER";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Admin only — the rspamd controller UI is a server-wide tool
if ($_SESSION["userContext"] !== "admin") {
	header("Location: /list/user");
	exit();
}

// Only meaningful when rspamd is the active antispam system
if (($_SESSION["ANTISPAM_SYSTEM"] ?? "") !== "rspamd") {
	header("Location: /list/server/");
	exit();
}

render_page($user, $TAB, "list_rspamd");
