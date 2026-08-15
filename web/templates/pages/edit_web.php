<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/web/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml(_("Back")) ?>
			</a>
		</div>
		<div class="toolbar-buttons">
			<a href="/delete/web/cache/?<?= tohtml(http_build_query(["domain" => $v_domain, "token" => $_SESSION['token']])) ?>" class="button button-secondary js-clear-cache-button <?php if (!($v_nginx_cache == 'yes' || $v_proxy_cache == 'yes')) {
				echo "u-hidden";
			} ?>">
				<i class="fas fa-trash icon-red"></i><?= tohtml(_("Purge NGINX Cache")) ?>
			</a>
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
	<?php
		$web_x_data = [
			"statsEnabled" => !in_array(trim((string) $v_stats, "'"), ["", "none"], true),
			"statsAuthEnabled" => !empty($v_stats_user),
			"redirectEnabled" => !empty($v_redirect),
			"sslEnabled" => $v_ssl == "yes",
			"letsEncryptEnabled" => $v_letsencrypt == "yes" || $v_letsencrypt == "on",
			"showCertificates" => !($v_letsencrypt == "yes" || $v_letsencrypt == "on"),
			"certLabelOn" => _("Hide Certificate"),
			"certLabelOff" => _("Show Certificate"),
			"showAdvanced" => false,
			"nginxCacheEnabled" => $v_nginx_cache == "yes",
			"proxyCacheEnabled" => $v_proxy_cache == "yes",
			"proxySupportEnabled" => !empty($v_proxy),
			"customDocumentRootEnabled" => !empty($v_custom_doc_root),
			"dockerEnabled" => !empty($v_docker),
		];
				?>

	<form
		x-data="<?= tohtml(json_encode($web_x_data, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_THROW_ON_ERROR)) ?>"
		x-on:advanced-toggled.window="showAdvanced = $event.detail"
		id="main-form"
		name="v_edit_web"
		method="post"
		class="<?= tohtml($v_status) ?> js-enable-inputs-on-submit"
	>
		<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
		<input type="hidden" name="save" value="save">

		<div class="form-container">
			<?php // Gates here protect the CUSTOMER from themselves (a pool set to high, a broken
			// proxy template), so the REAL admin overrides them even while impersonating: adminContext
			// is the durable identity (#438), userContext keeps scoping the data. The frontend template
			// and the pool profile ride that gate; PHP version does not - that one is the customer's.?>
			<h1 class="u-mb20"><?= tohtml(_("Edit Web Domain")) ?></h1>
			<?php show_alert_message($_SESSION); ?>
			<div class="u-mb10">
				<label for="v_domain" class="form-label"><?= tohtml(_("Domain")) ?></label>
				<input type="text" class="form-control" name="v_domain" id="v_domain" value="<?= tohtml(trim($v_domain, "'")) ?>" disabled required>
				<input type="hidden" name="v_domain" value="<?= tohtml(trim($v_domain, "'")) ?>">
			</div>
			<div class="u-mb10">
				<label for="v_aliases" class="form-label"><?= tohtml(_("Aliases")) ?></label>
				<textarea class="form-control" name="v_aliases" id="v_aliases"><?= tohtml(trim($v_aliases, "'")) ?></textarea>
			</div>
			<?php if ($v_letsencrypt == "yes" || $v_letsencrypt == "on") { ?>
				<div class="alert alert-info u-mb10" role="alert">
					<i class="fas fa-exclamation"></i>
					<p><?= tohtml(_("If the aliases changes, Let's Encrypt will obtain a new SSL certificate.")) ?></p>
				</div>
			<?php } ?>
			<div class="u-mb20">
				<label for="v_ip" class="form-label"><?= tohtml(_("IP Address")) ?></label>
				<select class="form-select" name="v_ip" id="v_ip">
					<?php
									foreach ($ips as $ip => $value) {
										$display_ip = htmlentities(empty($value['NAT']) ? $ip : "{$value['NAT']}");
										$ip_selected = ((!empty($v_ip) && $ip == $v_ip) || $v_ip == "'{$ip}'") ? 'selected' : '';
										echo "\n\t\t\t\t\t\t\t\t\t\t\t\t<option value=\"{$ip}\" {$ip_selected}>{$display_ip}</option>\n";
									}
				?>
				</select>
			</div>
			<div class="form-check u-mb10">
				<input class="form-check-input" type="checkbox" name="v_offline_check" id="v_offline_check" <?php if ($v_offline == "yes") {
					echo "checked";
				} ?>>
				<label for="v_offline_check">
					<?= tohtml(_("Take website temporarily offline (visitors see a maintenance page, HTTP 503)")) ?>
				</label>
			</div>
				<?php if (empty($v_docker) && $can_edit_templates) { ?>
					<?php // These policy gates protect the CUSTOMER from themselves (a pool set to high, a broken
					// proxy template), so the REAL admin overrides them even while impersonating: adminContext
					// is the durable identity (#438), userContext keeps scoping the data. Policy default is
					// effectively 'no' - protective for customers, invisible to admins.?>
				<?php // Only selectable in the nginx-only model; on apache-web the vhost renders from
						// share/ and the list is empty, so hide it instead of an empty dropdown (#219/#591)?>
					<?php if ($offer_web_template) { ?>
						<div class="u-mb10">
							<label for="v_template" class="form-label">
								<?= tohtml(_("Web Template")) ?> <span class="optional"><?= tohtml(strtoupper($_SESSION["WEB_SYSTEM"])) ?></span>
							</label>
							<select class="form-select" name="v_template" id="v_template">
								<?php
									foreach ($templates as $key => $value) {
										echo "\t\t\t\t<option value=\"".htmlentities($value)."\"";
										$svalue = "'".$value."'";
										if ((!empty($v_template)) && ($value == $v_template) || ($svalue == $v_template)) {
											echo ' selected' ;
										}
										echo ">".htmlentities($value)."</option>\n";
									}
						?>
							</select>
						</div>
					<?php } ?>
				<?php } ?>
					<?php if ($offer_backend) { ?>
						<?php // profile choice is capacity allocation - a customer would simply pick 'high'?>
						<div class="u-mb10">
								<label for="v_php_version" class="form-label"><?= tohtml(_("PHP Version")) ?></label>
							<select class="form-select" name="v_php_version" id="v_php_version">
								<?php
								$v_cur_php = trim($v_php_version, "'");
						foreach (($php_versions ?: []) as $value) {
							echo "\t\t\t\t<option value=\"" . tohtml($value) . "\"";
							if ($v_cur_php == $value) {
								echo ' selected';
							}
							echo ">PHP " . tohtml($value) . "</option>\n";
						}
						echo "\t\t\t\t<option value=\"none\"" . ($v_cur_php == 'none' ? ' selected' : '') . ">" . tohtml(_("None (no PHP)")) . "</option>\n";
						?>
							</select>
						</div>
						<?php if ($offer_backend_template) { ?>
						<div class="u-mb10">
								<label for="v_backend_template" class="form-label">
									<?= tohtml(_("PHP Pool Size")) ?> <span class="optional"><?= tohtml(strtoupper($_SESSION["WEB_BACKEND"])) ?></span>
								</label>
							<select class="form-select" name="v_backend_template" id="v_backend_template">
								<?php
							foreach ($backend_templates as $key => $value) {
								echo "\t\t\t\t<option value=\"".tohtml($value)."\"";
								$svalue = "'".$value."'";
								if ((!empty($v_backend_template)) && (($value == $v_backend_template) || ($svalue == $v_backend_template))) {
									echo ' selected' ;
								}
								if ((empty($v_backend_template)) && ($value == 'default')) {
									echo ' selected' ;
								}
								echo ">".tohtml($value)."</option>\n";
							}
							?>
							</select>
						</div>
						<?php } ?>
					<?php } ?>
			<?php if ($offer_stats) { ?>
				<div class="form-check u-mb10">
					<input x-model="statsEnabled" class="form-check-input" type="checkbox" name="v_stats" id="v_stats" value="awstats">
					<label for="v_stats">
						<?= tohtml(_("Web Statistics")) ?>
					</label>
				</div>
			<?php } ?>
			<div x-cloak x-show="statsEnabled" class="u-mb10">
				<div class="form-check">
					<input x-model="statsAuthEnabled" class="form-check-input" type="checkbox" name="v_stats_auth" id="v_stats_auth">
					<label for="v_stats_auth">
						<?= tohtml(_("Statistics Authorization")) ?>
					</label>
				</div>
			</div>
			<div x-cloak x-show="statsEnabled" class="u-pl30">
				<div x-cloak x-show="statsAuthEnabled" name="h-add-web-domain-stats-user">
					<div class="u-mb10">
						<label for="v_stats_user" class="form-label"><?= tohtml(_("Username")) ?></label>
						<input type="text" class="form-control" name="v_stats_user" id="v_stats_user" value="<?= tohtml(trim($v_stats_user, "'")) ?>">
					</div>
					<div class="u-mb20">
						<label for="v_password" class="form-label">
							<?= tohtml(_("Password")) ?>
							<button type="button" title="<?= tohtml(_("Generate")) ?>" class="u-unstyled-button u-ml5 js-generate-password">
								<i class="fas fa-arrows-rotate icon-green"></i>
							</button>
						</label>
						<div class="u-pos-relative">
							<input type="text" class="form-control js-password-input" name="v_stats_password" id="v_password" value="<?= tohtml(trim($v_stats_password, "'")) ?>">
						</div>
					</div>
				</div>
			</div>
			<div class="form-check u-mb10">
				<input x-model="sslEnabled" class="form-check-input" type="checkbox" name="v_ssl" id="v_ssl">
				<label for="v_ssl">
					<?= tohtml(_("Enable SSL for this domain")) ?>
				</label>
			</div>
			<div x-cloak x-show="sslEnabled" class="u-pl30">
				<div class="form-check u-mb10">
					<input x-model="letsEncryptEnabled" class="form-check-input js-toggle-lets-encrypt" type="checkbox" name="v_letsencrypt" id="v_letsencrypt">
					<label for="v_letsencrypt">
						<?= tohtml(_("Use Let's Encrypt to obtain SSL certificate")) ?>
					</label>
				</div>
				<div class="form-check u-mb10">
					<input class="form-check-input" type="checkbox" name="v_ssl_forcessl" id="v_ssl_forcessl" <?php if ($v_ssl_forcessl == 'yes') {
						echo 'checked';
					} ?>>
					<label for="v_ssl_forcessl">
						<?= tohtml(_("Enable automatic HTTPS redirection")) ?>
					</label>
				</div>
				<div class="form-check u-mb20">
					<input class="form-check-input" type="checkbox" name="v_ssl_hsts" id="ssl_hsts" <?php if ($v_ssl_hsts == 'yes') {
						echo 'checked';
					} ?>>
					<label for="ssl_hsts">
						<?= tohtml(_("Enable HTTP Strict Transport Security (HSTS)")) ?>
						<a href="https://en.wikipedia.org/wiki/HTTP_Strict_Transport_Security" target="_blank">
							<i class="fas fa-question-circle"></i>
						</a>
					</label>
				</div>
				<?php if ($offer_http3) { ?>
				<div class="form-check u-mb20">
					<input class="form-check-input" type="checkbox" name="v_http3" id="v_http3" <?php if ($v_http3 == 'yes') {
						echo 'checked';
					} ?>>
					<label for="v_http3">
						<?= tohtml(_("Enable HTTP/3 (QUIC)")) ?>
					</label>
				</div>
				<?php } ?>
					<?php // Cert data is bulk and rarely touched: SSL stays above the fold, the PEM
					// blocks only appear in advanced mode (#621)?>
				<div x-cloak x-show="showCertificates && showAdvanced" class="js-ssl-details">
					<div class="u-mb10">
						<label for="ssl_crt" class="form-label">
							<?= tohtml(_("SSL Certificate")) ?>
							<span id="generate-csr"> / <a class="form-link" target="_blank" href="/generate/ssl/?<?= tohtml(http_build_query(["domain" => $v_domain])) ?>"><?= tohtml(_("Generate Self-Signed SSL Certificate")) ?></a></span>
						</label>
						<textarea class="form-control u-min-height100 u-console" name="v_ssl_crt" id="ssl_crt"><?= tohtml(trim($v_ssl_crt, "'")) ?></textarea>
					</div>
					<div class="u-mb10">
						<label for="v_ssl_key" class="form-label"><?= tohtml(_("SSL Private Key")) ?></label>
						<textarea class="form-control u-min-height100 u-console" name="v_ssl_key" id="v_ssl_key"><?= tohtml(trim($v_ssl_key, "'")) ?></textarea>
					</div>
					<div class="u-mb20">
						<label for="v_ssl_ca" class="form-label">
							<?= tohtml(_("SSL Certificate Authority / Intermediate")) ?> <span class="optional">(<?= tohtml(_("Optional")) ?>)</span>
						</label>
						<textarea class="form-control u-min-height100 u-console" name="v_ssl_ca" id="v_ssl_ca"><?= tohtml(trim($v_ssl_ca, "'")) ?></textarea>
					</div>
				</div>
				<?php if ($v_ssl != "no") { ?>
					<ul class="values-list">
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml(_("Issued To")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_subject) ?></span>
						</li>
						<?php if ($v_ssl_aliases) {
							$v_ssl_aliases = str_replace(",", ", ", $v_ssl_aliases); ?>
							<li class="values-list-item">
								<span class="values-list-label"><?= tohtml(_("Alternate")) ?></span>
								<span class="values-list-value"><?= tohtml($v_ssl_aliases) ?></span>
							</li>
						<?php } ?>
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml(_("Not Before")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_not_before) ?></span>
						</li>
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml(_("Not After")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_not_after) ?></span>
						</li>
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml(_("Signature")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_signature) ?></span>
						</li>
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml(_("Key Size")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_pub_key) ?></span>
						</li>
						<li class="values-list-item">
							<span class="values-list-label"><?= tohtml(_("Issued By")) ?></span>
							<span class="values-list-value"><?= tohtml($v_ssl_issuer) ?></span>
						</li>
						<p x-cloak x-show="letsEncryptEnabled && showAdvanced" id="letsinfo">
							<button
								type="button"
								class="form-link"
								x-on:click="showCertificates = !showCertificates"
									x-text="showCertificates ? certLabelOn : certLabelOff">
								<?= tohtml(_("Show Certificate")) ?>
							</button>
						</p>
					</ul>
				<?php } ?>
			</div>
			<div x-cloak x-show="showAdvanced" x-collapse>
			<div class="form-check u-mb10">
				<input x-model="redirectEnabled" class="form-check-input" type="checkbox" name="h-redirect-checkbox" id="h-redirect-checkbox">
				<label for="h-redirect-checkbox">
					<?= tohtml(_("Enable domain redirection")) ?>
				</label>
			</div>
			<div x-cloak x-show="redirectEnabled" id="v_redirect" class="u-pl30 u-mb10">
				<div class="form-check">
					<input class="form-check-input js-redirect-custom-value" type="radio" name="h-redirect" id="h-redirect-radio-1" value="<?= tohtml('www.'.$v_domain) ?>" <?php if ($v_redirect == "www.".$v_domain) {
						echo 'checked';
					} ?>>
					<label for="h-redirect-radio-1">
						<?= tohtml(sprintf(_("Redirect visitors to %s"), "www." . $v_domain)) ?>
					</label>
				</div>
				<div class="form-check">
					<input class="form-check-input js-redirect-custom-value" type="radio" name="h-redirect" id="h-redirect-radio-2" value="<?= tohtml($v_domain) ?>" <?php if ($v_redirect == $v_domain) {
						echo 'checked';
					} ?>>
					<label for="h-redirect-radio-2">
						<?= tohtml(sprintf(_("Redirect visitors to %s"), $v_domain)) ?>
					</label>
				</div>
				<div class="form-check">
					<input class="form-check-input js-redirect-custom-value" type="radio" name="h-redirect" id="h-redirect-radio-3" value="custom" <?php if (!empty($v_redirect_custom)) {
						echo 'checked';
					} ?>>
					<label for="h-redirect-radio-3">
						<?= tohtml(_("Redirect visitors to a custom domain or web address")) ?>
					</label>
				</div>
				<div class="u-pl30 js-custom-redirect-fields <?php if (empty($v_redirect_custom)) {
					echo 'u-hidden';
				} ?>">
					<div class="u-mt15 u-mb10">
						<label for="h-redirect-custom" class="form-label"><?= tohtml(_("Target domain or URL")) ?></label>
						<input type="text" class="form-control" name="h-redirect-custom" id="h-redirect-custom" value="<?= tohtml($v_redirect_custom) ?>">
					</div>
					<div class="u-mb20">
						<label for="h-redirect-code" class="form-label"><?= tohtml(_("Status code")) ?>:</label>
						<select class="form-select" name="h-redirect-code" id="h-redirect-code">
							<?php foreach ($redirect_code_options as $status_code): ?>
								<option value="<?= tohtml($status_code) ?>" <?php if ((int) $v_redirect_code === (int) $status_code) {
									echo 'selected="selected"';
								} ?>>
								<?= tohtml($status_code) ?>
							</option>
							<?php endforeach; ?>
						</select>
					</div>
				</div>
			</div>
				<div class="form-check u-mb10">
					<input x-model="customDocumentRootEnabled" class="form-check-input" type="checkbox" name="v_custom_doc_root_check" id="v_custom_doc_root_check">
					<label for="v_custom_doc_root_check">
						<?= tohtml(_("Custom document root")) ?>
					</label>
				</div>
				<div x-cloak x-show="customDocumentRootEnabled" id="v_custom_doc_root" class="u-pl30">
					<div class="u-mb10">
						<label for="h-custom-doc-domain" class="form-label"><?= tohtml(_("Point to")) ?></label>
						<input type="hidden" class="js-custom-docroot-prepath" name="h-custom-doc-root_prepath" value="<?= tohtml($v_custom_doc_root_prepath) ?>">
						<select class="form-select js-custom-docroot-domain" name="h-custom-doc-domain" id="h-custom-doc-domain">
							<?php foreach ($user_domains as $domain): ?>
							<option value="<?= tohtml($domain) ?>"
								<?php if ($v_custom_doc_domain === $domain || (empty($v_custom_doc_domain) && $domain === $v_domain)) {
									echo 'selected="selected"';
								} ?>>
								<?= tohtml($domain) ?>
							</option>
							<?php endforeach; ?>
						</select>
					</div>
					<div class="u-mb10">
						<label for="h-custom-doc-folder" class="form-label">
							<?= tohtml(_("Directory")) ?> <span class="optional">(<?= tohtml(_("Optional")) ?>)</span>
						</label>
						<input type="text" class="form-control js-custom-docroot-dir" name="h-custom-doc-folder" id="h-custom-doc-folder" value="<?= tohtml(trim($v_custom_doc_folder, "'")) ?>">
						<small class="js-custom-docroot-hint"></small>
					</div>
				</div>
			<?php if ($offer_botlimit) { ?>
				<!-- Layer-B bot throttling, customer-editable: only the families the admin ENABLED are
				     offered, since the server config defines rate zones for those alone. Humans are
				     never limited here. The family table itself stays admin-only. -->
				<details class="box-collapse u-mt15 u-mb10">
					<summary class="box-collapse-header">
						<i class="fas fa-robot u-mr10"></i><?= tohtml(_("Bot Rate Limiting")) ?>
						<span class="optional u-ml5">
							<?php $bl_on = count($v_botlimit); ?>
							<?= $bl_on ? tohtml(sprintf(_("%d active"), $bl_on)) : tohtml(_("off")) ?>
						</span>
					</summary>
					<div class="box-collapse-content">
						<p class="hint u-mb10">
							<?= tohtml(_("Throttle crawlers by family (HTTP 429). Humans are never limited, and malicious traffic is CrowdSec's job. Rates come from the server-wide family table.")) ?>
							<?php if ($_SESSION["userContext"] === "admin") { ?>
								<a href="/edit/server/" class="u-ml5"><?= tohtml(_("Configure")) ?></a>
							<?php } ?>
						</p>
						<?php foreach ($botfamilies as $bl_fam => $bl_data) {
							$bl_cur = $v_botlimit[$bl_fam] ?? "off"; ?>
							<div class="u-mb10">
								<label for="v_botlimit_<?= tohtml($bl_fam) ?>" class="form-label">
									<?= tohtml($bl_fam) ?>
									<span class="optional">
										(<?= tohtml($bl_data["LENIENT"]) ?> / <?= tohtml($bl_data["STRICT"]) ?>)
									</span>
								</label>
								<select class="form-select" name="v_botlimit[<?= tohtml($bl_fam) ?>]" id="v_botlimit_<?= tohtml($bl_fam) ?>">
									<option value="off" <?php if ($bl_cur == "off") {
										echo "selected";
									} ?>><?= tohtml(_("Off")) ?></option>
									<option value="lenient" <?php if ($bl_cur == "lenient") {
										echo "selected";
									} ?>><?= tohtml(_("Lenient")) ?></option>
									<option value="strict" <?php if ($bl_cur == "strict") {
										echo "selected";
									} ?>><?= tohtml(_("Strict")) ?></option>
								</select>
							</div>
						<?php } ?>
					</div>
				</details>
			<?php } ?>
			<?php if ($offer_docker) { ?>
			<div class="form-check u-mb10">
				<input x-model="dockerEnabled" class="form-check-input" type="checkbox" name="v_docker" id="v_docker" <?php if (!empty($v_docker)) {
					echo 'checked';
				} ?>>
				<label for="v_docker">
					<?= tohtml(_("Docker Proxy")) ?>
				</label>
			</div>
			<div x-cloak x-show="dockerEnabled" class="u-pl30 u-mb20">
				<label for="v_docker_port" class="form-label">
					<?= tohtml(_("Container address and port")) ?>
				</label>
				<div class="u-flex u-align-center">
					<span class="u-mr5"><?= tohtml($v_docker_net) ?>.</span>
					<input type="number" min="1" max="254" step="1" class="form-control" name="v_docker_octet" id="v_docker_octet" size="3" maxlength="3" style="width: 6em;" value="<?= tohtml($v_docker_octet) ?>">
					<span class="u-ml5 u-mr5">:</span>
					<input type="number" min="1024" max="65535" step="1" class="form-control" name="v_docker_port" id="v_docker_port" size="5" maxlength="5" style="width: 8em;" value="<?= tohtml($v_docker_port) ?>">
				</div>
				<?php # app shapes differ in proxy mode, headers, websockets - the list is admin-curated,
					# so the customer picks it; one entry is no choice
					if ($offer_docker_template) { ?>
				<div class="u-mt10">
					<label for="v_docker_template" class="form-label"><?= tohtml(_("Docker Template")) ?></label>
					<select class="form-select" name="v_docker_template" id="v_docker_template">
						<?php
							$v_cur_docker_tpl = $v_docker ?: "default";
						foreach ($docker_templates as $value) {
							echo "\t\t\t\t<option value=\"" . tohtml($value) . "\"";
							if ($v_cur_docker_tpl == $value) {
								echo ' selected';
							}
							echo ">" . tohtml($value) . "</option>\n";
						}
						?>
					</select>
				</div>
				<?php } ?>
			</div>
			<?php } ?>
			<?php if ($offer_proxy_cache) { ?>
				<div class="form-check u-mb10">
					<input x-model="proxyCacheEnabled" class="form-check-input" type="checkbox" name="v_proxy_cache_check" id="v_proxy_cache_check" <?php if ($v_proxy_cache_check == "on") {
						echo "checked";
					} ?>>
					<label for="v_proxy_cache_check">
						<?= tohtml(_("Enable proxy cache")) ?>
					</label>
				</div>
				<div x-cloak x-show="proxyCacheEnabled" id="v_proxy_duration" class="u-pl30">
					<div class="u-mb10">
						<label for="v_proxy_cache_duration" class="form-label">
							<?= tohtml(_("Cache Duration")) ?> <span class="optional">(<?= tohtml(_("For example")) ?>: 30s, 10m or 1d)</span>
						</label>
						<input type="text" class="form-control" name="v_proxy_cache_duration" id="v_proxy_cache_duration" value="<?= tohtml(trim($v_proxy_cache_duration, "'")) ?>">
					</div>
				</div>
			<?php } ?>
				<?php if ($offer_fastcgi_cache) { ?>
						<div class="form-check u-mb10">
							<input x-model="nginxCacheEnabled" class="form-check-input" type="checkbox" name="v_nginx_cache_check" id="v_nginx_cache_check">
							<label for="v_nginx_cache_check">
								<?= tohtml(_("Enable FastCGI cache")) ?>
								<a href="https://hestiacp.com/docs/server-administration/web-templates.html#nginx-fastcgi-cache" target="_blank" class="u-ml5">
									<i class="fas fa-circle-question"></i>
								</a>
							</label>
						</div>
						<div x-cloak x-show="nginxCacheEnabled" id="v_nginx_duration" class="u-pl30">
							<div class="u-mb10">
								<label for="v_nginx_cache_duration" class="form-label">
									<?= tohtml(_("Cache Duration")) ?> <span class="optional">(<?= tohtml(_("For example")) ?>: 30s, 10m or 1d)</span>
								</label>
								<input type="text" class="form-control" name="v_nginx_cache_duration" id="v_nginx_cache_duration" value="<?= tohtml(trim($v_nginx_cache_duration, "'")) ?>">
							</div>
						</div>
					<?php } ?>
					<?php if ($offer_proxy) { ?>
						<div style="display: none;">
							<div class="form-check u-mb10">
								<input x-model="proxySupportEnabled" class="form-check-input" type="checkbox" name="v_proxy" id="v_proxy">
									<label for="v_proxy">
										<?= tohtml(_("Proxy Support")) ?> <span class="optional"><?= tohtml(strtoupper($_SESSION["PROXY_SYSTEM"])) ?></span>
									</label>
							</div>
						</div>
						<div x-cloak x-show="proxySupportEnabled" id="proxytable">
							<?php # nothing to choose is not a choice: the both model ships one proxy template, the
						# variety lives in the web templates of an nginx-only box
						if ($offer_proxy_template) { ?>
							<div class="u-mb10">
								<label for="v_proxy_template" class="form-label"><?= tohtml(_("Proxy Template")) ?></label>
								<select class="form-select js-proxy-template-select" name="v_proxy_template" id="v_proxy_template">
									<?php
								foreach ($proxy_templates as $key => $value) {
									echo "\t\t\t\t<option value=\"".tohtml($value)."\"";
									$svalue = "'".$value."'";
									if ((!empty($v_proxy_template)) && (($value == $v_proxy_template) || ($svalue == $v_proxy_template))) {
										echo ' selected' ;
									}
									if ((empty($v_proxy_template)) && ($value == 'default')) {
										echo ' selected' ;
									}
									echo ">".tohtml($value)."</option>\n";
								}
							?>
								</select>
							</div>
							<?php } ?>
							<div class="u-mb10">
								<label for="v_proxy_ext" class="form-label"><?= tohtml(_("Proxy Extensions")) ?></label>
								<textarea class="form-control u-min-height100" name="v_proxy_ext" id="v_proxy_ext"><?php if (!empty($v_proxy_ext)) {
									echo tohtml(trim($v_proxy_ext, "'"));
								} else {
									echo 'jpg, jpeg, gif, png, ico, svg, css, zip, tgz, gz, rar, bz2, exe, pdf, doc, xls, ppt, txt, odt, ods, odp, odf, tar, bmp, rtf, js, mp3, avi, mpeg, flv, html, htm';
								} ?></textarea>
							</div>
						</div>
					<?php } ?>
				<?php if ($offer_ftp) { ?>
					<div class="form-check u-mb10">
						<input class="form-check-input js-toggle-ftp-accounts" type="checkbox" name="v_ftp" id="v_ftp" <?php if (!empty($v_ftp_user)) {
							echo 'checked';
						} ?>>
						<label for="v_ftp">
							<?= tohtml(_("Additional FTP account(s)")) ?>
						</label>
					</div>
					<div class="js-active-ftp-accounts">
						<?php foreach ($v_ftp_users as $i => $ftp_user): ?>
						<?php
							$v_ftp_user     = $ftp_user['v_ftp_user'];
							$v_ftp_password = $ftp_user['v_ftp_password'];
							$v_ftp_path     = $ftp_user['v_ftp_path'];
							$v_ftp_email    = $ftp_user['v_ftp_email'];
							$v_ftp_pre_path = $ftp_user['v_ftp_pre_path'];
							?>
						<div class="js-ftp-account js-ftp-account-nrm" name="v_add_domain_ftp" style="<?php if (empty($v_ftp_user)) {
							echo 'display: none;';
						} ?>">
							<div class="u-mb10">
								<?= tohtml(_("FTP")) ?> #<span class="js-ftp-user-number"><?= tohtml($i + 1) ?></span>
								<button type="button" class="form-link form-link-danger u-ml5 js-delete-ftp-account"><?= tohtml(_("Delete")) ?></button>
								<input type="hidden" class="js-ftp-user-deleted" name="v_ftp_user[<?= tohtml($i) ?>][delete]" value="0">
								<input type="hidden" class="js-ftp-user-is-new" name="v_ftp_user[<?= tohtml($i) ?>][is_new]" value="<?= tohtml($ftp_user['is_new']) ?>">
							</div>
							<div class="u-pl30 u-mb10">
								<label for="v_ftp_user[<?= tohtml($i) ?>][v_ftp_user]" class="form-label">
									<?= tohtml(_("Username")) ?><br>
									<span style="color:#777;"><?= tohtml(sprintf(_('Prefix %s will be added to username automatically'), $user_plain."_")) ?></span>
								</label>
								<input type="text" class="form-control js-ftp-user"<?= $ftp_user['is_new'] != 1 ? ' disabled="disabled"' : '' ?>
								name="v_ftp_user[<?= tohtml($i) ?>][v_ftp_user]" id="v_ftp_user[<?= tohtml($i) ?>][v_ftp_user]" value="<?= tohtml(trim($v_ftp_user, "'")) ?>">
								<small class="hint js-ftp-user-hint"></small>
							</div>
							<div class="u-pl30 u-mb10">
								<label for="v_ftp_user[<?= tohtml($i) ?>][v_ftp_password]" class="form-label">
									<?= tohtml(_("Password")) ?>
									<button type="button" title="<?= tohtml(_("Generate")) ?>" class="u-unstyled-button u-ml5 js-ftp-password-generate">
										<i class="fas fa-arrows-rotate icon-green"></i>
									</button>
								</label>
								<input type="text" class="form-control js-ftp-user-psw" name="v_ftp_user[<?= tohtml($i) ?>][v_ftp_password]" id="v_ftp_user[<?= tohtml($i) ?>][v_ftp_password]" value="<?= tohtml(trim($v_ftp_password, "'")) ?>">
							</div>
							<div class="u-pl30 u-mb10">
								<label for="v_ftp_user[<?= tohtml($i) ?>][v_ftp_path]" class="form-label"><?= tohtml(_("Path")) ?></label>
								<input type="hidden" name="v_ftp_pre_path" value="<?= tohtml(!empty($v_ftp_pre_path) ? trim($v_ftp_pre_path, "'") : '/') ?>">
								<input type="hidden" name="v_ftp_user[<?= tohtml($i) ?>][v_ftp_path_prev]" value="<?php if (!empty($v_ftp_path)) {
									echo tohtml(($v_ftp_path[0] != '/' ? '/' : '') . trim($v_ftp_path, "'"));
								} ?>">
								<input type="text" class="form-control js-ftp-path" name="v_ftp_user[<?= tohtml($i) ?>][v_ftp_path]" id="v_ftp_user[<?= tohtml($i) ?>][v_ftp_path]" value="<?php if (!empty($v_ftp_path)) {
									echo tohtml(($v_ftp_path[0] != '/' ? '/' : '') . trim($v_ftp_path, "'"));
								} ?>">
								<span class="hint-prefix"><?= tohtml(trim($v_ftp_pre_path, "'")) ?></span><span class="hint js-ftp-path-hint"></span>
							</div>
							<?php if ($ftp_user['is_new'] == 1): ?>
								<div class="u-pl30 u-mb10">
									<label for="v_ftp_user[<?= tohtml($i) ?>][v_ftp_email]" class="form-label"><?= tohtml(_("Send FTP credentials to email")) ?></label>
									<input type="email" class="form-control js-email-alert-on-psw" name="v_ftp_user[<?= tohtml($i) ?>][v_ftp_email]" id="v_ftp_user[<?= tohtml($i) ?>][v_ftp_email]" value="<?= tohtml(trim($v_ftp_email, "'")) ?>">
								</div>
							<?php endif; ?>
						</div>
						<?php endforeach; ?>
					</div>

					<button type="button" class="form-link u-mt20 js-add-ftp-account" style="<?php if (empty($v_ftp_user)) {
						echo 'display: none;';
					} ?>">
						<?= tohtml(_("Add FTP account")) ?>
					</button>
				<?php } ?>
			</div>
		</div>

			<div class="u-mt10 u-text-right">
				<button type="submit" class="button" form="main-form">
					<i class="fas fa-floppy-disk icon-purple"></i><?= tohtml(_("Save")) ?>
				</button>
			</div>
	</form>

