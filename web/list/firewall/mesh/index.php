<?php

$TAB = "FIREWALL";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

// A non-zero exit means the mesh is off (no mesh.conf) - the page then says how to turn it on
// instead of showing an empty table.
exec(HESTIA_CMD . "h-list-sys-crowdsec-peers json", $output, $return_var);
$mesh_enabled = $return_var === 0;
$data = $mesh_enabled ? json_decode(implode("", $output), true) : [];
if (!is_array($data)) {
	$data = [];
}
ksort($data);
unset($output);

// A freshly minted code is shown exactly once, then dropped from the session.
$pairing_code = $_SESSION["mesh_pairing_code"] ?? "";
$pairing_note = $_SESSION["mesh_pairing_note"] ?? "";
unset($_SESSION["mesh_pairing_code"], $_SESSION["mesh_pairing_note"]);

// Render page
render_page($user, $TAB, "list_firewall_mesh");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
