# Changelog

All notable HestiaRE changes are documented here, starting from the fork
point — a HestiaCP 1.9.6 snapshot, kept read-only in the `upstream/hestiacp`
branch (upstream's own history was dropped from this file with #307).

Maintenance rule: every larger change adds an entry to the Unreleased
section as part of its PR. On release, the section gets the version number.

## Unreleased

### Removed

- Dead phpPgAdmin plumbing, replaced by Adminer in #350 but never cleaned up
  (#365). phpPgAdmin was never installed or served anymore, yet its wiring lived
  on across the tree: `install/deb/pga/`, the `phppgadmin.*` templates under
  `share/{panel-caddy,nginx,apache2}/apps/`, a whole unused FPM pool
  (`share/panel-php/pool.d/phppgadmin.conf`), the `pga` branch of
  `h-change-sys-db-alias`, the `DB_PGA_ALIAS` seeding in `func/syshealth.sh`, the
  `DB_PGA_*` fields in `h-list-sys-config`, and the panel UI's (broken, 404-ing)
  phpPgAdmin links/alias field. Also dropped the unused
  `install/deb/postgresql/pg_hba.conf` (the installer never deployed it) and the
  `phppgadmin` version pin in `manifest.json`. Recoverable from `upstream/hestiacp`.

### Changed

- The panel now wires **Adminer** into the DB UI as the PostgreSQL admin tool
  (#365, #229): the DB list shows an "Adminer" button for PostgreSQL databases
  (linking to the panel's fixed `/adminer/` route) instead of the dead phpPgAdmin
  link, shown only when the Adminer addon is installed. `h-add-sys-adminer` /
  `h-remove-sys-adminer` set/clear a `DB_ADMINER_ALIAS` marker in `hestia.conf`
  that the panel reads to decide whether to offer the button (the phpMyAdmin
  pattern). phpMyAdmin/MySQL is untouched.

### Added

- Fully unattended install via `-a`/`--auto` (#198): `bash install.sh <preset> -a`
  now runs with no prompts at all — it takes the same defaults the pre-questions
  would propose (hostname = FQDN, port 8083, admin `admin`, email
  `admin@<hostname>`); the admin password is generated and printed as usual.
  Requires a preset (fails early otherwise, since preset selection would
  otherwise still prompt). Preset-only (`install.sh <preset>`) stays interactive
  for the four identity questions. Enables scripted test-VM (re)provisioning.

### Changed

- Adminer logins are now restricted to the local server (#356): the vendored
  login-servers plugin replaces the login form's free-text "Server" field with a
  fixed localhost dropdown (PostgreSQL / MySQL-MariaDB), so the panel's Adminer
  cannot be pointed at an arbitrary remote host — the SSRF follow-up from #350.
  Username/password login is unchanged; no SSO (out of scope by decision). Fresh
  installs get it automatically; `h-add-sys-adminer` now also deploys
  `adminer-plugins/login-servers.php` (vendored) + `adminer-plugins.php` (the
  localhost config).

### Fixed

- All hestia sudo grants were dead on Ubuntu 26 (#363): `/etc/sudoers.d/hestia`
  opened with `Defaults:root !requiretty`, but Ubuntu 26 ships **sudo-rs** (the
  Rust reimplementation) as its default sudo, and sudo-rs does not implement the
  obsolete `requiretty` setting — it rejects the *entire* file when it appears,
  silently dropping the `hestia` grant the panel relies on for every privileged
  action. (Classic sudo, incl. Debian 13's 1.9.16, still accepts it — so this is
  a sudo-rs behaviour, not a version bump.) `requiretty` was a CentOS-era
  workaround that was always a no-op on Debian/Ubuntu, so the line is removed
  everywhere. The smoke test now runs `visudo -cf /etc/sudoers.d/hestia`, so a
  file the local sudo cannot parse fails the baseline instead of silently
  disabling the panel. The sudoers source also moved from the legacy
  `install/common/sudo/` to `share/sudo/` (opportunistic step in dissolving
  `install/`, #119).
- phpMyAdmin and Adminer were broken under the isolated panel PHP (#227, #229):
  both run under the shared hestia FPM master, but its curated conf.d
  (`hestia-php-confd`, #272) only carried the panel-UI extension set — so
  phpMyAdmin died with a runtime fatal (`undefined function ctype_alpha()`,
  HTTP 500 on all OSes) and Adminer could never reach PostgreSQL (no
  `pgsql`/`pdo_pgsql` driver). The curated FPM set now also includes the
  extensions the bundled DB web UIs need (ctype, iconv, fileinfo, the xml
  family; gd/bz2 for phpMyAdmin, pgsql/pdo_pgsql for Adminer), and the panel
  stage installs `php-gd`/`php-bz2`/`php-pgsql` for the panel version
  unconditionally — the panel PHP stays self-contained, with no coupling of
  PostgreSQL add/remove to the hestia-php config.
- `h-add-sys-adminer` no longer silently ships an Adminer without SSRF hardening
  (#229): the "already installed" guard now also checks the login-servers plugin
  files, so re-running on an install that predates the plugin (#356) redeploys
  it instead of short-circuiting; and a missing vendored plugin source is now a
  hard error rather than a failed `cp` that still reports success.
- Installer prerequisites curated to silence two harmless-but-noisy warnings
  (#356): `apt-utils` is now a prerequisite (without it debconf logs "delaying
  package configuration" on every apt call), and `h-install-hestia` exports
  `DEBIAN_FRONTEND=noninteractive` for the whole run so sub-commands no longer
  trip debconf's "unable to initialize frontend: Dialog … falling back:
  Readline" in the non-TTY install context.

- Install no longer aborts when rspamd's scan-worker socket is slow to appear
  (#353): a cold first start (Lua compile, language detector, 120+ regexps,
  remote map fetches) can take well over the previous 15s wait, while a warm
  restart binds the socket in ~3s. On deb12/deb13/ubuntu-26 the timeout tripped
  and `h-add-sys-rspamd` hard-exited, leaving the mail stage half-wired
  (`ANTISPAM_SYSTEM` unset). The wait is now 60s and — since the unit is already
  confirmed active — a still-missing socket only warns and continues instead of
  aborting; the smoke test verifies the socket independently. (No redis conflict
  was involved: the 64 MB Bayes cap is applied only to rspamd's own companion
  redis, never when the user selected a full Redis via `DB_REDIS`.)
- PostgreSQL install no longer prints `pg_lsclusters: not found` (#353): the
  `postgresql` metapackage's debconf pre-config script calls `pg_lsclusters`
  before `postgresql-common` (which provides it) is unpacked when both are in one
  apt transaction. `postgresql-common` is now installed in a separate, earlier
  transaction so the command is on PATH. Cosmetic only — the cluster was always
  created correctly.

### Added

- Adminer as the PostgreSQL web UI, offered as an optional addon (#350). It is
  a single vendored PHP file (`share/adminer/adminer.php`, official upstream
  5.4.4 EN build, sha256-pinned in `VENDORED.json`) served by the Panel-Caddy at
  `/adminer/` via a dedicated caddy FPM pool — the same delivery model as
  phpMyAdmin, but repo-vendored because every OS `adminer` package ships a
  CVE-affected version (deb12/noble 4.8.1: CVE-2023-45195/45196 + CVE-2025-43960;
  even 26.04's 5.4.1: CVE-2026-25892, fixed only in 5.4.2). New commands
  `h-add-sys-adminer` / `h-remove-sys-adminer` (no v-* symlinks). The wizard
  offers it in the addons group and pre-selects it when PostgreSQL is chosen
  (`visible_if DB_POSTGRESQL == true`, default on), hidden otherwise — replacing
  the old `DB_PGADMIN` derivation (pgadmin4-web is in no OS repo; phpPgAdmin is
  dormant). The smoke test verifies the Adminer FPM socket when installed, and
  `share/upstream/update-web-vendor.sh` gained an `adminer` target for version
  checks and snapshot rebuilds. phpMyAdmin/MySQL is untouched — the full Adminer
  build can also reach MySQL, but phpMyAdmin stays the default.

### Fixed

- Installer robustness across all four targets, from the Ubuntu 24/26 + deb13
  baseline round (#347): (1) `/etc/ssl/dhparam.pem` is now laid down in the base
  stage instead of the later configure stage — nginx and dovecot both reference
  it and fatal at start if it is missing, so mail delivery could break (dovecot
  `doveconf: Fatal … Can't open /etc/ssl/dhparam.pem`, most visibly during the
  sieve-addon restart on Ubuntu 24.04); (2) the `libzip4` package name is fixed
  per release — `libzip4t64` on 24.04 (t64 transition), `libzip5` on 26.04,
  where plain `libzip4` does not exist and aborted the base stage outright;
  (3) the non-existent `pgadmin4-web` is no longer installed (it is in no OS repo
  and only ever errored) — PostgreSQL is CLI-only until phpPgAdmin is wired up
  (#121); (4) the smoke test now checks PostgreSQL via `COMPONENT_DB_POSTGRESQL`
  (it is not recorded in `DB_SYSTEM`, so it was never verified before)
- Sieve addon no longer changes over-quota delivery behaviour: with sieve on,
  clean mail goes through dovecot-lda, which by default *bounced* an over-quota
  mailbox while exim's appendfile transports (spam, and all mail without the
  addon) *defer*. dovecot-lda now runs with `quota_full_tempfail = yes` and the
  `dovecot_virtual_delivery` transport uses `return_fail_output`, so an
  over-quota mailbox defers on both paths — installing the addon is
  behaviour-neutral. Documented the related property that sieve scripts run
  only on non-spam mail (spam bypasses lda straight to `.Spam`) (#343)
- rspamd controller socket no longer reachable by the panel's app pools
  (#341): the controller UI needs the Panel-Caddy proxy to reach
  `/run/rspamd/controller.sock`, but the grant was `usermod -aG _rspamd caddy`
  — and since the phpMyAdmin/phpPgAdmin/Roundcube FPM pools also run as
  `caddy` (#214), they inherited it via `initgroups()` and could hit the
  controller API (mail metadata across all domains, Bayes writes) past
  `forward_auth`. Now a dedicated `_rspamd-ctrl` group owns only the
  controller socket and is granted to the Caddy *process* via a systemd
  drop-in (`SupplementaryGroups=`), which FPM workers do not inherit — so the
  proxy reaches the socket and the app pools do not. `h-add-sys-rspamd` also
  strips the stale `caddy`→`_rspamd` membership from pre-fix installs;
  `h-remove-sys-rspamd` cleans up the drop-in and group. New smoke checks
  assert the invariant against process credentials, not config, so a
  regression fails the baseline (#341)

## v0.9.0 (2026-07-13)

Covers everything since v0.8.0, including the quick tags v0.8.1–v0.8.3.

### Fixed

- Debian 13 mail stack: local delivery deferred for every message — the
  dovecot-2.4 branch of the mail-account commands (upstream heritage) wrote
  the account maildir path into the passwd home field while exim's
  appendfile transports expect the user home. The passwd format is now
  identical on all platforms (home in field 5; only the quota extra field
  stays version-specific) and dovecot 2.4 derives the maildir from home in
  10-mail.conf, matching the proven 2.3 layout. Also fixes the
  `sssl_server_cert_file` typo that produced broken dovecot-2.4 per-domain
  SSL configs (#329)

### Removed

- Dead DNS feature plumbing (#283): the last `DNS_SYSTEM`-guarded blocks and
  every call to non-existent `h-*-dns` commands are gone from the mail/
  letsencrypt/webmail lifecycle, backups, cpanel import and the search
  commands; `h-list-sys-config` no longer emits the DNS_SYSTEM/DNS_CLUSTER/
  DNSSEC keys (no panel consumer). The restic restore path called
  `h-restore-dns-domain-restic` unconditionally — every full restore hit a
  command-not-found; fixed by removal. `h-change-user-ns` (+ v-* symlink) and
  the panel's orphaned nameserver-input remnants are deleted — nothing read
  the NS values. Kept: the DKIM-DNS record display
  (`h-list-mail-domain-dkim-dns`) and the HestiaCP-compatible user-data
  schema (`dns.conf`, `dns/`, user.conf/package DNS fields, restore ignores
  dns containers) so backups stay bidirectional

### Changed / Rebuilt

- Panel PHP CLI (`hestia-php`) now loads its own curated extension set from
  `/etc/php/hestia/cli/conf.d` (built by `hestia-php-confd` alongside the FPM
  set from #280), isolated from the customer conf.d of the same PHP version.
  The CLI consumers need only compiled-in PHP; the set exists for composer
  runs (phar, mbstring/iconv/ctype, curl/zip) (#281)
- Panel password generator: typeable-anywhere character set (no AltGr/dead
  keys, no confusable I/l/1/O/0 or pipe/braces) with only 1–3 symbols per
  password, so generated passwords survive being typed by hand, e.g. over
  VNC (#316)
- rspamd scan worker moved from TCP `127.0.0.1:11333` to a group-restricted
  unix socket (`/run/rspamd/normal.sock`, mode 0660, group `_rspamd` — the
  installer adds `Debian-exim`), so local shell users can no longer read the
  rule/score configuration or submit scan jobs; same pattern as the
  controller socket from #301 (#321)

### Added

- rspamd and sieve are modular addons (#122 part 1): `h-add-sys-rspamd`/
  `h-remove-sys-rspamd` and `h-add-sys-sieve`/`h-remove-sys-sieve` install,
  wire, unwire and purge each service at runtime; the installer now just
  invokes them per the recipe. The sieve addon is the first FUNCTIONAL
  sieve support: ManageSieve on 4190 (localhost consumers), per-account
  script storage inside the account maildir, and clean local delivery
  switched to dovecot-lda (new `SIEVE` exim macro +
  `dovecot_virtual_delivery` transport) so scripts actually run at
  delivery — spam keeps exim's direct `.Spam` path. Removal reverts to the
  appendfile transport; stored scripts survive re-adding. The
  managesieved/sieve packages left the base install set (#122)
- rspamd controller web UI embedded in the panel at `/list/rspamd/` (iframe),
  admin-only. Two independent access layers: Caddy `forward_auth` requires an
  authenticated admin session, and the controller listens on a unix socket
  (mode 0660, group `_rspamd` — the installer adds `caddy` to it) instead of
  TCP localhost, so no local shell user (e.g. a customer with SSH) can read
  the controller API. No separate rspamd login; installer still sets the
  controller password overriding the stock `q1` default as defense in depth
  (#301)
- Embedded rspamd UI follows the panel theme: on dark panel themes a
  home-grown override stylesheet (`web/css/src/rspamd-dark.css`) is injected
  into the same-origin iframe — rspamd has no native dark mode below 3.14,
  which no target platform ships; the override only touches Bootstrap colour
  classes that are identical across rspamd 3.4/3.8/3.12 (#319)
- Per-domain spam tuning for customers: mark threshold (preset
  tolerant/normal/strict or custom value), reject threshold and an optional
  spam subject tag per mail domain, editable in the panel below the Spam
  Filter toggle and via `h-change`/`h-delete-mail-domain-spam-score`/
  `-spam-reject-score`/`-spam-subject-tag`. Values live in `mail.conf`
  (rebuild/restore-safe), mirrored to per-domain files read by exim per
  message — no reload. Non-admin users are bounded by the new
  `POLICY_SPAM_CUSTOMER_TUNING` and `POLICY_SPAM_(REJECT_)SCORE_MIN/MAX`
  keys; exim keeps decision authority (#318)
- Per-domain sender whitelist/blacklist (spam tuning phase 2): whitelisted
  senders are never treated as spam (scan skipped), blacklisted senders are
  always marked — with `.Spam` foldering and subject tag — and refused at
  SMTP time while Reject Spam is on; whitelist wins on conflict. Patterns
  `user@dom`, `*@dom`, `dom`, `*.dom` per line, managed via
  `h-add|delete|list-mail-domain-spam-whitelist|-blacklist` and two
  textareas in the mail domain editor; same exim-file data model as phase 1,
  no reload. The per-domain greylist toggle from the plan was dropped —
  greylisting is deliberately disabled in HestiaRE (#330)

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
