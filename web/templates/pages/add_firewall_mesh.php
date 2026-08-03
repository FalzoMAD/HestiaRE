<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/firewall/mesh/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml( _("Back")) ?>
			</a>
		</div>
		<div class="toolbar-buttons">
			<button type="submit" class="button" form="main-form">
				<i class="fas fa-link icon-purple"></i><?= tohtml( _("Pair")) ?>
			</button>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container">

	<form id="main-form" name="v_add_mesh_peer" method="post">
		<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
		<input type="hidden" name="ok" value="Add">

		<div class="form-container">
			<h1 class="u-mb20"><?= tohtml( _("Join a Mesh Peer")) ?></h1>
			<?php show_alert_message($_SESSION); ?>
			<p class="hint u-mb20">
				<?= tohtml( _("Ask the other server's admin to generate a pairing code on its own Fleet Mesh page. Both servers then share their web-tier bans, and each opens its panel port for the other only.")) ?>
			</p>
			<div class="u-mb20">
				<label for="v_host" class="form-label"><?= tohtml( _("Hostname")) ?></label>
				<input type="text" class="form-control" name="v_host" id="v_host" value="<?= tohtml($v_host) ?>" required>
			</div>
			<div class="u-mb20">
				<label for="v_port" class="form-label"><?= tohtml( _("Panel Port")) ?></label>
				<input type="text" class="form-control" name="v_port" id="v_port" value="<?= tohtml($v_port) ?>">
			</div>
			<div class="u-mb10">
				<label for="v_code" class="form-label"><?= tohtml( _("Pairing Code")) ?></label>
				<input type="text" class="form-control" name="v_code" id="v_code" autocomplete="off" required>
			</div>
		</div>

	</form>

</div>
