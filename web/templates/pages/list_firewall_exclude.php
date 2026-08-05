<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/firewall/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml( _("Back")) ?>
			</a>
			<a href="/add/firewall/exclude/" class="button button-secondary js-button-create">
				<i class="fas fa-circle-plus icon-green"></i><?= tohtml( _("Add IP Address")) ?>
			</a>
		</div>
		<div class="toolbar-right">
			<form x-data x-bind="BulkEdit" action="/bulk/firewall/exclude/" method="post">
				<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
				<select class="form-select" name="action">
					<option value=""><?= tohtml( _("Apply to selected")) ?></option>
					<option value="delete"><?= tohtml( _("Delete")) ?></option>
				</select>
				<button type="submit" class="toolbar-input-submit" title="<?= tohtml( _("Apply to selected")) ?>">
					<i class="fas fa-arrow-right"></i>
				</button>
			</form>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container">

	<h1 class="u-text-center u-hide-desktop u-mt20 u-pr30 u-mb20 u-pl30"><?= tohtml( _("Whitelisted IP Addresses")) ?></h1>

	<p class="u-mb20">
		<?= tohtml( _("A whitelisted address is accepted ahead of every ban and can no longer be banned. Adding your own address here is what recovers a lockout.")) ?>
	</p>

	<div class="units-table js-units-container">
		<div class="units-table-header">
			<div class="units-table-cell">
				<input type="checkbox" class="js-toggle-all-checkbox" title="<?= tohtml( _("Select all")) ?>">
			</div>
			<div class="units-table-cell"><?= tohtml( _("IP Address")) ?></div>
			<div class="units-table-cell"></div>
		</div>

		<!-- Begin whitelisted IP address list item loop -->
		<?php
			foreach ($data as $key => $value) {
				++$i;
				$ip = $key;
			?>
			<div class="units-table-row js-unit">
				<div class="units-table-cell">
					<div>
						<input id="check<?= tohtml($i) ?>" class="js-unit-checkbox" type="checkbox" title="<?= tohtml( _("Select")) ?>" name="ip[]" value="<?= tohtml($ip) ?>">
						<label for="check<?= tohtml($i) ?>" class="u-hide-desktop"><?= tohtml( _("Select")) ?></label>
					</div>
				</div>
				<div class="units-table-cell units-table-heading-cell u-text-bold">
					<span class="u-hide-desktop"><?= tohtml( _("IP Address")) ?>:</span>
					<?= tohtml($ip) ?>
				</div>
				<div class="units-table-cell">
					<ul class="units-table-row-actions">
						<li class="units-table-row-action shortcut-delete" data-key-action="js">
							<a
								class="units-table-row-action-link data-controls js-confirm-action"
								href="/delete/firewall/exclude/?<?= tohtml(http_build_query(["ip" => $ip, "token" => $_SESSION["token"]])) ?>"
								title="<?= tohtml( _("Delete")) ?>"
								data-confirm-title="<?= tohtml( _("Delete")) ?>"
								data-confirm-message="<?= tohtml(sprintf(_("Are you sure you want to remove IP address %s from the whitelist?"), $key)) ?>"
							>
								<i class="fas fa-trash icon-red"></i>
								<span class="u-hide-desktop"><?= tohtml( _("Delete")) ?></span>
							</a>
						</li>
					</ul>
				</div>
			</div>
		<?php } ?>
	</div>

	<div class="units-table-footer">
		<p>
			<?php
				if ( $i == 0) {
					echo _('There are currently no whitelisted IP addresses.');
				} else {
					printf(ngettext('%d whitelisted IP address', '%d whitelisted IP addresses', $i),$i);
				}
			?>
		</p>
	</div>

</div>
