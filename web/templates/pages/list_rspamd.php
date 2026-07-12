<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/server/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml( _("Back")) ?>
			</a>
		</div>
		<div class="toolbar-buttons">
			<a class="button button-secondary" href="/rspamd/" target="_blank" rel="noopener">
				<i class="fas fa-up-right-from-square icon-green"></i><?= tohtml( _("Open in new tab")) ?>
			</a>
		</div>
	</div>
</div>
<!-- End toolbar -->

<!-- rspamd controller UI, served same-origin at /rspamd/ behind the panel
     session (forward_auth); no separate rspamd login thanks to secure_ip.
     Constrained to the standard content box; tall so the graphs/tables fit. -->
<?php
// The rspamd UI has no native dark mode below 3.14 (none of the target
// platforms ship that), so on dark panel themes we inject an override
// stylesheet into the same-origin iframe (#319). Shipped dark themes follow
// the "dark*" naming convention (dark, dark-tonal).
$panel_theme = !empty($_SESSION["userTheme"]) ? $_SESSION["userTheme"] : ($_SESSION["THEME"] ?? "light");
$rspamd_dark = str_starts_with($panel_theme, "dark");
?>
<div class="container">
	<iframe
		id="rspamd-frame"
		src="/rspamd/"
		title="rspamd"
		class="u-width-full"
		style="height: calc(100vh - 140px); min-height: 900px; border: 0;<?= $rspamd_dark ? " background-color: #282828;" : "" ?>"
		referrerpolicy="same-origin"
	></iframe>
</div>
<?php if ($rspamd_dark) { ?>
<script type="module">
	// Same-origin injection; the rspamd UI is a SPA, so one <link> in its
	// <head> survives all in-app navigation. The iframe background above
	// covers the moment before the stylesheet applies.
	const frame = document.getElementById("rspamd-frame");
	const injectDarkCss = () => {
		const doc = frame.contentDocument;
		if (!doc || doc.getElementById("hestia-rspamd-dark")) return;
		const link = doc.createElement("link");
		link.id = "hestia-rspamd-dark";
		link.rel = "stylesheet";
		link.href = "/css/src/rspamd-dark.css?<?= JS_LATEST_UPDATE ?>";
		doc.head.appendChild(link);
	};
	frame.addEventListener("load", injectDarkCss);
	// The iframe may already be loaded before this module runs
	if (frame.contentDocument?.readyState === "complete") injectDarkCss();
</script>
<?php } ?>
