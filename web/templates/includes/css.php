<link rel="alternate icon" href="/images/favicon.png" type="image/png">
<link rel="icon" href="/images/logo.svg" type="image/svg+xml">
<link rel="stylesheet" href="/css/src/themes/default.css?<?= JS_LATEST_UPDATE ?>">

<?php
$selected_theme = !empty($_SESSION["userTheme"]) ? $_SESSION["userTheme"] : $_SESSION["THEME"];
// Load non-default theme as overlay on top of default
if ($selected_theme !== "default") {
	// Load HestiaRE-shipped themes (overwritten with updates) - ($HESTIA/web/css/src/themes/*.css)
	$non_default_theme_path = $_SERVER["HESTIA"] . "/web/css/src/themes/" . $selected_theme . ".css";
	if (file_exists($non_default_theme_path)) {
		echo '<link rel="stylesheet" href="/css/src/themes/' . $selected_theme . ".css?" . JS_LATEST_UPDATE . '">';
	}
	// Load custom theme files ($HESTIA/web/css/src/themes/custom/*.css)
	else {
		$custom_theme_path = $_SERVER["HESTIA"] . "/web/css/src/themes/custom/" . $selected_theme . ".css";
		if (file_exists($custom_theme_path)) {
			echo '<link rel="stylesheet" href="/css/src/themes/custom/' . $selected_theme . ".css?" . JS_LATEST_UPDATE . '">';
		}
	}
}

?>
