<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/server/">
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

	<form id="main-form" name="v_edit_botlimit" method="post">
		<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
		<input type="hidden" name="save" value="save">

		<div class="form-container">
			<h1 class="u-mb20"><?= tohtml( _("Bot Rate Limiting")) ?></h1>
			<?php show_alert_message($_SESSION); ?>
			<p class="hint u-mb20">
				<?= tohtml( _("Bot families are matched on the User-Agent and throttled to the rate below (HTTP 429). Humans are never limited; malicious traffic is handled by CrowdSec, not here. Each domain then picks off, lenient or strict per family - nothing is throttled until you do.")) ?>
				<?php if ($v_front == "nginx") { ?>
					<br><?= tohtml( _("Enforced by")) ?>: nginx <code>limit_req</code>
				<?php } elseif ($v_front == "apache2") { ?>
					<br><?= tohtml( _("Enforced by")) ?>: apache <code>mod_qos</code> (<?= tohtml( _("per client IP")) ?>)
				<?php } ?>
			</p>

			<?php foreach ($rows as $i => $r) { ?>
				<details class="box-collapse u-mb10">
					<summary class="box-collapse-header">
						<i class="fas fa-robot u-mr10"></i>
						<?php if ($r["fam"] === "") { ?>
							<span class="optional"><?= tohtml( _("unused slot")) ?></span>
						<?php } else { ?>
							<?= tohtml($r["fam"]) ?>
							<span class="optional u-ml5">
								<?= tohtml($r["lenient"]) ?> / <?= tohtml($r["strict"]) ?>
								<?php if (!$r["enabled"]) { ?>- <?= tohtml( _("Disabled")) ?><?php } ?>
							</span>
						<?php } ?>
					</summary>
					<div class="box-collapse-content">
					<input type="hidden" name="orig[<?= tohtml($i) ?>]" value="<?= tohtml($r["orig"]) ?>">
					<div class="u-mb10">
						<label for="fam<?= tohtml($i) ?>" class="form-label">
							<?= tohtml( _("Family")) ?>
							<span class="optional">(<?= tohtml( _("empty to remove")) ?>)</span>
						</label>
						<input type="text" class="form-control" name="fam[<?= tohtml($i) ?>]" id="fam<?= tohtml($i) ?>" value="<?= tohtml($r["fam"]) ?>" placeholder="<?= tohtml( _("unused slot")) ?>">
					</div>
					<div class="u-mb10">
						<label for="match<?= tohtml($i) ?>" class="form-label">
							<?= tohtml( _("User-Agent Match")) ?> <span class="optional">(<?= tohtml( _("tokens separated by |")) ?>)</span>
						</label>
						<input type="text" class="form-control" name="match[<?= tohtml($i) ?>]" id="match<?= tohtml($i) ?>" value="<?= tohtml($r["match"]) ?>" placeholder="examplebot|example-crawler">
					</div>
					<div class="u-mb10">
						<label for="lenient<?= tohtml($i) ?>" class="form-label"><?= tohtml( _("Lenient")) ?></label>
						<input type="text" class="form-control" name="lenient[<?= tohtml($i) ?>]" id="lenient<?= tohtml($i) ?>" value="<?= tohtml($r["lenient"]) ?>" placeholder="60r/m">
					</div>
					<div class="u-mb10">
						<label for="strict<?= tohtml($i) ?>" class="form-label"><?= tohtml( _("Strict")) ?></label>
						<input type="text" class="form-control" name="strict[<?= tohtml($i) ?>]" id="strict<?= tohtml($i) ?>" value="<?= tohtml($r["strict"]) ?>" placeholder="20r/m">
					</div>
					<div class="u-mb10">
						<label for="enabled<?= tohtml($i) ?>" class="form-label"><?= tohtml( _("Enabled")) ?></label>
						<select class="form-select" name="enabled[<?= tohtml($i) ?>]" id="enabled<?= tohtml($i) ?>">
							<option value="yes" <?php if ($r["enabled"]) echo "selected"; ?>><?= tohtml( _("yes")) ?></option>
							<option value="no" <?php if (!$r["enabled"]) echo "selected"; ?>><?= tohtml( _("no")) ?></option>
						</select>
					</div>
					<?php if ($r["burst"] !== "") { ?>
						<p class="hint">
							<?= tohtml( _("Advanced (config file only)")) ?>:
							burst=<?= tohtml($r["burst"]) ?><?php if ($r["nodelay"] == "yes") { ?>, nodelay<?php } ?>
						</p>
					<?php } ?>
					</div>
				</details>
			<?php } ?>

			<p class="hint">
				<?= tohtml( _("Disabling or removing a family also stops it being applied to any domain that used it.")) ?>
			</p>
		</div>

	</form>

</div>
