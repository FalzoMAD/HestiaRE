# Changelog

All notable HestiaRE changes are documented here, starting from the fork
point — a HestiaCP 1.9.6 snapshot, kept read-only in the `upstream/hestiacp`
branch (upstream's own history was dropped from this file with #307).

Maintenance rule: every larger change adds an entry to the Unreleased
section as part of its PR. On release, the section gets the version number.

## Unreleased

### Breaking / Upgrade notes

- The system removal commands are unified under a single verb: `h-remove-sys-*` →
  `h-delete-sys-*` (#123). Affected: `adminer, mariadb, postgresql, redis,
  roundcube, rspamd, sieve, snappymail`. HestiaCP uses `v-delete-*` universally,
  so this restores cherry-pick parity and matches every object command
  (`h-delete-web-domain`, …); it reverses the interim `h-remove-sys-*` naming
  introduced for redis in #121. No code path invoked the old names, and the
  install-time dangling-symlink prune (below) clears the now-broken
  `v-remove-sys-*` aliases on existing installs — but any personal scripts calling
  `h-remove-sys-*`/`v-remove-sys-*` must be updated.
- ProFTPD installs now set `FTP_SYSTEM=proftpd` (it was never recorded before,
  #123). New installs get it automatically; **pre-existing installs keep
  `FTP_SYSTEM` empty** (no migration before v1) — until re-run through
  `h-add-sys-proftpd`, the FTP machinery (`h-restart-ftp`, RRD FTP graph, smoke
  FTP check, NAT MasqueradeAddress) stays inert on them, as it already was.

### Added

- SSH `AllowUsers` allowlist co-maintenance (#412). HestiaRE now keeps the hestia
  panel accounts in sync on an `AllowUsers` line in `/etc/ssh/sshd_config` — a
  defense-in-depth SSH login allowlist. The installer seeds a **commented** (inert)
  `#AllowUsers` line with guidance unless one already exists; `h-add-user` adds the
  new account, `h-delete-user` removes it, and `rebuild_user` (`func/rebuild.sh`)
  re-adds it — so restore/rebuild, which bypass `h-add-user`, can't leave a restored
  user off an active line and silently locked out (shared helper
  `manage_sshd_allowusers` in `func/main.sh`). It edits **only** the token matching the account, so operator
  entries (`root@10.0.0.5`, maintenance, emergency accounts) and the commented-vs-
  active state of the line are preserved; the change is validated with `sshd -t`
  (left unchanged on rejection) and sshd is reloaded only when the line is active. A
  delete that would leave an *active* line empty re-comments it instead of locking
  everyone out (including root). Membership tracks account existence (no suspend
  hook). Domain-FTP sub-accounts are out of scope here (they follow in the SFTP
  transport rebuild). Nothing changes until the operator removes the leading `#`.
- `h-add-sys-clamav` / `h-delete-sys-clamav` — ClamAV mail antivirus is now a
  modular addon (#123). It was missing from the manifest and installer entirely,
  even though the exim antivirus machinery (`.ifdef CLAMD` block: `av_scanner`,
  per-domain antivirus ACL, `deny malware = */defer_ok`) already shipped inert.
  Anchored in `share/manifest.json` as `ADDON_CLAMAV` (mail-block only, **never
  preselected** — clamd holds the whole signature DB, ~1-2 GB RAM); the orphaned
  `install/deb/clamav/clamd.conf` moved to `share/clamav/` and hardened
  (`LocalSocketMode 666`→`660`, `LogVerbose` off). `h-add-sys-clamav` installs the
  daemon + freshclam, deploys the config, wires **bidirectional group access**
  (`Debian-exim`→`clamav` to write the clamd socket, **and `clamav`→`Debian-exim`
  to read the exim spool it scans** — the latter is load-bearing: without it clamd
  hits "Permission denied" on the spool and the fail-open scanner passes mail
  unscanned), waits for the virus DB (via the freshclam service — no manual
  `freshclam` that would collide with its lock), and **arms the exim `CLAMD` macro
  + `ANTIVIRUS_SYSTEM=clamav` only once clamd answers on the socket** (`clamdscan
  --ping`). If the DB is still downloading it leaves the macro OFF with a WARN to
  re-run — because `defer_ok` is **fail-open** (a dead clamd accepts mail
  *unscanned*, not deferred), so an armed-but-blind macro would silently pass
  mail. Two hardening details found in live testing: the socket mode is enforced
  by a systemd drop-in (`share/clamav/socket-hardening.conf`, `SocketMode=0660`)
  because clamd is socket-activated so the `.socket` unit — not `clamd.conf`'s
  `LocalSocketMode` — owns the live socket; and a local AppArmor override
  (`share/clamav/apparmor-local`) guarantees the spool read even under a stricter
  base profile than the stock one (which already allows it). Delete is saved-state
  (per-domain flags preserved, restored on reinstall; the DB is moved aside across
  the purge and restored, since `apt purge clamav-freshclam` wipes `/var/lib/clamav`
  — kept unless `PURGE_DATA=yes`). Verified live on all four distros: EICAR over
  SMTP rejected from an untrusted host, clean mail delivered, socket `660 clamav`,
  fail-open window, delete-disarm + reinstall-restore, and correct behaviour with
  AppArmor absent entirely.
- `h-add-sys-proftpd` / `h-delete-sys-proftpd` — ProFTPD is now a fully modular,
  individually-removable addon (#123). The curated config moved
  `install/deb/proftpd/` → `share/proftpd/` (it was orphaned — never deployed, so
  the distro default was live) and gained `Include modules.conf` (DSO loading)
  and `Include conf.d/` (NAT MasqueradeAddress). The add command deploys the
  config, records `FTP_SYSTEM=proftpd`, and opens the FTP firewall rule with the
  passive range read from `PassivePorts` in the deployed config (single source);
  the delete command purges and reverts all of it. `install_addons` delegates to
  the add command instead of an inline `apt install`. Cross-distro handling
  (verified on Debian 12/13 + Ubuntu 24/26): a uniform package set
  (`proftpd-core proftpd-mod-vroot proftpd-mod-crypto` — `proftpd-basic` is
  bookworm-only and modern proftpd split TLS into `proftpd-mod-crypto`), an
  explicit `mod_tls` presence gate (its absence silently disables FTPS — the TLS
  block is `<IfModule mod_tls.c>`-guarded), and an AppArmor local override
  (`share/proftpd/apparmor-local`) so Ubuntu 26's enforced proftpd profile can
  read the panel cert.

### Changed

- SSH-access shells are now a curated allowlist (#412). `is_format_valid_shell`
  (`func/main.sh`) and `h-list-sys-shells` (the panel's single shell source, used by
  the user and package editors) share one list — `HESTIA_SHELL_ALLOWLIST` = `nologin`
  (SFTP-only, default) · `jailbash` (bwrap sandbox) · `bash` (unconfined) · `sh` (POSIX
  `/bin/sh`), intersected with `/etc/shells` (so a shell absent on the node, e.g.
  `jailbash` without the SSH jail, isn't offered) with `nologin` guaranteed. The
  upstream `dash`/`rbash`/`rssh`/`screen`/`tmux` options are dropped (`rssh` no longer
  exists on Debian and silently degrades to `nologin`; `screen`/`tmux` are meaningless
  as a login shell). Also fixes
  an unquoted, word-based `grep -w $1 /etc/shells` in the old validator that let a bare
  `bash` validate against the `/bin/bash` line. The validator is genuinely hard (not a
  UI-only filter): `h-change-user-shell` gates every real change through it, but allows
  re-asserting the user's *current* shell (in-allowlist **or** identical to the shell
  already set) so a legacy off-allowlist shell a restore left in place can be re-set
  without a new off-allowlist shell slipping in. Existing users/packages keep any
  off-allowlist shell: `rebuild.sh` restores it straight from `/etc/shells`, and the
  user/package editors now render it as the selected "(current)" option so saving the
  form unchanged never silently resets it — only the curated shells are newly assignable.
- Moved the webmail vhost templates from `templates/mail/` into service-scoped
  `share/nginx/webmail/` and `share/apache2/webmail/` (#119) — they are system
  webmail-delivery assets (docroot-free proxies to the Panel-Caddy listeners,
  #205), not a user-pickable template library like `templates/web/`. The
  `nginx/apache2` split is structural (`add_webmail_config` keys on
  `$WEB_SYSTEM`), so `MAILTPL` is retired and the resolver is now
  `$HESTIA/share/$WEB_SYSTEM/webmail/$tpl`. Also removed the dead RainLoop
  templates + refs (superseded by SnappyMail; never installed by HestiaRE):
  `share/apache2/webmail/rainloop.{tpl,stpl}`, the rainloop branch in
  `h-add-mail-domain-ssl`, and the guarded `/etc/rainloop/` block in
  `h-change-sys-hostname`.
- Dissolved `install/deb/ssl/` and `install/deb/logrotate/` into service-scoped
  `share/` homes (#119). `dhparam.pem` → `share/ssl/` (it is consumed
  cross-service — nginx `nginx.conf` and dovecot 2.3/2.4 `10-ssl.conf` both read
  `/etc/ssl/dhparam.pem`, so not an nginx-only asset); the base-stage
  "ship curated, regenerate as fallback" deploy is unchanged. The logrotate
  fragments are distributed to their owning service:
  `share/apache2/logrotate` (+ `share/apache2/httpd-prerotate/`),
  `share/nginx/logrotate`, `share/dovecot/logrotate`, `share/hestia/logrotate`
  — mirroring the existing `share/roundcube/logrotate` (#234). `h-install-hestia`
  repointed; pure moves, no behaviour change.
- Removed the shared `www.conf` PHP-FPM pool and dissolved `install/deb/php-fpm/`
  (#397, #119). Every web domain already runs in its own per-domain FPM pool, so
  the server-wide `www.sock` pool had no serving role left — in upstream it ran
  as `hestiamail` to back the panel-adjacent web apps, but HestiaRE isolated
  those into dedicated per-app Caddy pools (#205/#341), leaving only an apache
  catch-all fallback that *executed* unclaimed `.php` as the `caddy` service user
  unconfined. That is now hardened: `share/apache2/hestia-event.conf` denies
  unclaimed `.php` (`Require all denied`, mirroring Debian's own php-fpm apache
  snippet) and each per-domain vhost re-grants with `Require all granted`
  (`templates/web/apache2/php-fpm/default.{tpl,stpl}`) — so a `.php` no domain
  claims is refused (403) instead of run in a shared context or served as source.
  The three curated assets (`dummy.conf`, `multiphp.tpl`, `php-fpm.conf`) moved
  to `share/php-fpm/`; `h-list-default-php` now reports the default web version
  via `multiphp_default_version()` (update-alternatives) instead of the removed
  `www.conf` marker. Verified on Debian 13 (nginx+apache): claimed domain `.php`
  executes end-to-end, unclaimed `.php` returns 403; nginx-only domains never
  used `www.sock` and are unaffected.
- Dropped the unused `dom` extension from the panel FPM's curated optional set
  (`hestia-php-confd`). Audit A8: no panel (`web/`), phpMyAdmin, or Adminer code
  uses `DOMDocument`/`DOMXPath` (grep-verified in-tree + on the installed
  phpMyAdmin), so it was whitelisted for nothing. The XML family the DB tools do
  need (`simplexml`/`xmlwriter`/`xmlreader`) is unaffected.
- Vendored **Adminer bumped 5.4.4 → 5.5.0** (`share/adminer/adminer.php`,
  VENDORED.json). Adminer is vendored (not the OS package) specifically because
  every target distro ships a CVE-affected version (#350); keeping the vendored
  build current is part of that rationale. Fetched via
  `share/upstream/update-web-vendor.sh --fetch adminer@5.5.0` (GitHub release
  digest verified, `php -l` clean); `upstream/adminer` snapshot branch updated.
  The `login-servers` SSRF-hardening plugin (#356) is re-pinned to the same
  v5.5.0 tag — its file is byte-identical across the two releases (pin only).

### Fixed

- The mail-domain list no longer shows a stale "Anti-Virus / Spam Filter:
  Enabled" icon for domains when the addon isn't installed (#123). Those two
  columns in `list_mail.php` rendered straight from each domain's stored
  `ANTIVIRUS`/`ANTISPAM` value with no gate; they now gate on
  `ANTIVIRUS_SYSTEM`/`ANTISPAM_SYSTEM` (neutral dash when the system is absent),
  matching the add/edit forms — so deleting clamav or rspamd leaves no misleading
  green check while the saved per-domain preference waits for a reinstall.
- Roundcube webmail returned HTTP 500 on every page — `Class "DOMDocument" not
  found` (#402). The `dom` extension had been dropped from the panel PHP's
  curated conf.d by an earlier audit (`hestia-php-confd`) that only checked the
  panel/phpMyAdmin/Adminer consumers and missed the Roundcube/SnappyMail pools
  that #205 had moved onto the same FPM master. Roundcube's template engine
  builds every page via `DOMDocument`, so it hard-fatalled. `dom` is restored as
  a webmail-critical extension (it ships in `php-xml`, already installed for the
  DB tools' simplexml/xmlwriter/xmlreader, so only the symlink was missing), and
  `hestia-php-confd` now documents the full app inventory on the master plus an
  audit rule to grep all three app groups. SnappyMail was unaffected (no
  DOMDocument). Verified: `:8090` 500→200, smoke 33/0 on deb12 + ub24.
- The installer no longer blanket-creates a `v-*` compat alias for every `h-*`
  command (#123). Committed `v-*` symlinks already ship in the tarball, so the
  loop only minted orphan aliases for HestiaRE-native commands. `configure_hestia`
  now just prunes dangling `v-*` (e.g. one left by a renamed/removed `h-*`), and
  `h-check-sys-smoke` guards that none dangle.
- Webmail now degrades safely when the selected client isn't installed (#119).
  Previously `h-add-mail-domain-webmail` hard-exited `E_INVALID` if the client
  wasn't in `WEBMAIL_SYSTEM`, `func/rebuild.sh` hardcoded `roundcube` (failing
  when Roundcube was absent), and selection keyed off the template file existing
  rather than the package — so a domain kept proxying to a dead `:8090/:8091`
  after its webmailer was removed, and removing a webmailer never rebuilt mail
  domains (stale 502 proxies). A shared `select_webmail_template()` helper
  (`func/domain.sh`, used by both the webmail and SSL paths, killing the
  divergent duplicate) now degrades an uninstalled/empty client to the
  backend-safe `disabled` vhost, and `h-add/delete-sys-{roundcube,snappymail}`
  re-render all mail domains so a webmailer install/removal takes effect
  immediately. Verified on Debian 13 (nginx+apache): snappymail domain →
  `:8091`; after `WEBMAIL_SYSTEM=''` → `disabled` vhost (local web stack, no 502,
  no hard-fail); restore → `:8091`.
- PHP-version validation regex now survives a two-digit major in
  `h-change-sys-php` and `h-delete-web-php` (`^[0-9]\.` → `^[0-9]+\.`). Audit A6:
  the same hardening had already landed in `h-change-sys-panel-php` /
  `h-add-web-php`, but these two siblings were missed — they would reject e.g.
  PHP `10.0`.
- MariaDB install aborted on Ubuntu 26.04 when the OS-repo version was chosen
  (#387): `mariadb.service` failed to start with "Table 'mysql.db' doesn't
  exist" — the system schema was never created. Ubuntu 26.04 is the only target
  that ships an *enforced* `mariadbd` AppArmor profile (`/etc/apparmor.d/mariadbd`),
  and it comments out `capability dac_override` — which the bootstrap `mariadbd`
  that `mariadb-install-db` runs needs to create the initial datadir (it dies
  with "Can't create test file … Permission denied"). Normal runtime does not
  need the capability, so only first-init tripped it, and the failure was
  swallowed (`> /dev/null`). `h-add-sys-mariadb` now normalises the datadir to
  `mysql:mysql` and, only when that profile is loaded, unloads it for the
  `mariadb-install-db` step and reloads it (back to enforce) immediately after;
  the init is also guarded to run only when the schema is absent and now fails
  loud (logging to `/var/log/hestia/mariadb-install-db.log`) instead of letting
  the service start error later. No-op on deb12/deb13/ub24 (no loaded mariadbd
  profile). Verified live on ub26: the OS-repo 11.8.6 install completes, the
  profile ends up back in enforce, and runtime works under it.

### Security

- **GHSA-fcq6 — authenticated admin takeover fixed** (#386). The admin-only gate
  in `web/edit/server/hestia/index.php` had a second clause comparing to a bare,
  undefined `$ROOT_USER` — always false, so any authenticated user reached the
  page and could rewrite the hestia panel service config and the privileged panel
  crontab (→ root). It now gates on the role alone. Affects ≤ our 1.9.6 fork
  point; verified against code.
- **GHSA-8w7m — SQL injection via database password fixed** (#386). The password
  was interpolated raw into `IDENTIFIED BY '…'` / `PASSWORD '…'` while the panel
  permits `'` `` ` `` `\` `;`. New `mysql_sql_escape()` / `sql_escape()` helpers
  (cherry-picked from upstream 1.9.7) are now applied at every password site in
  `func/db.sh` (MySQL/MariaDB + PostgreSQL, create + change). db.conf stores only
  the password hash and `func/db.sh` has no `eval`, so there is no second-order
  path.
- **GHSA-cr7q — root RCE via eval in search-object commands fixed** (#386).
  `h-search-user-object` / `h-search-object` ran `eval` on the raw `KEY='value'`
  fields grep'd from a user's own web/mail/db/cron.conf. Every eval site now uses
  the no-eval parser (`parse_object_kv_list_non_eval`, `declare -g`) and bash
  indirect expansion, so a quote-breaking conf value can no longer execute as
  root.
- **GHSA-5fpv — cron parsing hardened** (#386, defense-in-depth). The RCE sink is
  already closed (the rebuilt quote-safe `parse_object_kv_list`), but
  `sync_cron_jobs` now reads with `read -r` and `is_cron_command_valid_format`
  rejects embedded newlines. **Behaviour note:** `read -r` preserves backslashes
  the old `read` stripped one level of, so a cron `CMD` written under the old
  behaviour may be interpreted differently — pre-1.0, no live systems.
- Not affected, verified against code — and **GHSA-w3mx double-eval RCE
  empirically refuted** by running the original attack against our
  `parse_object_kv_list` (payloads stay literal, breakout rejected): GHSA-w3mx
  (parser rebuilt), GHSA-gh6f (web terminal removed, #59), GHSA-73p3
  (`CF-Connecting-IP` trusted only behind Cloudflare ranges), GHSA-fg7j
  (usernames cannot carry HTML — validator charset), GHSA-47mf (queue lines carry
  only validated identifiers). `h-check-sys-smoke` gained static invariant gates
  for the fcq6 and cr7q fixes so they cannot silently regress.

## v0.10.0 (2026-07-19)

Covers everything since v0.9.0. The headline is platform reach: Ubuntu 24.04
and 26.04 join Debian 12 and 13 as first-class targets.

### Breaking / Upgrade notes

- **Command renames** (hard cut, pre-1.0, no deprecation shims, no live
  systems): `h-delete-sys-redis` → `h-remove-sys-redis`,
  `h-delete-sys-roundcube` → `h-remove-sys-roundcube`,
  `h-delete-sys-snappymail` → `h-remove-sys-snappymail`. The orphaned
  `v-delete-sys-snappymail` symlink is gone with the old name; no new `v-*`
  symlinks (#121, #234).
- **`DB_SYSTEM` is now seeded empty** and composed from actually-registered
  database hosts instead of hard-seeded to `mysql`. Registering the first host
  of a type enables it; removing the last host drops the token. This is a
  behaviour change on a contract parsed by ~466 consumers — audit anything that
  reads `DB_SYSTEM` (mechanics under Changed) (#121).
- **Webmail delivery re-architected** (#205): Roundcube/SnappyMail render
  through the Panel-Caddy, and per-domain `webmail.<domain>` vhosts
  reverse-proxy to it instead of serving a docroot. Fresh-install only, no
  migration path — no live systems (details under Added).

### Added

- **Ubuntu 24.04 and 26.04 are now first-class targets, on par with Debian 12
  and 13.** Every change is verified on all four from here on. Reaching parity
  drove a round of installer/mail/sudo hardening specific to the Ubuntu 24/26 +
  deb13 baseline — several release-blocking bugs surfaced only there (see the
  `libzip` naming, dhparam ordering, sudo-rs, and dovecot 2.4 entries below).
- Webmail is delivered through the **Panel-Caddy** instead of the customer web
  stack (#205). Roundcube and SnappyMail each get a dedicated `caddy` FPM pool
  (`share/panel-php/pool.d/`) behind an internal loopback listener
  (`127.0.0.1:8090` / `:8091`) — the phpMyAdmin/Adminer model. Per-domain
  `webmail.<domain>` vhosts **reverse-proxy** to those listeners (nginx, and the
  apache-only case via `mod_proxy_http`), so the `caddy`-owned data dirs are
  never touched by `www-data` — the root cause of the old SnappyMail "Permission
  denied!" — and there is one renderer instead of one per domain. Roundcube is
  additionally reachable on the panel URL at `:8083/webmail` (admin access
  without a customer domain; Roundcube-only, since SnappyMail is a root-mounted
  app that cannot live under a sub-path). Let's Encrypt is unchanged: the
  `webmail.`/`mail.` SANs stay on the customer vhost and the http-01 challenge is
  served locally (nginx inline `return 200`; apache-only `.well-known` alias +
  `ProxyPass !` exclusion with `AllowOverride None` on the docroot). Verified
  live on deb13 (Roundcube) and ub24 (SnappyMail): render, real IMAP login, and
  the apache well-known split.
- Adminer as the PostgreSQL web UI, an optional addon (#350):
  `h-add-sys-adminer` / `h-remove-sys-adminer` serve a single sha256-pinned
  vendored PHP file (`share/adminer/`) at `/adminer/` via a dedicated caddy FPM
  pool — repo-vendored because every OS `adminer` package ships a CVE-affected
  version. The wizard pre-selects it when PostgreSQL is chosen. phpMyAdmin/MySQL
  is untouched.
- PostgreSQL is a fully panel-integrated, removable component (#121):
  `h-add-sys-postgresql` / `h-remove-sys-postgresql`. The add command installs
  PostgreSQL (`postgresql-common` first, #353), sets a password on the
  `postgres` superuser for loopback TCP login, and registers the local host so
  the panel can create/manage PostgreSQL databases and users. Readiness via
  `pg_isready` (not the oneshot `systemctl` umbrella, which reports active even
  when the cluster is down). Remove refuses while customer databases exist and
  keeps the datadir by default (`PURGE_DATA=yes` to drop); credentials live in
  `conf/pgsql.conf`, never install.conf.
- MariaDB is a standalone, removable component (#121):
  `h-add-sys-mariadb [VERSION]` / `h-remove-sys-mariadb`, owning the full
  lifecycle (repo/keyring dispatch — `12.3|11.8|11.4` = MariaDB.org, else the OS
  package; RAM-tiered my.cnf; root unix_socket hardening; host registration;
  implicit phpMyAdmin). `install_db` is now a thin orchestrator that checks exit
  codes instead of inlining the logic, so a failed DB install no longer reports
  "installed" (the #272 class).
- In-place MariaDB version switching: `h-upgrade-sys-mariadb [TARGET]` (#207).
  Forced full logical dump as a hard precondition (kept in `/root`, 0600), repo
  switch, package upgrade, `mariadb-upgrade`, post-check, version recorded.
  **Downgrades are refused** (MariaDB cannot open a newer-format datadir). With
  no argument it lists the curated targets with the version each would actually
  deliver on this system and its reachability, so a specific version can be
  targeted deliberately.
- Fully unattended install via `-a`/`--auto` (#198):
  `bash install.sh <preset> -a` runs with no prompts (FQDN hostname, port 8083,
  admin `admin`, generated + printed password), enabling scripted test-VM
  (re)provisioning. Preset-only stays interactive for the four identity
  questions.

### Changed

- `h-add-database-host` validates the engine against the supported types
  (`mysql|pgsql`) instead of `DB_SYSTEM` membership, and no longer requires
  `DB_SYSTEM` to be pre-enabled (#121): adding the first host of a type is what
  *enables* it, so the old guards were circular — they made the first MySQL host
  depend on a pre-seeded `DB_SYSTEM='mysql'` and made a PostgreSQL host
  impossible to register at all. `h-delete-database-host` now decomposes
  `DB_SYSTEM` (drops the type token when its last host is gone). `DB_SYSTEM` is
  therefore seeded empty; the panel's add-database page filters empty tokens so
  an empty `DB_SYSTEM` renders no ghost type. Idempotency guards on the new
  engine commands are artefact-based (package + host registration), since
  `COMPONENT_*` is the wizard *selection*, not install state.
- The panel wires **Adminer** as the PostgreSQL admin tool (#365, #229): the DB
  list shows an "Adminer" button for PostgreSQL databases (the panel's fixed
  `/adminer/` route) when the Adminer addon is installed, replacing the dead
  phpPgAdmin link; `h-add`/`h-remove-sys-adminer` set/clear a `DB_ADMINER_ALIAS`
  marker the panel reads. phpMyAdmin/MySQL is untouched.
- The panel PHP's curated extension set (`hestia-php-confd`) gained a webmail
  group — `intl` + `phar` (critical) and `exif` (optional) — so the panel FPM
  can serve the webmail clients: without `intl` Roundcube fatals on login
  (`INTL_IDNA_VARIANT_UTS46`), without `phar` SnappyMail's change-password
  plugin blanks the page. `php${VER}-intl` + `php${VER}-exif` are installed
  unconditionally in the panel stage (#205).
- The SnappyMail data dir (`/etc/snappymail/data`) is set to an explicit
  `caddy:caddy 0750` instead of leaving the mode to the release tarball/umask —
  only the caddy FPM pool enters it now (#205).
- Curated config assets continue moving out of the legacy `install/` tree into
  `share/` (#119, no behaviour change): the webmailer assets
  (`share/{roundcube,snappymail}/`), the web-server + phpMyAdmin-SSO assets
  (`share/{apache2,nginx,phpmyadmin}/`), and the MariaDB `my-{small,medium,large}.cnf`
  (`share/mysql/`). Five dead Roundcube files are dropped (recoverable from
  `upstream/hestiacp`); `install/common/` now holds only `bubblewrap/`.

### Removed

- Dead phpPgAdmin plumbing (#365) — superseded by Adminer in #350 but never
  cleaned up: `install/deb/pga/`, the `phppgadmin.*` app templates, an unused
  FPM pool, the `pga` branch of `h-change-sys-db-alias`, the `DB_PGA_*` seeding
  and config fields, and the panel's broken phpPgAdmin links/alias field. Also
  the unused `install/deb/postgresql/pg_hba.conf` and the `phppgadmin` pin in
  `manifest.json`. Recoverable from `upstream/hestiacp`.

### Fixed

- **dovecot 2.4 (Debian 13 / Ubuntu 26): every IMAP/POP3 login was dead on a
  fresh install** (#376) — a textbook "service active, port listening, every
  login hangs" fault, invisible to a plain up/port check. The 2.4 config carried
  `default_login_user = dovecot` (upstream heritage, harmless on 2.3), but the
  login chroot `/run/dovecot/login` ends up `root:dovenull 0750`, so login
  processes running as `dovecot` could not reach the auth socket
  (`auth_process_not_ready`). Now `default_login_user = dovenull`. The smoke
  test additionally gained a protocol **banner** check for IMAP (143) and SMTP
  (25) — exactly the class `check_service`/`check_port` cannot see. Verified live
  on deb13 + ub26.
- Choosing the OS-repo MariaDB silently installed the *external* MariaDB.org
  build on Debian 13 / Ubuntu 26 (#226): the wizard resolved the `__os__`
  sentinel to a bare version number before storing it, and the installer picks
  the repo by matching that number — so when the OS version equalled an offered
  external version (both 11.8) the external repo was added. The version picker
  now maps any non-external pick back to the `__os__` sentinel. Verified live on
  deb12 and deb13 (the collision case).
- phpMyAdmin and Adminer were broken under the isolated panel PHP (#227, #229):
  both run under the shared hestia FPM master, whose curated conf.d only carried
  the panel-UI extensions — so phpMyAdmin died with `undefined function
  ctype_alpha()` (HTTP 500) and Adminer could never reach PostgreSQL (no
  `pgsql`/`pdo_pgsql`). The curated FPM set now also includes the DB-UI
  extensions (ctype, iconv, fileinfo, the xml family; gd/bz2 for phpMyAdmin,
  pgsql/pdo_pgsql for Adminer), installed for the panel version unconditionally.
- `h-add-sys-adminer` no longer silently ships an Adminer without SSRF hardening
  (#229): the "already installed" guard also checks the login-servers plugin, so
  re-running on a pre-#356 install redeploys it; a missing vendored source is now
  a hard error, not a failed `cp` that still reports success.
- Installer prerequisites curated to silence two harmless-but-noisy warnings
  (#356): `apt-utils` is now a prerequisite (debconf "delaying package
  configuration"), and `h-install-hestia` exports `DEBIAN_FRONTEND=noninteractive`
  for the whole run (debconf "unable to initialize frontend: Dialog … Readline").
- Install no longer aborts when rspamd's scan-worker socket is slow to appear on
  a cold first start (#353): the wait is now 60s and — the unit already confirmed
  active — a still-missing socket only warns instead of aborting; the smoke test
  verifies the socket independently.
- PostgreSQL install no longer prints `pg_lsclusters: not found` (#353):
  `postgresql-common` is installed in a separate, earlier transaction so the
  command is on PATH when the metapackage's debconf script runs. Cosmetic — the
  cluster was always created correctly.
- Installer robustness across all four targets, from the Ubuntu 24/26 + deb13
  baseline (#347): `/etc/ssl/dhparam.pem` is laid down in the base stage (nginx
  and dovecot both fatal at start without it — most visibly the sieve-addon
  restart on 24.04); the `libzip` package name is fixed per release
  (`libzip4t64` on 24.04, `libzip5` on 26.04, where plain `libzip4` aborted the
  base stage); the non-existent `pgadmin4-web` is no longer installed, leaving
  PostgreSQL CLI-only at that point — superseded within this release by Adminer
  (#350) and full panel integration (#121); and the smoke test checks PostgreSQL
  via `COMPONENT_DB_POSTGRESQL`.
- Sieve addon is over-quota-delivery-neutral (#343): with sieve on, clean mail
  goes through dovecot-lda, which by default *bounced* an over-quota mailbox
  while exim's appendfile *defers*. dovecot-lda now runs with
  `quota_full_tempfail = yes` and `return_fail_output`, so both paths defer.
  (Also documented that sieve scripts run only on non-spam mail — spam bypasses
  lda straight to `.Spam`.)
- SnappyMail integration had three latent defects, found in the #234 webmailer
  baseline: the installer passed the DB password as the panel port (`$argv[4]`
  vs `$argv[5]`), `domains/hestia.json` was built from `json_decode(<path>)` (the
  path string, not the file), and `h-change-sys-port` wrote a second
  `hestia_host` line for the port (key typo) — together breaking password changes
  from SnappyMail. All three fixed.
- Webmailer removal state is consistent now (#234): `h-remove-sys-snappymail`'s
  `WEBMAIL_SYSTEM` cleanup condition was inverted (only cleared when snappymail
  was *absent*); both webmailer removers now strip their token robustly (no stray
  commas) and reset `COMPONENT_MAIL_WEBMAILER` to `NONE` when the removed client
  was the recorded selection.
- The Roundcube logrotate fragment is actually deployed now (#234): it existed in
  the install tree but nothing ever copied it, while the fail2ban `roundcube-auth`
  jail tails the (unrotated) `/var/log/roundcube/errors.log`.

### Security

- rspamd controller socket is no longer reachable by the panel's app pools
  (#341): the controller-UI proxy needs `/run/rspamd/controller.sock`, but the
  grant was `usermod -aG _rspamd caddy` — and since the phpMyAdmin/Adminer/
  Roundcube FPM pools also run as `caddy` (#214), they inherited it via
  `initgroups()` and could hit the controller API (mail metadata across all
  domains, Bayes writes) past `forward_auth`. A dedicated `_rspamd-ctrl` group
  now owns only the socket and is granted to the Caddy *process* via a systemd
  drop-in (`SupplementaryGroups=`), which FPM workers do not inherit — so the
  proxy reaches the socket and the app pools do not. `h-add-sys-rspamd` strips
  the stale `caddy`→`_rspamd` membership from pre-fix installs; smoke checks
  assert the invariant against process credentials, not config.
- Adminer logins are restricted to the local server (#356): the vendored
  login-servers plugin replaces the login form's free-text "Server" field with a
  fixed localhost dropdown (PostgreSQL / MySQL-MariaDB), so the panel's Adminer
  cannot be pointed at an arbitrary remote host — the SSRF follow-up from #350.
- All hestia sudo grants were dead on Ubuntu 26 (#363): `/etc/sudoers.d/hestia`
  opened with `Defaults:root !requiretty`, but Ubuntu 26 ships **sudo-rs** (the
  Rust reimplementation), which does not implement the obsolete `requiretty` and
  rejects the *entire* file when it appears — silently dropping the `hestia`
  grant every privileged panel action relies on. `requiretty` (always a no-op on
  Debian/Ubuntu) is removed everywhere; the smoke test now runs
  `visudo -cf /etc/sudoers.d/hestia` so a file the local sudo cannot parse fails
  the baseline.

## v0.9.0 (2026-07-13)

Covers everything since v0.8.0, including the quick tags v0.8.1–v0.8.3.

### Added

- rspamd and sieve are modular addons (#122): `h-add`/`h-remove-sys-rspamd` and
  `-sieve` install, wire and purge each service; the installer just invokes them
  per recipe. First functional sieve support — ManageSieve on 4190, per-account
  scripts inside the maildir, clean local delivery via dovecot-lda so scripts
  run at delivery (spam keeps exim's direct `.Spam` path)
- rspamd controller web UI embedded in the panel at `/list/rspamd/` (iframe,
  admin-only), gated by Caddy `forward_auth` + a group-restricted unix socket
  instead of TCP localhost; a home-grown override gives it a dark-theme match in
  the same-origin iframe (#301, #319)
- Per-domain spam tuning for customers: mark/reject thresholds and an optional
  subject tag, plus a sender whitelist/blacklist, editable in the panel and via
  `h-*-mail-domain-spam-*`; values live in `mail.conf`, mirrored to per-domain
  exim files read per message (no reload), bounded by `POLICY_SPAM_*` for
  non-admins (#318, #330)

### Changed / Rebuilt

- Panel PHP CLI (`hestia-php`) now loads its own curated extension set from
  `/etc/php/hestia/cli/conf.d` (built by `hestia-php-confd` alongside the FPM
  set), isolated from the customer conf.d of the same PHP version (#281)
- Panel password generator uses a typeable-anywhere character set (no AltGr/dead
  keys, no confusable I/l/1/O/0, 1–3 symbols), so generated passwords survive
  being typed by hand e.g. over VNC (#316)
- rspamd scan worker moved from TCP `127.0.0.1:11333` to a group-restricted unix
  socket (`/run/rspamd/normal.sock`, mode 0660, group `_rspamd`), so local shell
  users can no longer read the rule/score config or submit scan jobs (#321)

### Removed

- Dead DNS feature plumbing (#283): the last `DNS_SYSTEM`-guarded blocks and
  every call to non-existent `h-*-dns` commands across mail/letsencrypt/webmail,
  backups, cpanel import and search; the DNS_SYSTEM/DNS_CLUSTER/DNSSEC keys leave
  `h-list-sys-config`. Kept: the DKIM-DNS record display and the
  HestiaCP-compatible dns.conf/dns/ schema so backups stay bidirectional

### Fixed

- Debian 13 mail stack: local delivery deferred for every message (#329) — the
  dovecot-2.4 mail-account commands wrote the maildir path into the passwd home
  field while exim's appendfile expects the user home. The passwd format is now
  identical on all platforms (home in field 5) and dovecot 2.4 derives the
  maildir from home. Also fixes the `sssl_server_cert_file` typo that produced
  broken dovecot-2.4 per-domain SSL configs

## v0.8.0 (2026-07-11) — cumulative changes since the fork

Everything below shipped incrementally across v0.1.x–v0.8.0. From here on,
entries are grouped per release.

### Removed (vs. HestiaCP)

- DNS server: bind9 and the entire DNS zone management (#58, #213)
- REST API subsystem (#146)
- Web Terminal (#59)
- vsftpd — proftpd remains available as the optional FTP server (#213)
- SpamAssassin — replaced by rspamd, see Added (#284, #299)
- Software Installer ("Quick Install Apps")
- Bundled `hestia-nginx`/`hestia-php` services — the panel now runs on
  OS-repo Caddy and a dedicated Sury PHP-FPM pool, see Changed (#24, #25)
- Legacy hestia package auto-update subsystem (#128) and the dead
  `func/upgrade.sh` (#197)
- Composer dependencies in the panel — the few remaining libraries are
  vendored (#56)
- Node.js build chain for panel assets — native ESM modules, vendored
  Alpine.js, prebuilt CSS (#248)
- `hestiamail` system user (#214)
- Dead ballast sweeps: bind9/named/vsftpd remnants (#213),
  spamassassin/spamd remnants incl. their panel editor pages (#284),
  unused installer data (#119), stale calls to removed DNS commands in
  domain/user lifecycle scripts — errored on every run (#213)

### Changed / Rebuilt

- All CLI commands renamed `v-*` → `h-*`; `v-*` kept as compatibility
  symlinks to ease upstream cherry-picks (#22, #23). HestiaCP compatibility
  is preserved permanently: `/home/$user` layout, command signatures,
  bidirectional backup format
- Panel webserver: Caddy from the OS repo on port 8083 replaces
  hestia-nginx (#24); panel PHP runs in an isolated, pinned Sury FPM pool
  with its own `conf.d` extension set and own `php.ini`, guarded against
  deletion, switchable via `h-change-sys-panel-php` (#25, #250, #272)
- System user model reworked: `hestiaweb` → `hestia`, app pools run as
  `caddy`; phpMyAdmin/phpPgAdmin are served via the Panel-Caddy (#214)
- Installer rebuilt from scratch: monolithic upstream scripts → Makefile
  (#26) → just (#102) → pure-bash two-stage installer — an interactive,
  manifest-driven wizard writes `/etc/hestia/install.conf`, the
  non-interactive `h-install-hestia` consumes it, `COMPONENT_*`-gated and
  idempotent, with fail-clear + resume recovery (#61, #106, #112)
- Instance state moved out of the install root to `/etc/hestia` (config,
  user data, component state) so it survives updates; `data/` dissolved
  (#30, #31, #129, #152, #156)
- `install.conf` doubles as live component state, maintained by
  `h-add-*`/`h-delete-*` commands (#103)
- Package sources moved to OS repos: nginx (#53), Roundcube (#54),
  phpMyAdmin (#55); only two external repos remain (Sury PHP, MariaDB)
- Build & release: tag → CI → curl-able source tarball; no .deb packages,
  no apt repo, no compiled binaries
- Web/proxy port model per install profile — nginx as reverse proxy in
  front of apache2 for customer vhosts (#247)
- phpMyAdmin SSO reimplemented without the REST API: local one-time token
  handoff (#145)
- exim: one dsearch-untainted 4.95+ template for all targets (fixes tainted
  local delivery on exim ≥ 4.96), moved to `share/exim/` (#299)
- Curated config assets live in `share/` — `install/` is legacy and being
  dissolved (#119); upgrade version pins folded into `share/manifest.json`
  (#288)
- Panel rebranding: brand tokens, recolored default/flat/dark themes, new
  dark-tonal and green themes, new logo, header wordmark with trailing R
  (#259, #260, #261, #269, #297)

### Added

- Interactive install wizard (whiptail, manifest-driven) with install
  profiles standard/minimal (#106)
- Post-install smoke test `h-check-sys-smoke` (#221)
- rspamd integration: exim wiring via `variant=rspamd` (exim keeps decision
  authority, per-domain toggles unchanged), curated `local.d` set, Bayes
  learning on an always-present hard-capped Redis companion (64 MB,
  volatile-ttl), Spam→`.Spam` foldering via exim router (#299)
- Redis lifecycle commands `h-add-sys-redis`/`h-delete-sys-redis` honoring
  the rspamd companion contract (promote/demote instead of uninstall)
  (#121)
- Per-mail-domain SMTP relay excludes: `bypass_smtp_relay` router delivers
  listed recipient domains directly via DNS/MX past the relay, managed by
  `h-add`/`h-delete`/`h-list-mail-domain-relay-exclude` (#304) and editable
  in the panel's mail domain settings below the relay credentials (#306)
- `hestia` umbrella command: `hestia install|configure|update|uninstall|status`
- Repo tooling & docs: `CODEMAP.json`, `PATHS.md`, `TROUBLESHOOTING.md`,
  `VENDORED.json`, upstream sync/vendor-update scripts in `share/upstream/`
  (#248)
