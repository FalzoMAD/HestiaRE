<?php
$v_webmail_alias = "webmail";
if (!empty($_SESSION["WEBMAIL_ALIAS"])) {
	$v_webmail_alias = $_SESSION["WEBMAIL_ALIAS"];
}
?>
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/mail/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml(_("Back")) ?>
			</a>
		</div>
		<div class="toolbar-right"></div>
	</div>
</div>

<div class="container">

	<h1 class="u-text-center u-hide-desktop u-mt20 u-pr30 u-mb20 u-pl30"><?= tohtml(_("DNS Records")) ?></h1>

	<div class="units-table js-units-container">
		<div class="units-table-header">
			<div class="units-table-cell"><?= tohtml(_("Record")) ?></div>
			<div class="units-table-cell u-text-center"><?= tohtml(_("Type")) ?></div>
			<div class="units-table-cell u-text-center"><?= tohtml(_("Priority")) ?></div>
			<div class="units-table-cell u-text-center"><?= tohtml(_("TTL")) ?></div>
			<div class="units-table-cell"><?= tohtml(_("IP or Value")) ?></div>
		</div>

		<?php
		// Family-resolved picks: with v6 IP objects in the pool, array_key_first could hand a
		// v6 to the A row (lexicographic order). A prefers v4; AAAA renders when a v6 exists.
		$first_v4 = "";
		$first_v6 = "";
		foreach ($ips as $k => $v) {
			if (str_contains($k, ":")) {
				$first_v6 = $first_v6 ?: $k;
			} else {
				$first_v4 = $first_v4 ?: (empty($v["NAT"]) ? $k : $v["NAT"]);
			}
		}
		$dns_a_value = $first_v4 ?: $first_v6;
		?>
		<div class="units-table-row js-unit">
			<div class="units-table-cell">
				<label class="u-hide-desktop u-text-bold"><?= tohtml(_("Record")) ?>:</label>
				<input type="text" class="form-control" value="mail.<?= tohtml($_GET["domain"]) ?>">
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("Type")) ?>:</span>
				A
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("Priority")) ?>:</span>
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("TTL")) ?>:</span>
				14400
			</div>
			<div class="units-table-cell u-text-center-desktop">
				<label class="u-hide-desktop u-text-bold"><?= tohtml(_("IP or Value")) ?>:</label>
				<input type="text" class="form-control" value="<?= tohtml($dns_a_value) ?>">
			</div>
		</div>
		<?php if ($first_v6 !== "") { ?>
		<div class="units-table-row js-unit">
			<div class="units-table-cell">
				<label class="u-hide-desktop u-text-bold"><?= tohtml(_("Record")) ?>:</label>
				<input type="text" class="form-control" value="mail.<?= tohtml($_GET["domain"]) ?>">
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("Type")) ?>:</span>
				AAAA
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("Priority")) ?>:</span>
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("TTL")) ?>:</span>
				14400
			</div>
			<div class="units-table-cell u-text-center-desktop">
				<label class="u-hide-desktop u-text-bold"><?= tohtml(_("IP or Value")) ?>:</label>
				<input type="text" class="form-control" value="<?= tohtml($first_v6) ?>">
			</div>
		</div>
		<?php } ?>
		<?php if ($_SESSION["WEBMAIL_SYSTEM"]) { ?>
			<div class="units-table-row js-unit">
				<div class="units-table-cell">
					<label class="u-hide-desktop u-text-bold"><?= tohtml(_("Record")) ?>:</label>
					<input type="text" class="form-control" value="<?= tohtml($v_webmail_alias) ?>.<?= tohtml($_GET["domain"]) ?>">
				</div>
				<div class="units-table-cell u-text-bold u-text-center-desktop">
					<span class="u-hide-desktop"><?= tohtml(_("Type")) ?>:</span>
					A
				</div>
				<div class="units-table-cell u-text-bold u-text-center-desktop">
					<span class="u-hide-desktop"><?= tohtml(_("Priority")) ?>:</span>
				</div>
				<div class="units-table-cell u-text-bold u-text-center-desktop">
					<span class="u-hide-desktop"><?= tohtml(_("TTL")) ?>:</span>
					14400
				</div>
				<div class="units-table-cell u-text-center-desktop">
					<label class="u-hide-desktop u-text-bold"><?= tohtml(_("IP or Value")) ?>:</label>
					<input type="text" class="form-control" value="<?= tohtml($dns_a_value) ?>">
				</div>
			</div>
		<?php } ?>
		<div class="units-table-row js-unit">
			<div class="units-table-cell">
				<label class="u-hide-desktop u-text-bold"><?= tohtml(_("Record")) ?>:</label>
				<input type="text" class="form-control" value="<?= tohtml($_GET["domain"]) ?>">
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("Type")) ?>:</span>
				MX
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("Priority")) ?>:</span>
				10
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("TTL")) ?>:</span>
				14400
			</div>
			<div class="units-table-cell u-text-center-desktop">
				<label class="u-hide-desktop u-text-bold"><?= tohtml(_("IP or Value")) ?>:</label>
				<input type="text" class="form-control" value="mail.<?= tohtml($_GET["domain"]) ?>.">
			</div>
		</div>
		<div class="units-table-row js-unit">
			<div class="units-table-cell">
				<label class="u-hide-desktop u-text-bold"><?= tohtml(_("Record")) ?>:</label>
				<input type="text" class="form-control" value="<?= tohtml($_GET["domain"]) ?>">
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("Type")) ?>:</span>
				TXT
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("Priority")) ?>:</span>
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("TTL")) ?>:</span>
				14400
			</div>
			<div class="units-table-cell u-text-center-desktop">
				<label class="u-hide-desktop u-text-bold"><?= tohtml(_("IP or Value")) ?>:</label>
				<?php
				$ip = $dns_a_value;
