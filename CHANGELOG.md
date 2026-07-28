# Changelog

All notable HestiaRE changes are documented here, starting from the fork
point — a HestiaCP 1.9.6 snapshot, kept read-only in the `upstream/hestiacp`
branch (upstream's own history was dropped from this file with #307).

Maintenance rule: every larger change adds an entry to the Unreleased
section as part of its PR. On release, the section gets the version number.

## Unreleased

### Breaking / Upgrade notes

- The `install/` tree is dissolved and `HESTIA_INSTALL_DIR` retired (#119). fail2ban's
  config (`jail.local`, `filter.d/`, `action.d/`) moved `install/deb/fail2ban/` →
  `share/fail2ban/` (the installer copies from there now); it was the last holdout.
  The stale iptables/ipset copy-blocks in `h-install-hestia` (which sourced from the
  now-vacated `install/` tree) were removed — those rules are set up in the configure
  stage from `/etc/hestia`. No live installs pre-v1, so no migration path.
- Removed the leftover **FileGator** plumbing after the FM rebuild (#218): the
  `install/deb/filemanager/` composer overlay, the `filegator` manifest pin, the
  system-wide File-Manager server toggle (edit/server), the FileGator `configuration.php`
  hook in `h-change-sys-config-value`, the vestigial system `FILE_MANAGER` /
  `PLUGIN_FILE_MANAGER` keys in `h-list-sys-config`, and the `syshealth` block that
  auto-installed the module. The FM is per-customer now (`FILE_MANAGER` in user.conf).

- File manager rebuilt (#419, replaces FileGator + the SFTP-loopback connector). The
  `h-add-sys-filemanager`/`h-delete-sys-filemanager` commands no longer download FileGator
  or run composer; the app now runs in a per-customer php-fpm pool **as the customer** (the
  kernel UID is the isolation boundary), reached via Panel-Caddy `/fm/` → `forward_auth`
  (`web/fm-auth.php`) → a private loopback listener. New per-user commands
  `h-add-user-filemanager`/`h-delete-user-filemanager`, saved-state on module delete, and a
  `rebuild_user` restore hook. Phase 1 (integration skeleton) only — the vendored app follows
  in Phase 2 (#218). No live installs pre-v1, so no migration path; the old
  `/usr/local/hestia/web/fm` tree is unused.

- File manager — bumped vendored Bootstrap-CSS 5.2.3 → 5.3.8 and PrismJS 1.29.0 → 1.30.0
  (#218). Bootstrap 5.3 adds native `data-bs-theme` colour modes, which the FM's theme
  passthrough (S2) relies on — 5.2.3 ignored `data-bs-theme` entirely. upstream/* snapshot
  branches + VENDORED.json pins updated accordingly.

- File manager Phase 4 — panel menu + robustness (#218). The panel's "File manager"
  menu entry now follows the customer's own `FILE_MANAGER` flag (exposed via
  `h-list-user`, surfaced as `USER_FILE_MANAGER` for the effective/impersonated user)
  instead of the legacy system-wide FileGator toggle. `h-add-user-filemanager` waits
  for the pool socket before returning, so clicking the menu right after enabling never
  races a not-yet-ready socket.

- File manager Phase 2 — vendored TinyFileManager put on a diet (#218). All external
  CDN assets are dropped (GDPR/offline/CSP): Bootstrap-CSS + a combined Prism build are
  vendored under `share/filemanager/fm/assets/`, FontAwesome is referenced from the panel's
  own FA7 copy (same-origin). jQuery, Bootstrap-JS, DataTables, Dropzone and Ace are removed
  — replaced by vanilla JS + a tiny Bootstrap-compatible modal/dropdown shim, a native
  chunked uploader, native table filter/sort, and a Prism-overlay code editor (highlighting +
  line numbers, no preview). FA4 icons remapped to FA7. File sharing/direct-links removed
  (P11). The panel light/dark theme now drives the FM (`fm-auth` passes `X-Hestia-Theme`), and
  in-page media (img/audio/video) streams through PHP since the customer home is not web-served.

- The SFTP jail no longer uses `/srv/jail` (#413) — it is now built per session under
  `/run/hestia/jail` by `pam_namespace`. Fresh installs get this automatically; there
  are no live installs pre-v1, so no migration/cleanup path is carried.
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

- `share/upstream/update-web-vendor.sh --check` now also gates the File Manager fork
  against external `http(s)` resource references (#434). The diet's "vendor
  everything" rule (GDPR/offline/CSP) is enforced mechanically — a stray ref (like
  the Google/MS doc-viewer iframes removed in #435) fails the check instead of
  surviving on review. Comment lines, SVG `xmlns` namespaces and the app's own
  project/help nav links are allowlisted.
- File manager can now be enabled/disabled **per user from the Edit User page** (#218)
  — an admin-only "Enable File Manager" checkbox under Advanced Options that calls
  `h-add-user-filemanager` / `h-delete-user-filemanager` on save (so it builds/tears down
  the customer's FPM pool + private-listener vhost, not just a flag). The checkbox and the
  panel's File-Manager menu entry only appear while the system module is installed:
  `h-list-sys-config` now exports `FILE_MANAGER_PORT` (set by `h-add-sys-filemanager`,
  cleared by `h-delete-sys-filemanager`), and both gates check it — so uninstalling the
  module hides the menu even for users whose saved `FILE_MANAGER='yes'` flag is retained.
- The SFTP jail is rebuilt on `pam_namespace` (#413), replacing the `/srv/jail`
  systemd bind-mount machinery. Per session, `pam_namespace` mounts a private tmpfs on
  `/run/hestia/jail` (via `share/tmpfiles.d/hestia-jail.conf`) and runs
  `share/security/hestia-jail.init` inside the new mount namespace — as root, before
  sshd chroots — building the jail at the **fidelity path**
  (`/run/hestia/jail/<user>/<real-home>`, from `getent passwd`) and bind-mounting the
  real home there. One generic rule now serves **both** panel users and domain-FTP
  sub-accounts (whose home is user-owned deep under `web/<domain>` — a case native
  chroot cannot handle); the SFTP client sees its true path (e.g.
  `/home/alice/web/site.tld/public_html`). Fail-closed rides on sshd's own
  `safely_chroot()`: the fresh tmpfs root is `1777`, the init builds everything while
  it is still `1777`, and `chmod 755` on the root is the **last** action — so any
  failure leaves the root world-writable and sshd refuses the session (pam_namespace
  ignores the init exit code, so this is the real gate). Scope is the `sftp-jailed`
  group, used both as the sshd chroot selector (a single static `Match Group` block,
  no more growing `Match User` list) and the PAM scope (a `pam_succeed_if` gate, so
  non-members log in completely unchanged). No `/home` ownership flip any more (the
  chroot root is root-owned in the tmpfs; homes keep normal user ownership). No
  persistent state — no `/srv/jail`, no per-user `.mount` units, no `@reboot` cron;
  `/run/hestia/jail` is tmpfs and self-heals on reboot. Verified live on OpenSSH
  9.2/9.6/10.0/10.2 (deb12/ub24/deb13/ub26), including ub26 with the unprivileged-
  userns restriction active and **no** bwrap/userns involved.
- SSH `AllowUsers` co-maintenance now also covers domain-FTP sub-accounts (#413,
  deferred from #412): `h-add-web-domain-ftp` adds the FTP account and
  `h-delete-web-domain-ftp` removes it via `manage_sshd_allowusers`, so an active
  allowlist no longer silently locks out FTP sub-accounts (rebuild goes through
  `h-add-web-domain-ftp`, so it is covered too).
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

- Starting or ending user impersonation ("login as" / return) now rotates the panel
  session id (#438, session-fixation defense). **Behaviour side effect:** any other
  tab sharing that session — a second admin tab, or an open File Manager tab — is
  logged out at the switch. This is intentional (you cannot be admin and a customer
  at the same time), but is a visible change someone may report as a bug.
- Moved the bubblewrap assets `jailbash` (the sandboxed login-shell wrapper) and
  `bwrap-userns-restrict` (the AppArmor profile for the Ubuntu 24.04+ unprivileged-
  userns restriction) from `install/common/bubblewrap/` to `share/bubblewrap/`,
  matching the curated-asset convention (`share/proftpd`, `share/clamav`, …).
  `h-add-sys-ssh-jail` deploys them from the new path. Since bubblewrap was the only
  thing under `install/common/`, the now-unused `HESTIA_COMMON_DIR` variable and the
  empty `install/common/` directory were removed.
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

- Panel file downloads — **user backups, database dumps and site archives** were broken
  on the Caddy-fronted panel (#441). They emitted `X-Accel-Redirect` (an nginx idiom);
  the panel's Caddy config *does* intercept it, but serves via `file_server` as the
  `caddy` user, which cannot read the customer-owned files (`hestia:<user>` `0640`) — so
  an admin downloading a backup got a **404**, not the archive. They now stream via PHP
  `readfile()` from the panel pool (which runs as `hestia`, the owner of those files),
  with the download path `basename()`-guarded against traversal. RRD stats images stay on
  X-Accel (a caddy-readable panel file under the web root). Note: `readfile()` binds a
  panel FPM worker for the download's duration — fine at this scale; revisit
  the pool's `pm` limits if large parallel downloads ever pressure the panel
  (these are manual, logged-in, click-driven downloads — concurrency is minimal
  even at hundreds of users, so no dedicated download pool is warranted).
- Panel downloads — hardened the #441 stream for GB-scale files (#443). The `readfile()`
  in the three handlers is consolidated into `web/inc/download.php` and now: drains every
  output buffer and sets `ignore_user_abort(false)` so a multi-GB backup streams straight
  to the socket (not into `memory_limit`) and a client disconnect frees the FPM worker at
  the next chunk instead of hanging it; writes in flushed 8 KB chunks; and — for the
  **stored backup only** — honours a `Range:` request (206/416 + `Accept-Ranges`) so an
  aborted large download resumes instead of restarting from zero. The db/site archives are
  regenerated per request, so they deliberately do **not** advertise ranges (a resume would
  stream a differently-generated file). The panel php.ini pins `output_buffering = Off` /
  `zlib.output_compression = Off` to match. A smoke guard allowlists X-Accel-Redirect
  *emitters* to `list/rrd/image.php`, so a future download copying that idiom fails the
  smoke rather than silently hitting the caddy-can't-read wall.
- File manager — the native modal/dropdown shim (which replaced Bootstrap-JS in the
  diet) regained the keyboard accessibility Bootstrap-JS used to provide (#434):
  modals now trap focus, close on Escape (honoring `data-bs-keyboard="false"` on
  static dialogs), and return focus to the element that opened them; they carry
  `aria-modal="true"` while open. Dropdowns track `aria-expanded` and close on
  Escape (returning focus to their toggle) as well as on outside click.
- Suspending a user now also cuts their **File Manager** access (#434). The FM pool
  runs as the customer over an FPM socket, so `usermod --lock` (which stops
  SFTP/FTP/SSH) never touched it — a suspended customer kept full FM access,
  including an already-open panel session. `h-suspend-user` now tears the FM
  listener down (keeping the saved `FILE_MANAGER='yes'`) and `h-unsuspend-user`
  restores it, both gated by the same `POLICY_USER_VIEW_SUSPENDED` policy as
  SFTP/FTP/SSH — so "view suspended" deliberately keeps the FM reachable for data
  cleanup.
- `update_user_value()` silently dropped a key that sat on the **last line** of
  `user.conf` (#433). It deleted the line then inserted the new value *before* the
  same line number — but after the delete that address is past EOF, so `sed`
  wrote nothing and the value vanished (no error). It now rewrites the line in
  place with `sed` `c`, which works on any line including the last (and, unlike
  `s`, has no delimiter a value could contain). The FM `FILE_MANAGER` case had a
  call-site workaround (insert before `TIME=`); this fixes the shared helper for
  all ~20 callers. A regression test lives on the `docs` branch.
- File manager gave a 403 for every request on **apache-only** installs (#218): the
  private-listener template gated the secret only in the `<Directory>` block, which
  authorizes static assets but not a `.php` handled by `SetHandler proxy`. That request
  is authorized in the `<FilesMatch \.php$>` context, where the server-wide
  `Require all denied` fallback (`conf.d/hestia-event.conf`, #397) otherwise wins — so
  `index.php` was denied before it ran. Re-assert the secret gate inside `<FilesMatch>`
  (same pattern the customer web templates already use). nginx-fronted profiles were
  unaffected. Found on a fresh apache-only build in fleet verification.
- AllowUsers co-maintenance (#412) edited the wrong line: the seeded guidance
  comment began with "# AllowUsers …", and `manage_sshd_allowusers`' detection regex
  (`#?[[:space:]]*AllowUsers`) matched that prose line, so `h-add-user` tokenised the
  sentence and appended the username to it — mangling the comment and leaving the real
  `#AllowUsers` directive empty. Tightened the regex to the directive form
  (`#?AllowUsers`, no space between `#` and the keyword — sshd's own commented-directive
  style) and reworded the seed so its guidance no longer starts with "AllowUsers".
  Existing installs carry a mangled seed comment; re-seed `/etc/ssh/sshd_config` (the
  line is commented/inert, so there is no access impact). Found in fleet verification.
- Panel Caddy failed to come up on fresh installs — the panel `Caddyfile` was
  never deployed, so Caddy kept serving the distro-default site on `:80` and the
  panel on `:8083` was unreachable. A stray `||` line-continuation
  (`chown … || ` + newline before the `cp`) had turned the unconditional
  `cp share/panel-caddy/Caddyfile /etc/caddy/Caddyfile` into the failure branch of
  the preceding `chown`, so it only ran when the chown failed (it never does).
  Restored `chown … || true` so the `cp` runs unconditionally. (`hestia.conf` on
  the next line still copied, which is why only the listener was wrong.)
- `h-restart-service hestia` no longer fails with "Restart of hestia failed" —
  `hestia` is the legacy single-service name from the hestia-nginx era and has no
  `hestia.service` unit; it now maps to the real panel pair `caddy hestia-php`
  (matching the existing `php-fpm` multi-service handling). Callers
  `h-change-sys-port` and `h-update-host-certificate` restart the panel cleanly.
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

- Impersonation ("login as") now **drops admin privilege** while acting as a
  customer (#438). Previously `$_SESSION["userContext"]` stayed `"admin"` for the
  whole impersonation, so every admin-only route (161 gates) remained reachable —
  a same-origin script running in an impersonation session (the FM media handler
  was one such path, #435) could drive admin endpoints. `userContext` is now the
  **effective** (impersonated) role, so those gates refuse automatically; a new
  durable `adminContext` holds the real logged-in role for the impersonation
  controls and off-chain routes (`fm-auth.php`, download handlers). The session id
  is **regenerated at both transitions** (enter and return), so an id captured
  during impersonation cannot regain admin after return. `web/download/backup`
  scoping was corrected to the effective user (it read the raw session user =
  admin), and `h-check-sys-smoke` gains an **allowlist** guard so only vetted files
  may read the real `$_SESSION["user"]` at all (plus a guard that the old
  effective-mirror `$_SESSION["role"]` is never gated on again — it was unified onto
  `userContext`). Scope note: this shrinks the reachable surface; it does **not**
  draw a privilege boundary — the panel process still runs as `hestia` and may call
  any `h-*`, so a panel-PHP RCE is game-over regardless — and impersonating another
  **admin** keeps admin (no boundary between admins). The impersonation session can
  do only what the **customer** could, which *includes what the customer can do*: a
  same-origin script in it still writes the customer's own web root (e.g. via the
  file manager). That is the accepted residual risk.
- File manager media handler — the inline-media allowlist gained a runtime guard
  that refuses any active `Content-Type` (svg/html/xml/script) even if one were
  ever added to the map (#432). Serving media from a separate origin was considered
  and **rejected**: it would force a DNS record on every install, and the allowlist
  + `nosniff` + CSP `sandbox` already make it unnecessary.
- **File manager media handler — panel-origin XSS hardened** (#218). The FM is
  same-origin with the panel (`:8083/fm/`), so the `?media=` stream serves
  customer-controlled bytes on the panel origin. It now derives `Content-Type`
  **only** from a server-side extension allowlist (never from file content or the
  client), forces everything outside it — **SVG included** — to
  `application/octet-stream` + `Content-Disposition: attachment`, and always sends
  `X-Content-Type-Options: nosniff` and `Content-Security-Policy: default-src 'none'; sandbox`.
  Previously the type came from `finfo` (content-sniffed), so a customer's
  `evil.svg` / `x.html` opened via the handler executed script under the panel
  session — including an admin's own context when viewing via "login as". The
  third-party Google/Microsoft document-viewer iframes were removed as well (they
  leaked the file URL off-box and could not work in the private per-customer FM).
  Caddy now also strips **all** inbound `X-Hestia-*` headers before re-setting the
  trusted ones (`request_header -X-Hestia-*`), making the §7.2 header invariant
  structural instead of an overwrite-list that must stay complete.
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
