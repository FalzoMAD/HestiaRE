<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/firewall/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml(_("Back")) ?>
			</a>
			<?php if ($mesh_enabled): ?>
				<a href="/add/firewall/mesh/" class="button button-secondary js-button-create">
					<i class="fas fa-circle-plus icon-green"></i><?= tohtml(_("Join a Peer")) ?>
				</a>
				<form method="post" action="/generate/mesh-pairing/" class="u-inline">
					<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
					<button type="submit" class="button button-secondary">
						<i class="fas fa-key icon-orange"></i><?= tohtml(_("Generate Pairing Code")) ?>
					</button>
				</form>
			<?php endif; ?>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container">

	<h1 class="u-text-center u-hide-desktop u-mt20 u-pr30 u-mb20 u-pl30"><?= tohtml(_("Fleet Mesh")) ?></h1>

	<?php show_alert_message($_SESSION); ?>

	<?php if (!$mesh_enabled): ?>
		<div class="form-container">
			<p><?= tohtml(_("CrowdSec fleet-mesh is not enabled on this server.")) ?></p>
			<p class="hint"><code>h-add-sys-crowdsec-mesh</code></p>
		</div>
	<?php else: ?>

		<?php if (!empty($pairing_code)): ?>
			<!-- Shown once, from the session: the plaintext exists nowhere else. -->
			<div class="form-container u-mb20">
				<label class="form-label"><?= tohtml(_("Pairing Code")) ?></label>
				<input type="text" class="form-control" value="<?= tohtml($pairing_code) ?>" readonly onclick="this.select()">
				<p class="hint"><?= tohtml($pairing_note) ?></p>
			</div>
		<?php endif; ?>

		<div class="units-table js-units-container">
			<div class="units-table-header">
				<div class="units-table-cell"><?= tohtml(_("Peer")) ?></div>
				<div class="units-table-cell"></div>
				<div class="units-table-cell u-text-center"><?= tohtml(_("Address")) ?></div>
				<div class="units-table-cell u-text-center"><?= tohtml(_("Shared Bans")) ?></div>
				<div class="units-table-cell u-text-center"><?= tohtml(_("Date")) ?></div>
			</div>

			<!-- Begin mesh peer list item loop -->
			<?php
				foreach ($data as $key => $value) {
					++$i;
					?>
				<div class="units-table-row js-unit">
					<div class="units-table-cell units-table-heading-cell u-text-bold">
						<span class="u-hide-desktop"><?= tohtml(_("Peer")) ?>:</span>
						<?= tohtml($key) ?>
					</div>
					<div class="units-table-cell">
						<ul class="units-table-row-actions">
							<li class="units-table-row-action shortcut-delete" data-key-action="js">
								<a
									class="units-table-row-action-link data-controls js-confirm-action"
									href="/delete/firewall/mesh/?<?= tohtml(http_build_query(["peer" => $key, "token" => $_SESSION["token"]])) ?>"
									title="<?= tohtml(_("Unpair")) ?>"
									data-confirm-title="<?= tohtml(_("Unpair")) ?>"
									data-confirm-message="<?= tohtml(sprintf(_("Are you sure you want to unpair %s? Run the same action on that server too."), $key)) ?>"
								>
									<i class="fas fa-trash icon-red"></i>
									<span class="u-hide-desktop"><?= tohtml(_("Unpair")) ?></span>
								</a>
							</li>
						</ul>
					</div>
					<div class="units-table-cell u-text-center-desktop">
						<span class="u-hide-desktop u-text-bold"><?= tohtml(_("Address")) ?>:</span>
						<?= tohtml($value["HOST"]) ?>:<?= tohtml($value["PORT"]) ?>
					</div>
					<div class="units-table-cell u-text-center-desktop">
						<span class="u-hide-desktop u-text-bold"><?= tohtml(_("Shared Bans")) ?>:</span>
						<?= tohtml($value["BANS"]) ?>
					</div>
					<div class="units-table-cell u-text-center-desktop">
						<span class="u-hide-desktop u-text-bold"><?= tohtml(_("Date")) ?>:</span>
						<time datetime="<?= tohtml($value["DATE"]) ?>"><?= tohtml($value["DATE"]) ?></time>
					</div>
				</div>
			<?php } ?>
		</div>

		<div class="units-table-footer">
			<p>
				<?php
						if ($i == 0) {
							echo _('No peers paired yet. Generate a code here, then join from the other server - or ask its admin for a code and use "Join a Peer".');
						} else {
							printf(ngettext('%d peer', '%d peers', $i), $i);
						}
				?>
			</p>
		</div>

	<?php endif; ?>

</div>