// SPF wants the bare address behind a family-matched mechanism; a v6 behind ip4: is an
// invalid record. v4 preferred until #891 feeds this from OUTGOING_IP, both families in one line.
$spf_mech = str_contains($ip, ":") ? "ip6" : "ip4";
?>
				<input type="text" class="form-control" value="<?= tohtml("v=spf1 a mx " . $spf_mech . ":" . $ip . " -all") ?>">
			</div>
		</div>
		<div class="units-table-row js-unit">
			<div class="units-table-cell">
				<label class="u-hide-desktop u-text-bold"><?= tohtml(_("Record")) ?>:</label>
				<input type="text" class="form-control" value="_dmarc">
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("Type")) ?>:</span>
				TXT
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("Priority")) ?>:</span>
			</div>
			<div class="units-table-cell u-text-bold u-text-center-desktop">
				<span class="u-hide-desktop"><?= tohtml(_("TTL")) ?>:</span>
				14400
			</div>
			<div class="units-table-cell u-text-center-desktop">
				<label class="u-hide-desktop u-text-bold"><?= tohtml(_("IP or Value")) ?>:</label>
				<input type="text" class="form-control" value="<?= tohtml("v=DMARC1; p=quarantine; pct=100") ?>">
			</div>
		</div>
		<?php foreach ($dkim as $key => $value) { ?>
			<div class="units-table-row js-unit">
				<div class="units-table-cell">
					<label class="u-hide-desktop u-text-bold"><?= tohtml(_("Record")) ?>:</label>
					<input type="text" class="form-control" value="<?= tohtml($key) ?>">
				</div>
				<div class="units-table-cell u-text-bold u-text-center-desktop">
					<span class="u-hide-desktop"><?= tohtml(_("Type")) ?>:</span>
					TXT
				</div>
				<div class="units-table-cell u-text-bold u-text-center-desktop">
					<span class="u-hide-desktop"><?= tohtml(_("Priority")) ?>:</span>
				</div>
				<div class="units-table-cell u-text-bold u-text-center-desktop">
					<span class="u-hide-desktop"><?= tohtml(_("TTL")) ?>:</span>
					3600
				</div>
				<div class="units-table-cell u-text-center-desktop">
					<label class="u-hide-desktop u-text-bold"><?= tohtml(_("IP or Value")) ?>:</label>
					<input type="text" class="form-control" value="<?= tohtml(str_replace(['"', "'"], "", $dkim[$key]["TXT"])) ?>">
				</div>
			</div>
		<?php } ?>
	</div>

</div>
