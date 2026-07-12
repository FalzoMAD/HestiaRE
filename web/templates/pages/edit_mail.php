<?php
// Per-domain spam tuning (#318): preset values must match the controller's
// map (web/edit/mail/index.php). The select's initial state is derived from
// the stored mark threshold; unknown values render as "custom".
$spam_presets = ["tolerant" => "7.0", "normal" => "5.0", "strict" => "3.5"];
$v_spam_sensitivity = "custom";
if (($v_spam_score ?? "") === "") {
	$v_spam_sensitivity = "default";
} else {
	foreach ($spam_presets as $spam_preset_key => $spam_preset_value) {
		if ((float) $spam_preset_value === (float) $v_spam_score) {
			$v_spam_sensitivity = $spam_preset_key;
		}
	}
}
$spam_tuning_allowed =
	$_SESSION["userContext"] === "admin" ||
	($_SESSION["POLICY_SPAM_CUSTOMER_TUNING"] ?? "yes") !== "no";
?>
<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/mail/">
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

	<form
		x-data="{
			sslEnabled: <?= tohtml($v_ssl == "yes" ? "true" : "false") ?>,
			letsEncryptEnabled: <?= tohtml($v_letsencrypt == "yes" ? "true" : "false") ?>,
			hasSmtpRelay: <?= tohtml($v_smtp_relay == "true" ? "true" : "false") ?>,
			spamFilterEnabled: <?= tohtml($v_antispam == "yes" ? "true" : "false") ?>,
			spamSensitivity: '<?= tohtml($v_spam_sensitivity ?? "default") ?>'
		}"
		id="main-form"
		name="v_edit_mail"
		method="post"
		class="<?= tohtml($v_status) ?> js-enable-inputs-on-submit"
	>
		<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
		<input type="hidden" name="save" value="save">

		<div class="form-container">
			<h1 class="u-mb20"><?= tohtml( _("Edit Mail Domain")) ?></h1>
			<?php show_alert_message($_SESSION); ?>
			<div class="u-mb20">
				<label for="v_domain" class="form-label"><?= tohtml( _("Domain")) ?></label>
				<input type="text" class="form-control" name="v_domain" id="v_domain" value="<?= tohtml(trim($v_domain, "'")) ?>" disabled required>
				<input type="hidden" name="v_domain" value="<?= tohtml(trim($v_domain, "'")) ?>">
			</div>
			<?php if ($_SESSION["WEBMAIL_SYSTEM"]) { ?>
				<div class="u-mb10">
					<label for="v_webmail" class="form-label"><?= tohtml( _("Webmail Client")) ?></label>
					<select class="form-select" name="v_webmail" id="v_webmail" tabindex="6">
						<?php foreach ($webmail_clients as $client){
							echo "\t\t\t\t<option value=\"".htmlentities($client)."\"";
							if (( htmlentities(trim($v_webmail,"'")) == $client )) {
								echo ' selected' ;
							}
							echo ">".htmlentities(ucfirst($client))."</option>\n";
							}
						?>
						<option value="disabled" <?php if (htmlentities(trim($v_webmail,"'")) == 'disabled') { echo "selected"; }?>><?= tohtml( _("Disabled")) ?></option>
					</select>
				</div>
			<?php } ?>
			<div class="u-mb10">
				<label for="v_catchall" class="form-label"><?= tohtml( _("Catch-All Email")) ?></label>
				<input type="email" class="form-control" name="v_catchall" id="v_catchall" value="<?= tohtml(trim($v_catchall, "'")) ?>">
			</div>
			<div class="u-mb20">
				<label for="v_rate" class="form-label">
					<?= tohtml( _("Rate Limit")) ?> <span class="optional">(<?= tohtml( _("email / hour / account")) ?>)</span>
				</label>
				<input type="text" class="form-control" name="v_rate" id="v_rate" value="<?= tohtml(trim($v_rate, "'")) ?>" <?php if ($_SESSION['userContext'] != "admin"){ echo "disabled"; }?>>
			</div>
			<?php if (!empty($_SESSION["ANTISPAM_SYSTEM"])) { ?>
				<div class="form-check u-mb10">
					<input x-model="spamFilterEnabled" class="form-check-input" type="checkbox" name="v_antispam" id="v_antispam" <?php if ($v_antispam == 'yes') echo 'checked'; ?>>
					<label for="v_antispam">
						<?= tohtml( _("Spam Filter")) ?>
					</label>
				</div>
				<div class="form-check u-mb10">
					<input class="form-check-input" type="checkbox" name="v_reject" id="v_reject" <?php if ($v_reject == 'yes') echo 'checked'; ?>>
					<label for="v_reject">
						<?= tohtml( _("Reject Spam")) ?>
					</label>
				</div>
				<?php if ($spam_tuning_allowed) { ?>
					<div x-cloak x-show="spamFilterEnabled" class="u-pl30">
						<div class="u-mb10">
							<label for="v_spam_sensitivity" class="form-label"><?= tohtml( _("Spam Filter Sensitivity")) ?></label>
							<select x-model="spamSensitivity" class="form-select" name="v_spam_sensitivity" id="v_spam_sensitivity">
								<option value="default" <?php if ($v_spam_sensitivity === 'default') echo 'selected'; ?>><?= tohtml( _("Server default")) ?></option>
								<option value="tolerant" <?php if ($v_spam_sensitivity === 'tolerant') echo 'selected'; ?>><?= tohtml( _("Tolerant")) ?> (7.0)</option>
								<option value="normal" <?php if ($v_spam_sensitivity === 'normal') echo 'selected'; ?>><?= tohtml( _("Normal")) ?> (5.0)</option>
								<option value="strict" <?php if ($v_spam_sensitivity === 'strict') echo 'selected'; ?>><?= tohtml( _("Strict")) ?> (3.5)</option>
								<option value="custom" <?php if ($v_spam_sensitivity === 'custom') echo 'selected'; ?>><?= tohtml( _("Custom threshold")) ?></option>
							</select>
							<small class="hint"><?= tohtml( _("Mail scoring above the threshold is marked as spam — lower means stricter.")) ?></small>
						</div>
						<div x-cloak x-show="spamSensitivity === 'custom'" class="u-mb10">
							<label for="v_spam_score" class="form-label">
								<?= tohtml( _("Mark Threshold")) ?>
							</label>
							<input type="text" class="form-control" name="v_spam_score" id="v_spam_score" value="<?= tohtml($v_spam_score ?? "") ?>">
							<?php if ($_SESSION["userContext"] !== "admin") { ?>
								<small class="hint"><?= tohtml(sprintf( _("Allowed range: %s to %s."), $_SESSION["POLICY_SPAM_SCORE_MIN"] ?? "3.0", $_SESSION["POLICY_SPAM_SCORE_MAX"] ?? "10.0")) ?></small>
							<?php } ?>
						</div>
						<div class="u-mb10">
							<label for="v_spam_reject_score" class="form-label">
								<?= tohtml( _("Reject Threshold")) ?> <span class="optional">(<?= tohtml( _("Optional")) ?>)</span>
							</label>
							<input type="text" class="form-control" name="v_spam_reject_score" id="v_spam_reject_score" value="<?= tohtml($v_spam_reject_score ?? "") ?>">
							<small class="hint"><?= tohtml( _("Only applies while Reject Spam is enabled. Empty = server default.")) ?><?php if ($_SESSION["userContext"] !== "admin") { echo " " . tohtml(sprintf( _("Allowed range: %s to %s."), $_SESSION["POLICY_SPAM_REJECT_SCORE_MIN"] ?? "8.0", $_SESSION["POLICY_SPAM_REJECT_SCORE_MAX"] ?? "20.0")); } ?></small>
						</div>
						<div class="u-mb10">
							<label for="v_spam_subject_tag" class="form-label">
								<?= tohtml( _("Spam Subject Tag")) ?> <span class="optional">(<?= tohtml( _("Optional")) ?>)</span>
							</label>
							<input type="text" class="form-control" name="v_spam_subject_tag" id="v_spam_subject_tag" value="<?= tohtml($v_spam_subject_tag ?? "") ?>" placeholder="[SPAM]">
							<small class="hint"><?= tohtml( _("Prepended to the subject of mail classified as spam.")) ?></small>
						</div>
					</div>
				<?php } ?>
			<?php } ?>
			<?php if (!empty($_SESSION["ANTIVIRUS_SYSTEM"])) { ?>
				<div class="form-check u-mb10">
					<input class="form-check-input" type="checkbox" name="v_antivirus" id="v_antivirus" <?php if ($v_antivirus == 'yes') echo 'checked'; ?>>
					<label for="v_antivirus">
						<?= tohtml( _("Anti-Virus")) ?>
					</label>
				</div>
			<?php } ?>
			<div class="form-check u-mb10">
				<input class="form-check-input" type="checkbox" name="v_dkim" id="v_dkim" <?php if ($v_dkim == 'yes') echo 'checked'; ?>>
				<label for="v_dkim">
					<?= tohtml( _("DKIM Support")) ?>
				</label>
			</div>
			<div class="form-check u-mb10">
				<input x-model="sslEnabled" class="form-check-input" type="checkbox" name="v_ssl" id="v_ssl">
				<label for="v_ssl">
					<?= tohtml( _("Enable SSL for this domain")) ?>
				</label>
			</div>
			<div x-cloak x-show="sslEnabled" class="u-pl30">
				<div class="form-check u-mb10">
					<input x-model="letsEncryptEnabled" class="form-check-input" type="checkbox" name="v_letsencrypt" id="v_letsencrypt">
					<label for="v_letsencrypt">
						<?= tohtml( _("Use Let's Encrypt to obtain SSL certificate")) ?>
					</label>
				</div>
				<div class="alert alert-info u-mb20" role="alert">
					<i class="fas fa-exclamation"></i>
					<div>
						<p><?php echo $v_webmail_alias; ?></p>
						<p><?= tohtml(sprintf(_("To enable Let's Encrypt SSL, ensure that DNS records exist for mail.%s and %s!"), $v_domain, $v_webmail_alias)) ?></p>
					</div>
				</div>
				<div x-cloak x-show="!letsEncryptEnabled">
					<div class="u-mb10">
						<label for="v_ssl_crt" class="form-label">
							<?= tohtml( _("SSL Certificate")) ?>
							<span x-cloak x-show="!letsEncryptEnabled" id="generate-csr" > / <a class="form-link" target="_blank" href="/generate/ssl/?<?= tohtml(http_build_query(["domain" => $v_domain])) ?>"><?= tohtml( _("Generate Self-Signed SSL Certificate")) ?></a></span>
						</label>
						<textarea x-bind:disabled="letsEncryptEnabled" class="form-control u-min-height100 u-console" name="v_ssl_crt" id="v_ssl_crt"><?= tohtml(trim($v_ssl_crt, "'")) ?></textarea>
					</div>
					<div class="u-mb10">
						<label for="v_ssl_key" class="form-label"><?= tohtml( _("SSL Private Key")) ?></label>
						<textarea x-bind:disabled="letsEncryptEnabled" class="form-control u-min-height100 u-console" name="v_ssl_key" id="v_ssl_key"><?= tohtml(trim($v_ssl_key, "'")) ?></textarea>
					</div>
					<div class="u-mb20">
						<label for="v_ssl_ca" class="form-label">
							<?= tohtml( _("SSL Certificate Authority / Intermediate")) ?> <span class="optional">(<?= tohtml( _("Optional")) ?>)</span>
						</label>
						<textarea x-bind:disabled="letsEncryptEnabled" class="form-control u-min-height100 u-console" name="v_ssl_ca" id="v_ssl_ca"><?= tohtml(trim($v_ssl_ca, "'")) ?></textarea>
					</div>
				</div>
				<?php if ($v_ssl != "no") { ?>
					<ul class="values-list u-mb20">
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml( _("Issued To")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_subject) ?></span>
						</li>
						<?php if ($v_ssl_aliases) {
							$v_ssl_aliases = str_replace(",", ", ", $v_ssl_aliases); ?>
							<li class="values-list-item">
								<span class="values-list-label"><?= tohtml( _("Alternate")) ?></span>
								<span class="values-list-value"><?= tohtml($v_ssl_aliases) ?></span>
							</li>
						<?php } ?>
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml( _("Not Before")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_not_before) ?></span>
						</li>
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml( _("Not After")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_not_after) ?></span>
						</li>
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml( _("Signature")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_signature) ?></span>
						</li>
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml( _("Key Size")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_pub_key) ?></span>
						</li>
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml( _("Issued By")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_issuer) ?></span>
						</li>
					</ul>
				<?php } ?>
			</div>
			<div class="form-check u-mb10">
				<input x-model="hasSmtpRelay" class="form-check-input" type="checkbox" name="v_smtp_relay" id="v_smtp_relay">
				<label for="v_smtp_relay">
					<?= tohtml( _("SMTP Relay")) ?>
				</label>
			</div>
			<div x-cloak x-show="hasSmtpRelay" id="smtp_relay_table" class="u-pl30">
				<div class="u-mb10">
					<label for="v_smtp_relay_host" class="form-label"><?= tohtml( _("Host")) ?></label>
					<input type="text" class="form-control" name="v_smtp_relay_host" id="v_smtp_relay_host" value="<?= tohtml(trim($v_smtp_relay_host, "'")) ?>">
				</div>
				<div class="u-mb10">
					<label for="v_smtp_relay_port" class="form-label"><?= tohtml( _("Port")) ?></label>
					<input type="text" class="form-control" name="v_smtp_relay_port" id="v_smtp_relay_port" value="<?= tohtml(trim($v_smtp_relay_port, "'")) ?>">
				</div>
				<div class="u-mb10">
					<label for="v_smtp_relay_user" class="form-label"><?= tohtml( _("Username")) ?></label>
					<input type="text" class="form-control" name="v_smtp_relay_user" id="v_smtp_relay_user" value="<?= tohtml(trim($v_smtp_relay_user, "'")) ?>">
				</div>
				<div class="u-mb10">
					<label for="v_smtp_relay_pass" class="form-label"><?= tohtml( _("Password")) ?></label>
					<input type="text" class="form-control" name="v_smtp_relay_pass" id="v_smtp_relay_pass">
				</div>
				<div class="u-mb10">
					<label for="v_smtp_relay_exclude" class="form-label">
						<?= tohtml( _("Excluded Recipient Domains")) ?> <span class="optional">(<?= tohtml( _("Optional")) ?>)</span>
					</label>
					<textarea class="form-control u-min-height100" name="v_smtp_relay_exclude" id="v_smtp_relay_exclude" placeholder="*.example.com"><?= tohtml($v_smtp_relay_exclude ?? "") ?></textarea>
					<small class="hint"><?= tohtml( _("One recipient domain per line, wildcards like *.example.com allowed. Delivered directly instead of via the relay — requires valid SPF and DKIM for this server.")) ?></small>
				</div>
			</div>
		</div>

	</form>

</div>