</div>

<div class="u-hidden js-ftp-account-template">
	<div class="js-ftp-account js-ftp-account-nrm" name="v_add_domain_ftp">
		<div class="u-mb10">
			<?= tohtml(_("FTP")) ?> #<span class="js-ftp-user-number"></span>
			<button type="button" class="form-link form-link-danger u-ml5 js-delete-ftp-account"><?= tohtml(_("Delete")) ?></button>
			<input type="hidden" class="js-ftp-user-deleted" name="v_ftp_user[%INDEX%][delete]" value="0">
			<input type="hidden" class="js-ftp-user-is-new" name="v_ftp_user[%INDEX%][is_new]" value="1">
		</div>
		<div class="u-pl30 u-mb10">
			<label for="v_ftp_user[%INDEX%][v_ftp_user]" class="form-label">
				<?= tohtml(_("Username")) ?><br>
				<span style="color:#777;"><?= tohtml(sprintf(_("Prefix %s will be added to username automatically"), $user_plain . "_")) ?></span>
			</label>
			<input type="text" class="form-control js-ftp-user" name="v_ftp_user[%INDEX%][v_ftp_user]" id="v_ftp_user[%INDEX%][v_ftp_user]" value="">
			<small class="hint js-ftp-user-hint"></small>
		</div>
		<div class="u-pl30 u-mb10">
			<label for="v_ftp_user[%INDEX%][v_ftp_password]" class="form-label">
				<?= tohtml(_("Password")) ?>
				<button type="button" title="<?= tohtml(_("Generate")) ?>" class="u-unstyled-button u-ml5 js-ftp-password-generate">
					<i class="fas fa-arrows-rotate icon-green"></i>
				</button>
			</label>
			<input type="text" class="form-control js-ftp-user-psw" name="v_ftp_user[%INDEX%][v_ftp_password]" id="v_ftp_user[%INDEX%][v_ftp_password]">
		</div>
		<div class="u-pl30 u-mb10">
			<label for="v_ftp_user[%INDEX%][v_ftp_path]" class="form-label"><?= tohtml(_("Path")) ?></label>
			<input type="hidden" name="v_ftp_pre_path" value="">
			<input type="text" class="form-control js-ftp-path" name="v_ftp_user[%INDEX%][v_ftp_path]" id="v_ftp_user[%INDEX%][v_ftp_path]" value="">
			<span class="hint-prefix"><?= tohtml(trim($v_ftp_pre_path_new_user, "'")) ?></span><span class="hint js-ftp-path-hint"></span>
		</div>
		<div class="u-pl30 u-mb10">
			<label for="v_ftp_user[%INDEX%][v_ftp_email]" class="form-label"><?= tohtml(_("Send FTP credentials to email")) ?></label>
			<input type="email" class="form-control js-email-alert-on-psw" name="v_ftp_user[%INDEX%][v_ftp_email]" id="v_ftp_user[%INDEX%][v_ftp_email]" value="">
		</div>
	</div>
</div>
