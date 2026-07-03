<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/server/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml( _("Back")) ?>
			</a>
			<a href="/list/server/?cpu" class="button button-secondary">
				<i class="fas fa-chart-pie icon-green"></i><?= tohtml( _("Advanced Details")) ?>
			</a>
		</div>
		<div class="toolbar-right">
			<a class="toolbar-link<?php if ((empty($period)) || ($period == 'daily')) echo " selected" ?>" href="?<?= tohtml(http_build_query(["period" => 'daily'])) ?>"><?= tohtml( _("Daily")) ?></a>
			<a class="toolbar-link<?php if ((!empty($period)) && ($period == 'weekly')) echo " selected" ?>" href="?<?= tohtml(http_build_query(["period" => 'weekly'])) ?>"><?= tohtml( _("Weekly")) ?></a>
			<a class="toolbar-link<?php if ((!empty($period)) && ($period == 'monthly')) echo " selected" ?>" href="?<?= tohtml(http_build_query(["period" => 'monthly'])) ?>"><?= tohtml( _("Monthly")) ?></a>
			<a class="toolbar-link<?php if ((!empty($period)) && ($period == 'yearly')) echo " selected" ?>" href="?<?= tohtml(http_build_query(["period" => 'yearly'])) ?>"><?= tohtml( _("Yearly")) ?></a>
                        <a class="toolbar-link<?php if ((!empty($period)) && ($period == 'biennially')) echo " selected" ?>" href="?<?= tohtml(http_build_query(["period" => 'biennially'])) ?>"><?= tohtml( _("Biennially")) ?></a>
                        <a class="toolbar-link<?php if ((!empty($period)) && ($period == 'triennially')) echo " selected" ?>" href="?<?= tohtml(http_build_query(["period" => 'triennially'])) ?>"><?= tohtml( _("Triennially")) ?></a>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container">
	<div class="form-container form-container-wide">
		<!-- Begin graph list item loop -->
		<?php // Graphs are PNGs rendered server-side by rrdtool graph in the same
		// h-update-sys-rrd-* cron scripts that feed the RRD databases; image.php
		// delivers them via X-Accel-Redirect through the panel Caddy. ?>
		<?php foreach ($data as $key => $value) { ?>
			<div class="u-mb40">
				<h2 class="u-mb20"><?= tohtml($data[$key]["TITLE"]) ?></h2>
				<img
					class="u-max-height300"
					src="/list/rrd/image.php?/rrd/<?= tohtml($data[$key]["TYPE"]) ?>/<?= tohtml($period . "-" . $data[$key]["RRD"]) ?>.png"
					alt="<?= tohtml($data[$key]["TITLE"]) ?>"
				>
			</div>
		<?php } ?>
	</div>
</div>
