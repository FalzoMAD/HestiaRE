<?php /* Panel JS is served build-free: own code as native ES modules straight
from js/src (module scripts defer by default and execute in document order with
the deferred vendor scripts below — our alpine:init listeners register before
the Alpine core runs). Vendored libs come from upstream/* branches, see
VENDORED.json. */ ?>
<script type="module" src="/js/src/index.js?<?= JS_LATEST_UPDATE ?>"></script>
<script defer src="/js/vendor/alpinejs-collapse.min.js?<?= JS_LATEST_UPDATE ?>"></script>
<script defer src="/js/vendor/alpinejs.min.js?<?= JS_LATEST_UPDATE ?>"></script>
<script>
	document.documentElement.classList.replace('no-js', 'js');
	document.addEventListener('alpine:init', () => {
		Alpine.store('globals', {
			USER_PREFIX: '<?= $user_plain ?>_',
			UNLIMITED: '<?= _("Unlimited") ?>',
			NOTIFICATIONS_EMPTY: '<?= _("No notifications") ?>',
			NOTIFICATIONS_DELETE_ALL: '<?= _("Delete all notifications") ?>',
			CONFIRM_LEAVE_PAGE: '<?= _("Are you sure you want to leave the page?") ?>',
			ERROR_MESSAGE: '<?= !empty($_SESSION["error_msg"]) ? htmlentities($_SESSION["error_msg"],ENT_QUOTES) : "" ?>',
			BLACKLIST: '<?= _("BLACKLIST") ?>',
			IPVERSE: '<?= _("IPVERSE") ?>'
		});
	})
</script>
<?php $_SESSION["unset_alerts"] = true; ?>

<?php
$customScriptDirectory = new DirectoryIterator($_SERVER["HESTIA"] . "/web/js/custom_scripts");
foreach ($customScriptDirectory as $customScript) {
	$extension = $customScript->getExtension();
	if ($extension === "js") {
		$customScriptPath = "/js/custom_scripts/" . rawurlencode($customScript->getBasename());
		echo '<script defer src="' . $customScriptPath . '"></script>';
	} elseif ($extension === "php") {
		require_once $customScript->getPathname();
	}
} ?>
