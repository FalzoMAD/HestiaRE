<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/user/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml(_("Back")) ?>
			</a>
			<?php
				if (($_SESSION['userContext'] === 'admin') && ($_SESSION['look'] === '') && ($_SESSION['user'] !== $v_username)) {
					$ssh_key_url = "/list/key/?user=".htmlentities($_GET['user'])."&token=".$_SESSION['token']."";
					$log_url = "/list/log/?user=".htmlentities($_GET['user'])."&token=".$_SESSION['token']."";
				} else {
					$ssh_key_url = "/list/key/";
					$log_url = "/list/log/";
				}
				?>
			<a href="<?= tohtml($ssh_key_url) ?>" class="button button-secondary js-button-create" title="<?= tohtml(_("Manage SSH Keys")) ?>">
				<i class="fas fa-key icon-orange"></i><?= tohtml(_("Manage SSH Keys")) ?>
			</a>
			<?php if ($_SESSION["userContext"] == "admin" || ($_SESSION["userContext"] !== "admin" && $_SESSION["POLICY_USER_VIEW_LOGS"] !== "no")) { ?>
				<a href="<?= tohtml($log_url) ?>" class="button button-secondary js-button-create" title="<?= tohtml(_("Logs")) ?>">
					<i class="fas fa-clock-rotate-left icon-maroon"></i><?= tohtml(_("Logs")) ?>
				</a>
			<?php } ?>
		</div>
		<div class="toolbar-buttons">
			<?php // Sits in the toolbar, outside the form that carries x-data - Alpine scopes by
			// DOM, not by the form attribute, so this owns the state and the form mirrors it.?>
			<button
				x-data="<?= tohtml(json_encode(["adv" => false, "labelOn" => _("Hide Advanced Options"), "labelOff" => _("Advanced Options")], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_THROW_ON_ERROR)) ?>"
				type="button"
				class="button button-secondary"
				x-on:click="adv = !adv; $dispatch('advanced-toggled', adv)"
				x-text="adv ? labelOn : labelOff">
				<?= tohtml(_("Advanced Options")) ?>
			</button>
			<button type="submit" class="button" form="main-form">
				<i class="fas fa-floppy-disk icon-purple"></i><?= tohtml(_("Save")) ?>
			</button>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container">

	<form
		x-data="{
			loginDisabled: <?= tohtml($v_login_disabled === "yes" ? "true" : "false") ?>,
			useIpAllowList: <?= tohtml($v_login_use_iplist === "yes" ? "true" : "false") ?>,
			fileManager: <?= tohtml($v_file_manager === "yes" ? "true" : "false") ?>,
			dockerEnabled: <?= tohtml(!empty($v_docker_ip) ? "true" : "false") ?>,
			showAdvanced: false,
		}"
		x-on:advanced-toggled.window="showAdvanced = $event.detail"
		id="main-form"
		method="post"
		name="v_edit_user"
		class="<?= tohtml($v_status) ?>"
	>
		<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
		<input type="hidden" name="save" value="save">

		<div class="form-container">
			<h1 class="u-mb20"><?= tohtml(_("Edit User")) ?></h1>
			<?php show_alert_message($_SESSION); ?>
			<div class="u-mb10">
				<label for="v_user" class="form-label"><?= tohtml(_("Username")) ?></label>
				<input type="text" class="form-control" name="v_user" id="v_user" value="<?= tohtml(trim($v_username, "'")) ?>" disabled required>
				<input type="hidden" name="v_username" value="<?= tohtml(trim($v_username, "'")) ?>">
			</div>
			<div class="u-mb10">
				<label for="v_name" class="form-label"><?= tohtml(_("Contact Name")) ?></label>
				<input type="text" class="form-control" name="v_name" id="v_name" value="<?= tohtml(trim($v_name, "'")) ?>" <?php if (($_SESSION['userContext'] !== 'admin') && ($_SESSION['POLICY_USER_EDIT_DETAILS'] !== 'yes')) {
					echo 'disabled' ;
				}?> required>
				<?php if (($_SESSION['userContext'] !== 'admin') && ($_SESSION['POLICY_USER_EDIT_DETAILS'] !== 'yes')) { ?>
					<input type="hidden" name="v_name" value="<?= tohtml(trim($v_name, "'")) ?>">
				<?php } ?>
			</div>
			<div class="u-mb10">
				<label for="v_email" class="form-label"><?= tohtml(_("Email")) ?></label>
				<input type="email" class="form-control" name="v_email" id="v_email" value="<?= tohtml(trim($v_email, "'")) ?>" <?php if (($_SESSION['userContext'] !== 'admin') && ($_SESSION['POLICY_USER_EDIT_DETAILS'] !== 'yes')) {
					echo 'disabled' ;
				}?> required>
				<?php if (($_SESSION['userContext'] !== 'admin') && ($_SESSION['POLICY_USER_EDIT_DETAILS'] !== 'yes')) { ?>
					<input type="hidden" name="v_email" value="<?= tohtml(trim($v_email, "'")) ?>">
				<?php } ?>
			</div>
			<div class="u-mb10">
				<label for="v_password" class="form-label">
					<?= tohtml(_("Password")) ?>
					<button type="button" title="<?= tohtml(_("Generate")) ?>" class="u-unstyled-button u-ml5 js-generate-password">
						<i class="fas fa-arrows-rotate icon-green"></i>
					</button>
				</label>
				<div class="u-pos-relative u-mb10">
					<input type="text" class="form-control js-password-input" name="v_password" id="v_password" value="<?= tohtml(trim($v_password, "'")) ?>">
					<div class="password-meter">
						<meter max="4" class="password-meter-input js-password-meter"></meter>
					</div>
				</div>
			</div>
			<div id="password-details" class="u-mb20">
				<?php require $_SERVER["HESTIA"] . "/web/templates/includes/password-requirements.php"; ?>
				<?php if ($offer_admin_fields) { ?>
					<div class="form-check">
						<input x-model="loginDisabled" class="form-check-input" type="checkbox" name="v_login_disabled" id="v_login_disabled">
						<label for="v_login_disabled">
							<?= tohtml(_("Do not allow user to log in to Control Panel")) ?>
						</label>
					</div>
				<?php } ?>
				<div x-cloak x-show="!loginDisabled" id="password-options">
					<div class="form-check">
						<input class="form-check-input" type="checkbox" name="v_twofa" id="v_twofa" <?php if (!empty($v_twofa)) {
							echo 'checked';
						} ?>>
						<label for="v_twofa">
							<?= tohtml(_("Enable two-factor authentication")) ?>
						</label>
					</div>
					<?php if (!empty($v_twofa)) { ?>
						<p class="u-mb10"><?= tohtml(_("Account Recovery Code") . ": " . $v_twofa) ?></p>
						<p class="u-mb10"><?= tohtml(_("Please scan the code below in your 2FA application")) ?>:</p>
						<div class="u-mb10">
							<img class="qr-code" src="<?= tohtml($v_qrcode) ?>" alt="<?= tohtml(_("2FA QR Code")) ?>">
						</div>
					<?php } ?>
				</div>
				<div x-cloak x-show="!loginDisabled" id="password-options-ip">
					<div class="form-check">
						<input x-model="useIpAllowList" class="form-check-input" type="checkbox" name="v_login_use_iplist" id="v_login_use_iplist">
						<label for="v_login_use_iplist">
							<?= tohtml(_("Use IP address allow list for login attempts")) ?>
						</label>
					</div>
				</div>
				<div x-cloak x-show="useIpAllowList" id="ip-allowlist" class="u-mt10">
					<input type="text" class="form-control" name="v_login_allowed_ips" value="<?= tohtml(trim($v_login_allowed_ips, "'")) ?>" placeholder="<?= tohtml(_("For example")) ?>: 127.0.0.1,192.168.1.100">
				</div>
			</div>
			<div class="u-mb10">
				<label for="v_language" class="form-label"><?= tohtml(_("Language")) ?></label>
				<select class="form-select" name="v_language" id="v_language" required>
					<?php
						foreach ($languages as $key => $value) {
							echo "\n\t\t\t\t\t\t\t\t\t<option value=\"".$key."\"";
							$skey = "'".$key."'";
							if (($key == $v_language) || ($skey == $v_language)) {
								echo 'selected' ;
							}
							if (($key == detect_user_language()) && (empty($v_language))) {
								echo 'selected' ;
							}
							echo ">".htmlentities($value)."</option>\n";
						}
				?>
				</select>
			</div>
			<?php if ($offer_admin_fields) { ?>
				<div class="u-mb20">
					<label for="v_package" class="form-label"><?= tohtml(_("Package")) ?></label>
					<select class="form-select" name="v_package" id="v_package" required>
						<?php
							foreach ($packages as $key => $value) {
								echo "\n\t\t\t\t\t\t\t\t\t<option value=\"".htmlentities($key)."\"";
								$skey = "'".$key."'";
								if (($key == $v_package) || ($skey == $v_package)) {
									echo 'selected' ;
								}
								echo ">".htmlentities($key)."</option>\n";
							}
				?>
					</select>
				</div>
					<div class="u-mb10">
						<label for="v_shell" class="form-label"><?= tohtml(_("SSH Access")) ?></label>
						<select class="form-select" name="v_shell" id="v_shell">
							<?php
						// Preserve an existing off-allowlist shell (e.g. a legacy
						// dash/rssh) as the selected option so saving the form
						// unchanged does not silently reset it (#412). Only the
						// curated shells below are newly selectable.
						$cur_shell = trim($v_shell, "'");
				if ($cur_shell !== "" && !in_array($cur_shell, $shells, true)) {
					echo "\t\t\t\t<option value=\"".htmlentities($cur_shell)."\" selected>".htmlentities($cur_shell)." "._("(current)")."</option>\n";
				}
				foreach ($shells as $key => $value) {
					echo "\t\t\t\t<option value=\"".htmlentities($value)."\"";
					$svalue = "'".$value."'";
					if (($value == $v_shell) || ($svalue == $v_shell)) {
						echo 'selected' ;
					}
					echo ">".htmlentities($value)."</option>\n";
				}
				?>
						</select>
					</div>
			<?php } ?>
					<?php if ($offer_file_manager) { ?>
						<div class="u-mb10">
							<div class="form-check">
								<input x-model="fileManager" class="form-check-input" type="checkbox" name="v_file_manager" id="v_file_manager">
								<label for="v_file_manager">
									<?= tohtml(_("Enable File Manager")) ?>
								</label>
							</div>
						</div>
					<?php } ?>
					<?php # docker needs an unjailed login shell; an enabled customer keeps the switch either
						# way, so it can still be turned off after their shell changed
						if ($offer_docker) { ?>
						<div class="u-mb10">
							<div class="form-check">
								<input x-model="dockerEnabled" class="form-check-input" type="checkbox" name="v_docker" id="v_docker"
									data-docker-enabled="<?= tohtml(empty($v_docker_ip) ? "no" : "yes") ?>"
									data-docker-user="<?= tohtml($v_username) ?>"
									data-confirm-title="<?= tohtml(sprintf(_("Disable Docker for %s?"), $v_username)) ?>"
									data-confirm-message="<?= tohtml(_("This removes the companion account and deletes every container, image and volume of this customer. Turning Docker back on later creates an empty companion - nothing comes back. Their docker domains revert to normal vhosts.")) ?>"
									data-confirm-label="<?= tohtml(sprintf(_("Type %s to confirm."), $v_username)) ?>">
								<input type="hidden" name="v_docker_confirm" id="v_docker_confirm" value="">
								<label for="v_docker">
									<?= tohtml(_("Enable Docker")) ?>
									<?php if (!empty($v_docker_ip)) { ?>
										<span class="optional"><?= tohtml(preg_replace('/\.\d+$/', ".0/24", $v_docker_ip)) ?></span>
										<span class="optional"><?= tohtml(_("- turning this off removes the containers and their volumes")) ?></span>
									<?php } ?>
								</label>
							</div>
						</div>
					<?php } ?>
				<div x-cloak x-show="showAdvanced" x-collapse>
			<?php if ($offer_role): ?>
				<div class="u-mb10">
					<label for="v_role" class="form-label"><?= tohtml(_("Role")) ?></label>
					<select class="form-select" name="v_role" id="v_role" required>
						<option value="user"><?= tohtml(_("User")) ?></option>
						<option value="admin" <?= tohtml($v_role == "admin" ? "selected" : "") ?>><?= tohtml(_("Administrator")) ?></option>
					</select>
				</div>
			<?php endif; ?>
			<?php if ($offer_theme) { ?>
			<div class="u-mb10">
				<label for="v_user_theme" class="form-label"><?= tohtml(_("Theme")) ?></label>
				<select class="form-select" name="v_user_theme" id="v_user_theme">
					<?php
					// Mark by the value being rendered, never by a session key: gating the marker on
					// $_SESSION['userTheme'] leaves every option unmarked whenever that key is absent,
					// and an unmarked select submits its FIRST option - so the next save silently
					// replaced the theme this user had chosen.
					$selected_theme = !empty($v_user_theme) ? $v_user_theme : ($_SESSION['THEME'] ?? '');
				foreach ($themes as $key => $value) {
					echo "\t\t\t\t<option value=\"".$value."\"";
					if ($value === $selected_theme) {
						echo ' selected' ;
					}
					echo ">".$value."</option>\n";
				}
				?>
				</select>
			</div>
			<?php } ?>
				<div class="u-mb10">
					<label for="v_sort_order" class="form-label"><?= tohtml(_("Default List Sort Order")) ?></label>
					<select class="form-select" name="v_sort_order" id="v_sort_order">
						<option value='date' <?php if ($v_sort_order === 'date') {
							echo 'selected';
						} ?>><?= tohtml(_("Date")) ?></option>
						<option value='name' <?php if ($v_sort_order === 'name') {
							echo 'selected';
						} ?>><?= tohtml(_("Name")) ?></option>
					</select>
				</div>
					<?php // SSH access and the CLI version carried no gate of their own - they inherited
					// the admin wrapper they used to sit in. The fold had to leave that wrapper so the
					// sort order stays a customer setting, so both say it themselves now.?>
			<?php if ($offer_admin_fields) { ?>
					<div class="u-mb10">
						<label for="v_phpcli" class="form-label"><?= tohtml(_("PHP CLI Version")) ?></label>
						<select class="form-select" name="v_phpcli" id="v_phpcli">
							<?php
					foreach ($php_versions as $key => $value) {
						$php = explode('-', $value);
						echo "\t\t\t\t<option value=\"".$value."\"";
						$svalue = "'".$value."'";
						if ((!empty($v_phpcli)) && ($value == $v_phpcli) || ($svalue == $v_phpcli)) {
							echo ' selected' ;
						}
						if ((empty($v_phpcli)) && ($value == DEFAULT_PHP_VERSION)) {
							echo ' selected' ;
						}
						echo ">".htmlentities($value)."</option>\n";
					}
				?>
						</select>
					</div>

			<?php } ?>
				</div>
		</div>

			<?php // Same wrapper the toolbar uses, so this is the identical control, not a lookalike.
			// Indented by one toolbar button plus its gap so the right edge clears the floating
			// scroll/shortcut controls; 8px below is the toolbar's own button-to-edge gap.?>
			<div class="toolbar-buttons u-form-actions">
				<button type="submit" class="button" form="main-form">
					<i class="fas fa-floppy-disk icon-purple"></i><?= tohtml(_("Save")) ?>
				</button>
				<span class="button u-form-actions-spacer" aria-hidden="true">
					<i class="fas fa-floppy-disk icon-purple"></i><?= tohtml(_("Save")) ?>
				</span>
			</div>
	</form>

</div>
