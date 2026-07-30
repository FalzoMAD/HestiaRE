# Changelog

All notable HestiaRE changes are documented here, starting from the fork
point — a HestiaCP 1.9.6 snapshot, kept read-only in the `upstream/hestiacp`
branch (upstream's own history was dropped from this file with #307).

Maintenance rule: every larger change adds an entry to the Unreleased
section as part of its PR. On release, the section gets the version number.

## Unreleased

### Fixed

- `h-list-sys-php` no longer lists the isolated panel FPM pool (`/etc/php/hestia`,
  unit `hestia-php`) as a pseudo-version `hestia` (#464). Consumers turn the list into
  `php<v>-fpm`, so the stray entry produced the non-existent `phphestia-fpm` and broke
  `h-restart-web-backend` on every box and rolled back every live web-model switch (#120)
  at its health gate. Found in the #120 post-merge live re-verify.
- Web-model switch (#120) rollback no longer risks taking a live server down (#466). On a
  failure before the restart stage (validate / inventory), the running webserver was never
  stopped and is still serving its loaded config, but the rollback did a hard `systemctl
  restart` - a failed start on an unloadable on-disk config (a pre-existing broken include,
  an unreadable cert, disk-full) left it dead. Now `reload-or-restart`: a graceful reload
  keeps the running master up if the config will not load, and still starts a stopped one.
- Web-model switch (#120) cleanup now also removes the departing model's webmail vhost
  source (`$OLD.conf`/`.ssl.conf`) under `/home/*/conf/mail/*/` (#466). It only cleaned the
  web conf dirs, so a switch left a stale old-model webmail conf behind (inert, but it broke
  the byte-identical-to-fresh oracle and the rollback's mixed-tree cleanup).
- Directory listing (`h-change-web-domain-dirlist`) now works under nginx-only (#468). The
  command only ever flipped apache's `Options Indexes` (upstream never handled nginx), so on
  an nginx-only box `DIR_LIST='yes'` was a silent no-op. It now dispatches on the model:
  apache keeps the `Options` sed; nginx gets `autoindex on;` at server level via a
  `nginx.conf_dirlist` include fragment (no token in the templates to flip). Verified on
  deb13 (403 -> 200 listing, survives rebuild via the #456 self-heal).

## v0.12.0 (2026-07-30)

Covers everything since v0.11.0. The headline: the web-serving model is no longer
fixed at install — a **live switch** moves a running server between nginx-only, both,
and apache-only, as a first-class maintenance operation (freeze, snapshot, rollback,
crash recovery). Alongside it, two reference layers land: `STRUCTURE.md` for structural
divergence and per-folder `PROVENANCE.json` for per-file upstream heritage.

### Added

- Live web-serving model switch (#120): `h-add-sys-nginx`, `h-add-sys-apache2`,
  `h-delete-sys-nginx`, `h-delete-sys-apache2` change a running server between
  nginx-only / both / apache-only (previously fixed at install). Four thin commands over
  one shared core (`func/web-model.sh`); the model is derived from the configured
  component set. Runs as a maintenance operation: an exclusive freeze serializes domain
  ops and defers reloads (h-restart-web/-proxy/-service, apache logrotate, LE renewal)
  for the flip; snapshot + rollback (with a crash sentinel + `--recover`) means no
  total-loss window; the departing webserver is stopped+disabled (or `--purge`d), and
  `mod_remoteip` is toggled with the model. Backups gain a web-model marker and a
  cross-model restore prints visible warnings. Delete commands refuse on a dirty config
  unless `--force` (which still logs the overridden checks); a full nginx<->apache swap
  is a deliberate two-step through a serving `both`. Fleet-verified: all four transition
  directions serve HTTP/HTTPS + PHP, a switched box is byte-identical to a fresh install
  of the target model, and crash recovery restores cleanly.
- `STRUCTURE.md` (repo root): a structural-divergence reference mapping each
  major difference from HestiaCP to its follow-on implications (panel Caddy/Sury,
  the system-user split, protected downloads, webmail loopback, FileManager and
  SFTP-jail rebuilds, `/etc/hestia`, permanent removals). Registered in
  `CODEMAP.json` `_meta.reference_docs`. Living doc: keep current with each
  structural change. (#451)
- Per-folder `PROVENANCE.json` (`bin/`, `web/`, `share/`): per-file heritage vs
  HestiaCP - `source_type` (verbatim/derived/cherry-pick/eigenbau), `upstream_path`,
  `upstream_ref` last reconciled, and a RAW churn divergence percentage (triage, not
  truth: it overstates because the `v-*`->`h-*` rename and `install/`->`share/` reorg
  count as churn). Complements `VENDORED.json` (third-party, excluded here) and
  `STRUCTURE.md` (subsystem narrative). Recompute is a manual, occasional job on
  cherry-pick/reintegration - no smoke guard. share/ is best-effort: the #119
  install->share reorg breaks 1:1 paths, so 81 files are flagged for manual origin
  confirmation. (#459)

### Fixed

- Directory listing (`h-change-web-domain-dirlist`) survived no vhost rebuild (#456).
  It flipped apache `Options -Indexes`/`+Indexes` straight in the generated vhost with
  no `web.conf` key, so any `h-rebuild-web-domain(s)` reset it to the template default
  and lost the setting silently. Now persisted as a `DIR_LIST` key and re-applied by the
  rebuild self-heal (mirroring `SSL_FORCE`). Verified on apache-only and both models.
- nginx `suspended.{tpl,stpl}` and `php-fpm/*` templates logged to a hardcoded
  `/var/log/nginx/domains` while the managed dir is `/var/log/$WEB_SYSTEM`; in the
  `both` model that was the wrong directory. Now use `%web_system%` like `default.tpl`
  (#120).

## v0.11.0 (2026-07-28)

Covers everything since v0.10.0. The headline: the **file manager** is rebuilt
per-customer (the kernel UID is the isolation boundary), ClamAV and ProFTPD join
the modular addons, and a round of security hardening lands — impersonation drops
admin privilege, and the GHSA-* advisories against the 1.9.6 fork point are fixed.

### Breaking / Upgrade notes

- The `install/` tree is dissolved and `HESTIA_INSTALL_DIR` retired (#119).
  fail2ban's config moved `install/deb/fail2ban/` → `share/fail2ban/` (the last
  holdout); the stale iptables/ipset copy-blocks in `h-install-hestia` were removed
  (those rules are set up in the configure stage). No live installs pre-v1, so no
  migration path.
- File manager rebuilt (#218/#419), replacing FileGator + the SFTP-loopback
  connector. It runs in a per-customer php-fpm pool **as the customer**, reached via
  Panel-Caddy `/fm/` → `forward_auth` (`web/fm-auth.php`) → a private loopback
  listener; enablement is the per-user `FILE_MANAGER` flag in `user.conf`. All the
  old FileGator plumbing is gone — the composer overlay, the system-wide toggle, the
  `configuration.php` hook, the vestigial system `FILE_MANAGER`/`PLUGIN_FILE_MANAGER`
  keys, and the auto-install block; the old `/usr/local/hestia/web/fm` tree is unused.
  No migration path.
- The SFTP jail no longer uses `/srv/jail` (#413) — it is built per session under
  `/run/hestia/jail` by `pam_namespace`. Fresh installs get this automatically; no
  migration/cleanup path is carried.
- The system removal verb is unified: `h-remove-sys-*` → `h-delete-sys-*` (#123;
  `adminer, mariadb, postgresql, redis, roundcube, rspamd, sieve, snappymail`). This
  restores `v-delete-*` cherry-pick parity and reverses the interim `h-remove-sys-*`
  naming from #121. The install-time prune clears the now-broken `v-remove-sys-*`
  aliases, but any personal scripts calling the old names must be updated.
- ProFTPD installs now record `FTP_SYSTEM=proftpd` (#123) — it was never set before.
  New installs get it automatically; **pre-existing installs keep it empty** (no
  migration) until re-run through `h-add-sys-proftpd`, so the FTP machinery
  (`h-restart-ftp`, RRD FTP graph, smoke FTP check, NAT MasqueradeAddress) stays
  inert on them, as it already was.

### Added

- File manager — vendored TinyFileManager, put on a diet (#218). No external CDN
  (GDPR/offline/CSP): Bootstrap-CSS + a combined Prism build are vendored under
  `share/filemanager/fm/assets/`, FontAwesome is referenced from the panel's own FA7
  (same-origin). jQuery, Bootstrap-JS, DataTables, Dropzone and Ace are replaced by
  vanilla JS + a tiny Bootstrap-compatible shim, a native chunked uploader, native
  table filter/sort, and a Prism-overlay code editor. The panel light/dark theme
  drives the FM (`data-bs-theme`; Bootstrap-CSS 5.2.3 → 5.3.8, PrismJS 1.29.0 →
  1.30.0), and in-page media streams through PHP (the customer home is not
  web-served). Enable/disable **per user from the Edit User page** — an admin-only
  checkbox calls `h-add-user-filemanager`/`h-delete-user-filemanager` on save. The
  checkbox and the panel's File-Manager menu entry appear only while the system
  module is installed (`h-list-sys-config` exports `FILE_MANAGER_PORT`). The vendor
  `--check` gate rejects any external `http(s)` resource reference, so the "vendor
  everything" rule holds mechanically (#434).
- `h-add-sys-clamav` / `h-delete-sys-clamav` — ClamAV mail antivirus as a modular
  addon (#123). The exim antivirus machinery (`.ifdef CLAMD` block) already shipped
  inert. The add command installs the daemon + freshclam, wires **bidirectional**
  exim↔clamav group access (clamav must also read the exim spool it scans), waits for
  the virus DB, and **arms the exim `CLAMD` macro only once clamd answers on the
  socket** — because `defer_ok` is fail-open (a dead clamd accepts mail *unscanned*),
  so an armed-but-blind macro would silently pass mail. Never preselected (clamd holds
  the ~1-2 GB signature DB). Delete is saved-state (per-domain flags kept; the DB
  survives the purge unless `PURGE_DATA=yes`). Verified live on all four distros.
- `h-add-sys-proftpd` / `h-delete-sys-proftpd` — ProFTPD is now a fully modular,
  individually-removable addon (#123). The curated config moved `install/deb/proftpd/`
  → `share/proftpd/` (it was orphaned, so the distro default was live). Cross-distro
  package set (`proftpd-basic` is bookworm-only; modern proftpd split TLS into
  `proftpd-mod-crypto`), an explicit `mod_tls` presence gate (its absence silently
  disables FTPS), and an AppArmor override for Ubuntu 26's enforced profile. Verified
  on all four distros.
- SSH `AllowUsers` allowlist co-maintenance (#412/#413), defense-in-depth. The
  installer seeds a **commented (inert)** `#AllowUsers` line; `h-add-user`,
  `h-delete-user`, `rebuild_user`, and the domain-FTP hooks
  (`h-add-web-domain-ftp`/`h-delete-web-domain-ftp`) keep it in sync via the shared
  `manage_sshd_allowusers`. It edits **only** the account's own token (operator
  entries like `root@10.0.0.5` are preserved), validates with `sshd -t`, reloads sshd
  only when the line is active, and re-comments rather than leaving an active line
  empty (lockout guard). Nothing changes until the operator removes the leading `#`.
- The SFTP jail is rebuilt on `pam_namespace` (#413), replacing the `/srv/jail`
  systemd bind-mount machinery. Per session, `pam_namespace` mounts a private tmpfs on
  `/run/hestia/jail` and runs an init inside the new mount namespace (as root, before
  sshd chroots) that builds the jail at the **fidelity path**
  (`/run/hestia/jail/<user>/<real-home>`) and bind-mounts the real home there — one
  generic rule serving **both** panel users and domain-FTP sub-accounts (whose home is
  user-owned deep under `web/<domain>`, a case native chroot cannot handle).
  Fail-closed rides on sshd's own `safely_chroot()`: the fresh tmpfs root is `1777`
  and `chmod 755` on it is the **last** action, so any failure leaves it world-writable
  and sshd refuses the session. Scope is the `sftp-jailed` group (one static
  `Match Group` block + a `pam_succeed_if` gate, so non-members log in unchanged). No
  persistent state — no `/srv/jail`, no per-user `.mount` units, no `@reboot` cron.
  Verified live on OpenSSH 9.2/9.6/10.0/10.2 across all four distros, including ub26
  with the unprivileged-userns restriction active and no bwrap involved.

### Changed

- SSH-access shells are now a curated allowlist (#412): `nologin` (default) ·
  `jailbash` (bwrap sandbox) · `bash` · `sh`, intersected with `/etc/shells`, shared
  by the hard validator and the panel's single shell source. The upstream
  `dash`/`rbash`/`rssh`/`screen`/`tmux` options are dropped (meaningless or gone), and
  an unquoted `grep -w` that let a bare `bash` validate against `/bin/bash` is fixed.
  Existing off-allowlist shells are preserved (rendered as a selected "(current)"
  option; `rebuild.sh` restores them straight from `/etc/shells`), so saving a form
  unchanged never resets them — only the curated shells are newly assignable.
- Vendored Adminer bumped 5.4.4 → 5.5.0 (`share/adminer/`, VENDORED.json) — Adminer is
  vendored precisely because every target distro ships a CVE-affected version (#350).
  Fetched via `update-web-vendor.sh --fetch adminer@5.5.0` (release digest verified);
  the SSRF-hardening `login-servers` plugin (#356) is re-pinned to the same tag.
- Curated-asset moves out of the legacy `install/` tree (#119, no behaviour change):
  the webmail vhost templates → `share/{nginx,apache2}/webmail/` (`MAILTPL` retired;
  the resolver keys on `$WEB_SYSTEM`; dead RainLoop templates + refs removed);
  `dhparam.pem` → `share/ssl/` (consumed cross-service by nginx and dovecot) and the
  logrotate fragments distributed to their owning service; and the bubblewrap assets
  (`jailbash`, `bwrap-userns-restrict`) → `share/bubblewrap/` (the last thing under
  `install/common/`, so `HESTIA_COMMON_DIR` was removed).
- Removed the shared `www.conf` PHP-FPM pool (#397, #119). Every web domain already
  runs in its own per-domain pool, so the server-wide pool had no serving role left.
  The apache catch-all that *executed* unclaimed `.php` as the `caddy` user unconfined
  is now hardened: `hestia-event.conf` denies unclaimed `.php` (`Require all denied`)
  and each per-domain vhost re-grants — so a `.php` no domain claims returns 403
  instead of running in a shared context or being served as source. Verified on
  Debian 13 (nginx+apache).

### Fixed

- Panel file downloads — user backups, database dumps and site archives were broken on
  the Caddy-fronted panel (#441/#443). They emitted `X-Accel-Redirect`, which Caddy
  served via `file_server` as the `caddy` user — which cannot read the customer-owned
  files, so a download got a **404**. They now stream via PHP `readfile()` from the
  panel pool (owner `hestia`), traversal-guarded and hardened for GB scale: every
  output buffer is drained and `ignore_user_abort(false)` set, so a multi-GB file
  streams to the socket (not into `memory_limit`) and a client disconnect frees the
  worker at the next chunk; writes are flushed 8 KB chunks; and — for the **stored
  backup only** — a single `Range:` request is honoured (206/416, resume). A
  comma-separated multi-range list (the amplification vector) or any malformed spec
  falls back to the whole file; per-request dumps deliberately advertise no ranges (a
  resume would stream a differently-generated file). `encode gzip` now skips
  `/download/*`, `pm.max_children` is raised 4 → 8 (a download binds a worker for the
  whole transfer), a cross-customer request is refused with a redirect, and a smoke
  guard allowlists the X-Accel emitters.
- File manager fixes: a 403 for every request on **apache-only** installs (#218) — the
  secret gate had to move into `<FilesMatch \.php$>`, where the #397 `Require all
  denied` fallback otherwise wins, not just `<Directory>`; the native modal/dropdown
  shim regained the keyboard accessibility Bootstrap-JS provided (focus trap, Escape,
  `aria-*`) (#434); and suspending a user now also cuts **FM** access (#434) — the FM
  runs over an FPM socket, so `usermod --lock` never touched it (`h-suspend-user` tears
  the listener down, `h-unsuspend-user` restores it, same policy gate as SFTP/FTP/SSH).
- `update_user_value()` silently dropped a key on the **last line** of `user.conf`
  (#433): it deleted the line then inserted before the same line number, which is past
  EOF after the delete, so `sed` wrote nothing. It now rewrites in place with `sed c`
  (works on any line, no delimiter a value could contain); fixes the shared helper for
  all ~20 callers.
- Roundcube webmail returned HTTP 500 — `Class "DOMDocument" not found` (#402). The
  `dom` extension had been dropped from the panel FPM's curated conf.d by an audit that
  only checked the panel/phpMyAdmin/Adminer consumers and missed the Roundcube/SnappyMail
  pools moved onto the same FPM master (#205). `dom` is restored (webmail-critical; it
  ships in the already-installed `php-xml`, so only the symlink was missing), and
  `hestia-php-confd` now documents the full app inventory plus an audit rule to grep all
  three app groups. Verified `:8090` 500→200.
- MariaDB install aborted on Ubuntu 26.04 with the OS-repo version (#387):
  `mariadb.service` failed with "Table 'mysql.db' doesn't exist" — the schema was never
  created. Ubuntu 26.04's enforced `mariadbd` AppArmor profile comments out `capability
  dac_override`, which the bootstrap `mariadbd` that `mariadb-install-db` runs needs for
  first-init. `h-add-sys-mariadb` now unloads that profile for the init step only and
  reloads it (enforce) immediately after; the init fails loud instead of letting the
  service error later. No-op on the other three targets. Verified live on ub26.
- The AV/spam columns in `list_mail.php` now gate on `ANTIVIRUS_SYSTEM`/`ANTISPAM_SYSTEM`
  (#123) — a neutral dash when the addon is absent, instead of a misleading green check
  from the stored per-domain value.
- AllowUsers co-maintenance edited the wrong line (#412): the detection regex matched
  the seeded guidance comment, so the username was appended to the prose. Tightened to
  the directive form (`#?AllowUsers`, sshd's own commented-directive style) and reworded
  the seed. Existing installs carry a mangled seed comment; re-seed `/etc/ssh/sshd_config`
  (the line is inert, no access impact).
- Panel Caddy failed to come up on fresh installs — a stray `||` line-continuation had
  turned the unconditional `Caddyfile` copy into the failure branch of the preceding
  `chown` (which never fails), so Caddy kept serving the distro-default site on `:80` and
  the panel on `:8083` was unreachable. Restored `chown … || true`. Separately,
  `h-restart-service hestia` no longer fails — the legacy single-service name now maps to
  the real `caddy hestia-php` pair.
- Webmail degrades safely when the selected client isn't installed (#119): a shared
  `select_webmail_template()` degrades an uninstalled/empty client to the backend-safe
  `disabled` vhost, and `h-add/delete-sys-{roundcube,snappymail}` re-render mail domains
  so an install/removal takes effect immediately (no stale 502). Also: the PHP-version
  regex now survives a two-digit major in `h-change-sys-php`/`h-delete-web-php`
  (`^[0-9]\.` → `^[0-9]+\.`), and the installer no longer blanket-creates a `v-*` alias
  for every `h-*` command (#123; it only minted orphans for HestiaRE-native commands).

### Security

- Impersonation ("login as") now **drops admin privilege** while acting as a customer
  (#438). Previously `userContext` stayed `"admin"` for the whole impersonation, so all
  161 admin-only gates remained reachable — a same-origin script in an impersonation
  session (the FM media handler was one such path, #435) could drive admin endpoints.
  `userContext` is now the **effective** (impersonated) role, so those gates refuse
  automatically; a durable `adminContext` holds the real role for the impersonation
  controls and off-chain routes. The session id is **regenerated at both transitions**,
  so an id captured during impersonation cannot regain admin — **side effect:** any
  other tab sharing the session (a second admin tab, an open File Manager tab) is logged
  out at the switch. `web/download/backup` scoping was corrected to the effective user,
  and a smoke allowlist limits which files may read the raw `$_SESSION["user"]`. Scope
  note: this shrinks the reachable surface; it does **not** draw a privilege boundary
  (the panel process runs as `hestia` and may call any `h-*`, so a panel-PHP RCE is
  game-over regardless), and impersonating another admin keeps admin.
- File manager media handler — panel-origin XSS hardened (#218/#432). The FM is
  same-origin with the panel, so the `?media=` stream now derives `Content-Type` **only**
  from a server-side extension allowlist (never from file content or the client), forces
  everything outside it — **SVG included** — to `application/octet-stream` + attachment,
  and always sends `X-Content-Type-Options: nosniff` and CSP `default-src 'none';
  sandbox`; a runtime guard refuses any active type even if one were ever added to the
  map. Previously `finfo` content-sniffing let a customer's `evil.svg`/`x.html` run
  script under the panel session — including an admin's own via "login as". The
  Google/Microsoft doc-viewer iframes were removed, and Caddy now strips **all** inbound
  `X-Hestia-*` before re-setting the trusted ones (making the header invariant structural).
- GHSA advisories fixed (#386, all ≤ our 1.9.6 fork point, verified against code):
  - **GHSA-fcq6** — authenticated admin takeover: the admin gate in
    `web/edit/server/hestia/` had a second clause comparing to an undefined `$ROOT_USER`
    (always false), so any authenticated user reached the page and could rewrite the panel
    service config + privileged crontab (→ root). Now gates on the role alone.
  - **GHSA-8w7m** — SQL injection via the database password: it was interpolated raw into
    `IDENTIFIED BY`/`PASSWORD`. New `mysql_sql_escape()`/`sql_escape()` (cherry-picked from
    1.9.7) are applied at every password site in `func/db.sh`.
  - **GHSA-cr7q** — root RCE via `eval` in `h-search-user-object`/`h-search-object`: every
    eval site now uses the no-eval parser + indirect expansion, so a quote-breaking conf
    value can no longer execute as root.
  - **GHSA-5fpv** — cron parsing hardened (defense-in-depth; the RCE sink was already
    closed): `sync_cron_jobs` reads with `read -r` and rejects embedded newlines.
    Behaviour note: `read -r` preserves backslashes the old `read` stripped, so a cron
    `CMD` written under the old behaviour may be read differently (pre-1.0, no live systems).
  - **Not affected, verified against code**: GHSA-w3mx (double-eval RCE, empirically
    refuted against the rebuilt parser), GHSA-gh6f (web terminal removed, #59), GHSA-73p3
    (`CF-Connecting-IP` trusted only behind Cloudflare ranges), GHSA-fg7j (username
    charset), GHSA-47mf (queue lines carry only validated identifiers). `h-check-sys-smoke`
    gained static invariant gates for the fcq6 and cr7q fixes.

## v0.10.0 (2026-07-19)

Covers everything since v0.9.0. The headline is platform reach: Ubuntu 24.04
and 26.04 join Debian 12 and 13 as first-class targets.

### Breaking / Upgrade notes

- Command renames (hard cut, pre-1.0, no live systems):
  `h-delete-sys-{redis,roundcube,snappymail}` → `h-remove-sys-*`; the orphaned
  `v-delete-sys-snappymail` symlink is gone, no new `v-*` symlinks (#121, #234).
- `DB_SYSTEM` is now seeded empty and composed from actually-registered database hosts
  instead of hard-seeded to `mysql` — a behaviour change on a contract ~466 consumers
  read (#121).
- Webmail delivery re-architected (#205): Roundcube/SnappyMail render through the
  Panel-Caddy, and per-domain `webmail.<domain>` vhosts reverse-proxy to it instead of
  serving a docroot. Fresh-install only, no migration path.

### Added

- **Ubuntu 24.04 and 26.04 are now first-class targets, on par with Debian 12 and 13.**
  Every change is verified on all four from here on; reaching parity drove a round of
  installer/mail/sudo hardening specific to that baseline (see the `libzip`, dhparam,
  sudo-rs and dovecot 2.4 entries below).
- Webmail is delivered through the Panel-Caddy instead of the customer web stack (#205).
  Roundcube and SnappyMail each get a dedicated `caddy` FPM pool behind an internal
  loopback listener (`127.0.0.1:8090`/`:8091`); per-domain `webmail.<domain>` vhosts
  reverse-proxy to those, so the `caddy`-owned data dirs are never touched by `www-data`
  (the root cause of the old SnappyMail "Permission denied!"). Roundcube is additionally
  reachable at `:8083/webmail`. Let's Encrypt is unchanged. Verified on deb13 + ub24.
- Adminer as the PostgreSQL web UI, an optional addon (#350): `h-add-sys-adminer` /
  `h-remove-sys-adminer` serve a single sha256-pinned vendored PHP file at `/adminer/`
  (repo-vendored because every OS `adminer` ships a CVE-affected version).
- PostgreSQL is a fully panel-integrated, removable component (#121):
  `h-add-sys-postgresql` / `h-remove-sys-postgresql` — installs PostgreSQL, sets a
  loopback password, registers the host; readiness via `pg_isready`; removal refuses
  while customer databases exist and keeps the datadir unless `PURGE_DATA=yes`.
- MariaDB is a standalone, removable component (#121): `h-add-sys-mariadb [VERSION]` /
  `h-remove-sys-mariadb`, owning the full lifecycle (repo/OS dispatch, RAM-tiered
  my.cnf, root unix_socket hardening, host registration). In-place version switching
  `h-upgrade-sys-mariadb [TARGET]` (#207) — forced logical dump as a hard precondition,
  downgrades refused (a newer-format datadir can't be reopened).
- Fully unattended install via `-a`/`--auto` (#198): `bash install.sh <preset> -a`
  runs with no prompts (generated + printed admin password), for scripted test-VM
  (re)provisioning.

### Changed

- `h-add-database-host` validates the engine against the supported types
  (`mysql|pgsql`) instead of `DB_SYSTEM` membership (#121): adding the first host of a
  type is what *enables* it, so the old guards were circular. `h-delete-database-host`
  drops the type token when its last host is gone; `DB_SYSTEM` is therefore seeded
  empty and the panel filters empty tokens.
- The panel wires Adminer as the PostgreSQL admin tool (#365, #229): the DB list shows
  an Adminer button for PostgreSQL databases (via a `DB_ADMINER_ALIAS` marker),
  replacing the dead phpPgAdmin link. phpMyAdmin/MySQL is untouched.
- The panel FPM's curated extension set gained a webmail group — `intl` + `phar`
  (critical) and `exif` (optional) — so the panel FPM can serve the webmail clients
  (without `intl` Roundcube fatals on login, without `phar` SnappyMail's
  change-password plugin blanks); installed unconditionally in the panel stage (#205).
- The SnappyMail data dir is set to an explicit `caddy:caddy 0750` (#205).
- More curated config assets moved `install/` → `share/` (#119, no behaviour change):
  the webmailer, web-server + phpMyAdmin-SSO, and MariaDB `my-*.cnf` assets. Five dead
  Roundcube files dropped (recoverable from `upstream/hestiacp`).

### Removed

- Dead phpPgAdmin plumbing (#365) — superseded by Adminer but never cleaned up:
  `install/deb/pga/`, the `phppgadmin.*` app templates, an unused FPM pool, the `pga`
  branch of `h-change-sys-db-alias`, the `DB_PGA_*` fields, and the panel's broken
  links/alias field. Recoverable from `upstream/hestiacp`.

### Fixed

- **dovecot 2.4 (Debian 13 / Ubuntu 26): every IMAP/POP3 login was dead on a fresh
  install** (#376). `default_login_user = dovecot` (upstream heritage, harmless on 2.3)
  could not reach the auth socket in the `root:dovenull 0750` login chroot; now
  `dovenull`. The smoke test gained IMAP/SMTP protocol **banner** checks. Verified live
  on deb13 + ub26.
- Choosing the OS-repo MariaDB silently installed the *external* MariaDB.org build on
  deb13/ub26 (#226): the `__os__` sentinel resolved to a bare version the installer then
  matched to the external repo. The picker now maps any non-external pick back to the
  sentinel. Verified on the collision case (both 11.8).
- phpMyAdmin and Adminer were broken under the isolated panel PHP (#227, #229): the
  curated conf.d carried only the panel-UI extensions, so phpMyAdmin died on
  `ctype_alpha()` and Adminer could not reach PostgreSQL. The DB-UI extensions (ctype,
  iconv, fileinfo, the xml family; gd/bz2; pgsql/pdo_pgsql) are now included.
- `h-add-sys-adminer` re-runs now redeploy the SSRF-hardening plugin, and a missing
  vendored source is a hard error rather than a failed `cp` that still reports success
  (#229).
- Installer prerequisites curated to silence two noisy debconf warnings (#356);
  install no longer aborts when rspamd's scan-worker socket is slow on a cold start
  (#353); the cosmetic `pg_lsclusters: not found` on PostgreSQL install is gone (#353).
- Installer robustness across all four targets (#347): `/etc/ssl/dhparam.pem` is laid
  down in the base stage (nginx and dovecot both fatal without it), the `libzip`
  package name is fixed per release (`libzip4t64` on 24.04, `libzip5` on 26.04), the
  non-existent `pgadmin4-web` is no longer installed, and the smoke test checks
  PostgreSQL.
- Sieve addon is over-quota-delivery-neutral (#343): dovecot-lda now defers (not
  bounces) an over-quota mailbox, matching exim's appendfile.
- SnappyMail integration had three latent defects, found in the #234 webmailer baseline
  — the DB password was passed as the panel port, `domains/hestia.json` was built from
  the path string not the file, and `h-change-sys-port` wrote a duplicate `hestia_host`
  line — together breaking password changes from SnappyMail. All three fixed.
- Webmailer removal state is consistent now (#234): the inverted `WEBMAIL_SYSTEM`
  cleanup condition is fixed, both removers strip their token cleanly, and
  `COMPONENT_MAIL_WEBMAILER` resets to `NONE` when the removed client was the selection.
- The Roundcube logrotate fragment is actually deployed now (#234) — it existed in the
  install tree but nothing copied it, while the fail2ban jail tailed the unrotated log.

### Security

- rspamd controller socket is no longer reachable by the panel's app pools (#341): the
  grant was `usermod -aG _rspamd caddy`, and since the phpMyAdmin/Adminer/Roundcube FPM
  pools also run as `caddy`, they inherited it and could hit the controller API past
  `forward_auth`. A dedicated `_rspamd-ctrl` group owns the socket and is granted to the
  Caddy *process* via a systemd `SupplementaryGroups=` drop-in, which FPM workers do not
  inherit. `h-add-sys-rspamd` strips the stale membership from pre-fix installs.
- Adminer logins are restricted to the local server (#356): the vendored login-servers
  plugin replaces the free-text "Server" field with a fixed localhost dropdown — the
  SSRF follow-up to #350.
- All hestia sudo grants were dead on Ubuntu 26 (#363): `/etc/sudoers.d/hestia` opened
  with `Defaults:root !requiretty`, but Ubuntu 26 ships **sudo-rs**, which rejects the
  entire file over the obsolete `requiretty` — silently dropping the grant every
  privileged panel action relies on. `requiretty` (always a no-op here) is removed
  everywhere; the smoke test now runs `visudo -cf /etc/sudoers.d/hestia`.

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
