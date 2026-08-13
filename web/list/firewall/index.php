<?php

$TAB = "FIREWALL";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

// Data
$data = cli_json("h-list-firewall json");
// Evaluation order, always - the renderer emits rules by descending RULE id into one chain and
// nft takes the first match, so the top row is the one that actually wins. A firewall ruleset is
// ordered data, not a sortable table: honouring userSortOrder here made the list agree with
// precedence under one setting and invert it under the other, which silently flipped what the
// move arrows appeared to do.
krsort($data, SORT_NUMERIC);

// Render page
render_page($user, $TAB, "list_firewall");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
