<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/firewall/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml(_("Back")) ?>
			</a>
			<a href="/add/firewall/banlist/" class="button button-secondary js-button-create">
				<i class="fas fa-circle-plus icon-green"></i><?= tohtml(_("Ban IP Address")) ?>
			</a>
		</div>
		<div class="toolbar-right">
			<form x-data x-bind="BulkEdit" action="/bulk/firewall/banlist/" method="post">
				<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
				<select class="form-select" name="action">
					<option value=""><?= tohtml(_("Apply to selected")) ?></option>
					<option value="delete"><?= tohtml(_("Delete")) ?></option>
				</select>
				<button type="submit" class="toolbar-input-submit" title="<?= tohtml(_("Apply to selected")) ?>">
					<i class="fas fa-arrow-right"></i>
				</button>
			</form>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container">

	<h1 class="u-text-center u-hide-desktop u-mt20 u-pr30 u-mb20 u-pl30"><?= tohtml(_("Banned IP Addresses")) ?></h1>

	<div class="units-table js-units-container">
		<div class="units-table-header">
			<div class="units-table-cell">
				<input type="checkbox" class="js-toggle-all-checkbox" title="<?= tohtml(_("Select all")) ?>">
			</div>
			<div class="units-table-cell"><?= tohtml(_("IP Address")) ?></div>
			<div class="units-table-cell"></div>
			<div class="units-table-cell u-text-center"><?= tohtml(_("Source")) ?></div>
			<div class="units-table-cell u-text-center"><?= tohtml(_("Chain / Scenario")) ?></div>
			<div class="units-table-cell u-text-center"><?= tohtml(_("When")) ?></div>
		</div>

		<!-- Begin banned IP address list item loop. Rows come from fail2ban (banlist.conf) and, when
		     CrowdSec is present, its local decisions; $value["SOURCE"] routes the unban. -->
		<?php
			foreach ($data as $key => $value) {
				++$i;
				$ip = $value["IP"];
				$source = $value["SOURCE"];
				$is_cs = $source === "crowdsec";
				$detail = $is_cs ? ($value["SCENARIO"] ?? "") : ($value["CHAIN"] ?? "");
				$when = $is_cs
					? ($value["UNTIL"] ?? "")
					: trim(($value["DATE"] ?? "") . " " . ($value["TIME"] ?? ""));
				// Bulk value carries the source so the bulk handler can route; "|" not ":" because an IPv6
				// address contains colons.
				$cbval = $source . "|" . $ip . "|" . ($value["CHAIN"] ?? "");
				$delq = $is_cs
					? ["ip" => $ip, "source" => "crowdsec", "token" => $_SESSION["token"]]
					: ["ip" => $ip, "chain" => $value["CHAIN"] ?? "", "token" => $_SESSION["token"]];
				?>
			<div class="units-table-row js-unit">
				<div class="units-table-cell">
					<div>
						<input id="check<?= tohtml($i) ?>" class="js-unit-checkbox" type="checkbox" title="<?= tohtml(_("Select")) ?>" name="ipchain[]" value="<?= tohtml($cbval) ?>">
						<label for="check<?= tohtml($i) ?>" class="u-hide-desktop"><?= tohtml(_("Select")) ?></label>
					</div>
				</div>
				<div class="units-table-cell units-table-heading-cell u-text-bold">
					<span class="u-hide-desktop"><?= tohtml(_("IP Address")) ?>:</span>
					<?= tohtml($ip) ?>
				</div>
				<div class="units-table-cell">
					<ul class="units-table-row-actions">
						<li class="units-table-row-action shortcut-delete" data-key-action="js">
							<a
								class="units-table-row-action-link data-controls js-confirm-action"
								href="/delete/firewall/banlist/?<?= tohtml(http_build_query($delq)) ?>"
								title="<?= tohtml(_("Delete")) ?>"
								data-confirm-title="<?= tohtml(_("Delete")) ?>"
								data-confirm-message="<?= tohtml(sprintf(_("Are you sure you want to delete IP address %s?"), $ip)) ?>"
							>
								<i class="fas fa-trash icon-red"></i>
								<span class="u-hide-desktop"><?= tohtml(_("Delete")) ?></span>
							</a>
						</li>
					</ul>
				</div>
				<div class="units-table-cell u-text-bold u-text-center-desktop">
					<span class="u-hide-desktop"><?= tohtml(_("Source")) ?>:</span>
					<?= tohtml($source) ?>
				</div>
				<div class="units-table-cell u-text-center-desktop">
					<span class="u-hide-desktop u-text-bold"><?= tohtml(_("Chain / Scenario")) ?>:</span>
					<?= tohtml(_($detail)) ?>
				</div>
				<div class="units-table-cell u-text-center-desktop">
					<span class="u-hide-desktop u-text-bold"><?= tohtml(_("When")) ?>:</span>
					<?= tohtml($when) ?>
				</div>
			</div>
		<?php } ?>
	</div>

	<div class="units-table-footer">
		<p>
			<?php
					if ($i == 0) {
						echo _('There are currently no banned IP addresses.');
					} else {
						printf(ngettext('%d banned IP address', '%d banned IP addresses', $i), $i);
					}
				?>
		</p>
	</div>

</div>
