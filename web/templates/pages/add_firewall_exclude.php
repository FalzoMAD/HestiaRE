<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/firewall/exclude/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml( _("Back")) ?>
			</a>
		</div>
		<div class="toolbar-buttons">
			<button type="submit" class="button" form="main-form">
				<i class="fas fa-floppy-disk icon-purple"></i><?= tohtml( _("Save")) ?>
			</button>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container">

	<form id="main-form" name="v_add_exclude" method="post">
		<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
		<input type="hidden" name="ok" value="Add">

		<div class="form-container">
			<h1 class="u-mb20"><?= tohtml( _("Add IP Address to Whitelist")) ?></h1>
			<?php show_alert_message($_SESSION); ?>
			<div class="u-mb20">
				<label for="v_ip" class="form-label">
					<?= tohtml( _("IP Address")) ?> <span class="optional">(<?= tohtml( _("Support CIDR format")) ?>)</span>
				</label>
				<input type="text" class="form-control" name="v_ip" id="v_ip" value="<?= tohtml(trim($v_ip, "'")) ?>" required>
				<p class="hint u-mt10">
					<?= tohtml( _("The address is exempted from every ban and removed from the ban list if it is currently banned. It is also mirrored into fail2ban, so its jails stop counting the address entirely.")) ?>
				</p>
			</div>
		</div>

	</form>

</div>
