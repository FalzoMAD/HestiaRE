<?php

error_reporting(null);
$TAB = "BACKUP";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Data
$data = cli_json("h-list-user-backup-exclusions $user json");
// Render page
render_page($user, $TAB, "list_backup_exclusions");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
