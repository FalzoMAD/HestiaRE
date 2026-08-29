<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/package/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml(_("Back")) ?>
			</a>
		</div>
		<div class="toolbar-buttons">
			<button type="submit" class="button" form="main-form">
				<i class="fas fa-floppy-disk icon-purple"></i><?= tohtml(_("Save")) ?>
			</button>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container">

	<form
		id="main-form"
		name="v_edit_package"
		method="post"
		class="<?= tohtml($v_status) ?>"
	>
		<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
		<input type="hidden" name="save" value="save">

		<div class="form-container">
			<h1 class="u-mb20"><?= tohtml(_("Edit Package")) ?></h1>
			<?php show_alert_message($_SESSION); ?>
			<div class="u-mb10">
				<label for="v_package_new" class="form-label"><?= tohtml(_("Package Name")) ?></label>
				<input type="text" class="form-control" name="v_package_new" id="v_package_new" value="<?= tohtml(trim($v_package_new, "'")) ?>" required>
				<input type="hidden" name="v_package" value="<?= tohtml(trim($v_package, "'")) ?>">
			</div>
			<?php if ($offer_quota) { ?>
			<div class="u-mb10">
				<label for="v_disk_quota" class="form-label">
					<?= tohtml(_("Quota")) ?> <span class="optional">(<?= tohtml(_("in MB")) ?>)</span>
				</label>
				<div class="u-pos-relative">
					<input type="text" class="form-control" name="v_disk_quota" id="v_disk_quota" value="<?= tohtml(trim($v_disk_quota, "'")) ?>">
					<button type="button" class="unlimited-toggle js-unlimited-toggle" title="<?= tohtml(_("Unlimited")) ?>">
						<i class="fas fa-infinity"></i>
					</button>
				</div>
			</div>
			<?php } ?>
			<div class="u-mb10">
				<label for="v_bandwidth" class="form-label">
					<?= tohtml(_("Bandwidth")) ?> <span class="optional">(<?= tohtml(_("in MB")) ?>)</span>
				</label>
				<div class="u-pos-relative">
					<input type="text" class="form-control" name="v_bandwidth" id="v_bandwidth" value="<?= tohtml(trim($v_bandwidth, "'")) ?>">
					<button type="button" class="unlimited-toggle js-unlimited-toggle" title="<?= tohtml(_("Unlimited")) ?>">
						<i class="fas fa-infinity"></i>
					</button>
				</div>
			</div>
			<div class="u-mb10">
				<label for="v_backups" class="form-label"><?= tohtml(_("Backups")) ?></label>
				<input type="text" class="form-control" name="v_backups" id="v_backups" value="<?= tohtml(trim($v_backups, "'")) ?>">
			</div>
			<div class="u-mb10">
				<label for="v_backups_mode" class="form-label"><?= tohtml(_("Backup Mode")) ?></label>
				<select class="form-select" name="v_backups_mode" id="v_backups_mode">
					<option value="full"><?= tohtml(_("Full")) ?></option>
					<option value="diff" <?php if ('diff' == trim($v_backups_mode, "'")): ?>
						selected
					<?php endif; ?>><?= tohtml(_("Differential")) ?></option>
					<?php if (($_SESSION["BACKUP_INCREMENTAL"] ?? "") === "yes" || 'restic' == trim($v_backups_mode, "'")): ?>
						<option value="restic" <?php if ('restic' == trim($v_backups_mode, "'")): ?>
							selected
						<?php endif; ?>><?= tohtml(_("restic (addon)")) ?></option>
					<?php endif; ?>
				</select>
			</div>
			<details class="collapse" id="web-options">
				<summary class="collapse-header">
					<?= tohtml(_("WEB")) ?>
				</summary>
				<div class="collapse-content">
					<div class="u-mb10">
						<label for="v_web_domains" class="form-label"><?= tohtml(_("Web Domains")) ?></label>
						<div class="u-pos-relative">
							<input type="text" class="form-control" name="v_web_domains" id="v_web_domains" value="<?= tohtml(trim($v_web_domains, "'")) ?>">
							<button type="button" class="unlimited-toggle js-unlimited-toggle" title="<?= tohtml(_("Unlimited")) ?>">
								<i class="fas fa-infinity"></i>
							</button>
						</div>
					</div>
					<div class="u-mb10">
						<label for="v_web_aliases" class="form-label">
							<?= tohtml(_("Web Aliases")) ?> <span class="optional">(<?= tohtml(_("per domain")) ?>)</span>
						</label>
						<div class="u-pos-relative">
							<input type="text" class="form-control" name="v_web_aliases" id="v_web_aliases" value="<?= tohtml(trim($v_web_aliases, "'")) ?>">
							<button type="button" class="unlimited-toggle js-unlimited-toggle" title="<?= tohtml(_("Unlimited")) ?>">
								<i class="fas fa-infinity"></i>
							</button>
						</div>
					</div>
					<?php // No selectable web template on an apache web role - an empty required
						 // select cannot be answered, and it submits no key at all.?>
					<?php if ($offer_web_template) { ?>
					<div class="u-mb10">
						<label for="v_web_template" class="form-label">
							<?= tohtml(_("Web Template")) ?> <span class="optional"><?= tohtml(strtoupper($_SESSION["WEB_SYSTEM"])) ?></span>
						</label>
						<select class="form-select" name="v_web_template" id="v_web_template">
							<?php
							foreach ($web_templates as $key => $value) {
								echo "\t\t\t\t<option value=\"" . htmlentities($value) . "\"";
								if ((!empty($v_web_template)) && ($value == trim($v_web_template, "'"))) {
									echo ' selected';
								}
								echo ">" . htmlentities($value) . "</option>\n";
							}
						?>
						</select>
					</div>
					<?php } ?>
					<?php if ($offer_backend_template) { ?>
						<div class="u-mb10">
								<label for="v_backend_template" class="form-label">
									<?= tohtml(_("Backend Template")) ?> <span class="optional"><?= tohtml(strtoupper($_SESSION["WEB_BACKEND"])) ?></span>
								</label>
							<select class="form-select" name="v_backend_template" id="v_backend_template">
								<?php
								foreach ($backend_templates as $key => $value) {
									echo "\t\t\t\t<option value=\"" . $value . "\"";
									if ((!empty($v_backend_template)) && ($value == trim($v_backend_template, "'"))) {
										echo ' selected';
									}
									echo ">" . htmlentities($value) . "</option>\n";
								}
						?>
							</select>
						</div>
							<?php } ?>
					<?php # one template is not a choice: carry the value, drop the control
						if ($offer_proxy_template && count($proxy_templates ?? []) < 2) { ?>
						<input type="hidden" name="v_proxy_template" value="<?= tohtml(trim($v_proxy_template ?? "", "'") ?: ($proxy_templates[0] ?? 'default')) ?>">
					<?php } elseif ($offer_proxy_template) { ?>
						<div class="u-mb10">
								<label for="v_proxy_template" class="form-label">
									<?= tohtml(_("Proxy Template")) ?> <span class="optional"><?= tohtml(strtoupper($_SESSION["PROXY_SYSTEM"])) ?></span>
								</label>
							<select class="form-select" name="v_proxy_template" id="v_proxy_template">
								<?php
						foreach ($proxy_templates as $key => $value) {
							echo "\t\t\t\t<option value=\"" . htmlentities($value) . "\"";
							if ((!empty($v_proxy_template)) && ($value == trim($v_proxy_template, "'"))) {
								echo ' selected';
							}
							echo ">" . htmlentities($value) . "</option>\n";
						}
						?>
							</select>
						</div>
							<?php } ?>
				</div>
			</details>
			<details class="collapse" id="mail-options">
				<summary class="collapse-header">
					<?= tohtml(_("MAIL")) ?>
				</summary>
				<div class="collapse-content">
					<div class="u-mb10">
						<label for="v_mail_domains" class="form-label"><?= tohtml(_("Mail Domains")) ?></label>
						<div class="u-pos-relative">
							<input type="text" class="form-control" name="v_mail_domains" id="v_mail_domains" value="<?= tohtml(trim($v_mail_domains, "'")) ?>">
							<button type="button" class="unlimited-toggle js-unlimited-toggle" title="<?= tohtml(_("Unlimited")) ?>">
								<i class="fas fa-infinity"></i>
							</button>
						</div>
					</div>
					<div class="u-mb10">
						<label for="v_mail_accounts" class="form-label">
							<?= tohtml(_("Mail Accounts")) ?> <span class="optional">(<?= tohtml(_("per domain")) ?>)</span>
						</label>
						<div class="u-pos-relative">
							<input type="text" class="form-control" name="v_mail_accounts" id="v_mail_accounts" value="<?= tohtml(trim($v_mail_accounts, "'")) ?>">
							<button type="button" class="unlimited-toggle js-unlimited-toggle" title="<?= tohtml(_("Unlimited")) ?>">
								<i class="fas fa-infinity"></i>
							</button>
						</div>
					</div>
					<div class="u-mb10">
						<label for="v_ratelimit" class="form-label">
							<?= tohtml(_("Rate Limit")) ?> <span class="optional">(<?= tohtml(_("per account / hour")) ?>)</span>
						</label>
						<input type="text" class="form-control" name="v_ratelimit" id="v_ratelimit" value="<?= tohtml(trim($v_ratelimit, "'")) ?>">
					</div>
				</div>
			</details>
			<details class="collapse" id="database-options">
				<summary class="collapse-header">
					<?= tohtml(_("DB")) ?>
				</summary>
				<div class="collapse-content">
					<div class="u-mb10">
						<label for="v_databases" class="form-label"><?= tohtml(_("Databases")) ?></label>
						<div class="u-pos-relative">
							<input type="text" class="form-control" name="v_databases" id="v_databases" value="<?= tohtml(trim($v_databases, "'")) ?>">
							<button type="button" class="unlimited-toggle js-unlimited-toggle" title="<?= tohtml(_("Unlimited")) ?>">
								<i class="fas fa-infinity"></i>
							</button>
						</div>
					</div>
				</div>
			</details>
			<details class="collapse" id="system-options">
				<summary class="collapse-header">
					<?= tohtml(_("System")) ?>
				</summary>
				<div class="collapse-content">
					<div class="u-mb10">
						<label for="v_cron_jobs" class="form-label"><?= tohtml(_("Cron Jobs")) ?></label>
						<div class="u-pos-relative">
							<input type="text" class="form-control" name="v_cron_jobs" id="v_cron_jobs" value="<?= tohtml(trim($v_cron_jobs, "'")) ?>">
							<button type="button" class="unlimited-toggle js-unlimited-toggle" title="<?= tohtml(_("Unlimited")) ?>">
								<i class="fas fa-infinity"></i>
							</button>
						</div>
					</div>
					<div class="u-mb10">
						<label for="v_shell" class="form-label"><?= tohtml(_("SSH Access")) ?></label>
						<select class="form-select" name="v_shell" id="v_shell">
							<?php
						// Preserve an existing off-allowlist shell as the selected
						// option so saving unchanged does not silently reset it (#412).
						$cur_shell = trim($v_shell, "'");
				if ($cur_shell !== "" && !in_array($cur_shell, $shells, true)): ?>
							<option value="<?= tohtml($cur_shell) ?>" selected><?= tohtml($cur_shell) ?> <?= _("(current)") ?></option>
							<?php endif; ?>
							<?php foreach ($shells as $key => $value): ?>
								<option value="<?= tohtml($value) ?>"
									<?php if (!empty($v_shell) && $value == trim($v_shell, "''")): ?>
										selected
									<?php endif; ?>
								>
									<?= tohtml($value) ?>
								</option>
							<?php endforeach; ?>
						</select>
					</div>
				</div>
			</details>

			<?php # a per-docker-customer cap, so the addon decides whether it is offered
				if ($offer_docker_limit) { ?>
				<details class="collapse" id="docker-options">
					<summary class="collapse-header">
						<?= tohtml(_("DOCKER")) ?>
					</summary>
					<div class="collapse-content">
						<div class="u-mb10">
							<label for="v_docker_limit" class="form-label">
								<?= tohtml(_("Resource cap")) ?>
							</label>
							<select class="form-select" name="v_docker_limit" id="v_docker_limit">
								<?php
					$docker_presets = [
						"unlimited" => _("Unlimited"),
						"low" => "low (10% RAM, 50% CPU, 512 tasks)",
						"medium" => "medium (25% RAM, 100% CPU, 1024 tasks)",
						"high" => "high (50% RAM, 200% CPU, 2048 tasks)",
					];
					$cur_docker_limit = trim($v_docker_limit ?? "", "'") ?: "unlimited";
					foreach ($docker_presets as $key => $label) {
						echo "\t\t\t\t<option value=\"" . tohtml($key) . "\"";
						if ($cur_docker_limit == $key) {
							echo " selected";
						}
						echo ">" . tohtml($label) . "</option>\n";
					}
					?>
							</select>
							<small class="form-text text-muted"><?= tohtml(_("Caps the customer's Docker companion - the daemon and all of their containers together. Percentages are of the host: 100% CPU is one core.")) ?></small>
						</div>
					</div>
				</details>
			<?php } ?>

		</div>

	</form>

</div>
