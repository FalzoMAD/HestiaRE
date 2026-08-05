<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/firewall/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml( _("Back")) ?>
			</a>
			<a class="button button-secondary" href="/list/firewall/banlist/">
				<i class="fas fa-eye icon-red"></i><?= tohtml( _("Banned IP Addresses")) ?>
			</a>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container">

	<h1 class="u-text-center u-hide-desktop u-mt20 u-pr30 u-mb20 u-pl30"><?= tohtml( _("Jail Status")) ?></h1>

	<p class="u-mb20">
		<?= tohtml( _("Every jail this server configures, and what it is doing. A jail listed as stopped is configured but not running, which means it is protecting nothing.")) ?>
	</p>

	<div class="units-table js-units-container">
		<div class="units-table-header">
			<div class="units-table-cell"><?= tohtml( _("Jail")) ?></div>
			<div class="units-table-cell u-text-center"><?= tohtml( _("Status")) ?></div>
			<div class="units-table-cell u-text-center"><?= tohtml( _("Failures")) ?></div>
			<div class="units-table-cell u-text-center"><?= tohtml( _("Banned")) ?></div>
			<div class="units-table-cell"><?= tohtml( _("Log File")) ?></div>
		</div>

		<!-- Begin jail list item loop -->
		<?php
			foreach ($data as $key => $value) {
				++$i;
				$running = $value["STATE"] === "running";
			?>
			<div class="units-table-row js-unit">
				<div class="units-table-cell units-table-heading-cell u-text-bold">
					<span class="u-hide-desktop"><?= tohtml( _("Jail")) ?>:</span>
					<?= tohtml($key) ?>
				</div>
				<div class="units-table-cell u-text-center-desktop">
					<span class="u-hide-desktop u-text-bold"><?= tohtml( _("Status")) ?>:</span>
					<?php if ($running) { ?>
						<i class="fas fa-circle-check icon-green"></i> <?= tohtml( _("running")) ?>
					<?php } else { ?>
						<i class="fas fa-circle-exclamation icon-red"></i> <?= tohtml( _("stopped")) ?>
					<?php } ?>
				</div>
				<div class="units-table-cell u-text-center-desktop">
					<span class="u-hide-desktop u-text-bold"><?= tohtml( _("Failures")) ?>:</span>
					<?= tohtml($value["FAILED"]) ?> / <?= tohtml($value["FAILED_TOTAL"]) ?>
				</div>
				<div class="units-table-cell u-text-center-desktop">
					<span class="u-hide-desktop u-text-bold"><?= tohtml( _("Banned")) ?>:</span>
					<?= tohtml($value["BANNED"]) ?> / <?= tohtml($value["BANNED_TOTAL"]) ?>
				</div>
				<div class="units-table-cell">
					<span class="u-hide-desktop u-text-bold"><?= tohtml( _("Log File")) ?>:</span>
					<span class="u-text-small"><?= tohtml($value["LOGPATH"]) ?></span>
				</div>
			</div>
		<?php } ?>
	</div>

	<div class="units-table-footer">
		<p>
			<?php
				if ( $i == 0) {
					echo _('There are currently no jails configured.');
				} else {
					printf(ngettext('%d jail', '%d jails', $i),$i);
					echo " &mdash; " . _('current / total since the service started');
				}
			?>
		</p>
	</div>

</div>
