<?php

$TAB = "FIREWALL";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check user
if ($_SESSION["userContext"] != "admin") {
	header("Location: /list/user");
	exit();
}

// Data: fail2ban bans (banlist.conf) plus, when CrowdSec is present, its local L3 decisions - so an admin
// can see and lift a CrowdSec ban here too, including in the crowdsec-only model where there is no
// fail2ban banlist at all. Keyed with a source prefix so a shared IP does not collide between the two.
$data = [];

foreach (cli_json("h-list-firewall-ban json") as $ip => $v) {
	$v["IP"] = $ip;
	$v["SOURCE"] = "fail2ban";
	$data["f2b:" . $ip] = $v;
}

if (!empty($_SESSION["CROWDSEC"])) {
	foreach (cli_json("h-list-firewall-crowdsec-ban json") as $ip => $v) {
		$v["IP"] = $ip;
		$v["SOURCE"] = "crowdsec";
		$data["cs:" . $ip] = $v;
	}
}

$data = array_reverse($data, true);

// Render page
render_page($user, $TAB, "list_firewall_banlist");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
