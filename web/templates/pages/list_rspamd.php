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
     session (forward_auth); no separate rspamd login thanks to secure_ip. -->
<iframe
	src="/rspamd/"
	title="rspamd"
	class="u-width-full"
	style="height: calc(100vh - 96px); border: 0;"
	referrerpolicy="same-origin"
></iframe>
