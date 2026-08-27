# STRUCTURE.md - structural divergence from HestiaCP

> Read `CLAUDE.md` for the rules, `CODEMAP.json` for component-to-file mapping, and
> `PATHS.md` for the filesystem layout. **This file is the layer underneath those:**
> *why* HestiaRE's structure diverges from HestiaCP and *what each divergence forces*.

The interesting fact about `hestia-nginx -> Caddy` is not the swap itself; it is that
it forced the protected-download path to change, the panel to run as a different user,
and app serving to move to loopback listeners. Those cascades are easy to re-derive
wrong. This document records them once, per delta, in a uniform shape:

**Upstream** (what HestiaCP does) -> **HestiaRE** (what we do) -> **Why** -> **Follow-on**
(what else this forced, with `file:line` anchors).

Baselines: upstream = git branch `origin/upstream/hestiacp`; HestiaRE = `origin/dev`.
Anchors are on `origin/dev` unless prefixed `upstream:`.

**Living doc.** When a structural decision lands (a service swap, a user/isolation
change, a new config location, a removal), add or update the entry here in the same PR.
A point-in-time line-count/churn snapshot lives separately on the `docs` branch
(`codebase-divergence-analysis.md`); this file is the durable, shipped reference.

---

## System-user model (the spine of deltas 1-6)

Several deltas below are consequences of one decision: **who a process runs as**. And
there are always **two** users per concern - the **webserver** user (serves/proxies)
and the **PHP-pool** user (executes PHP). Conflating them hides the actual isolation.

Upstream already split these: the bundled `hestia-nginx` webserver ran as `hestiaweb`,
the panel UI's own PHP pool ran as `hestiaweb` (`upstream:src/deb/php/php-fpm.conf:13`,
socket `/run/hestia-php.sock`), but the **phpMyAdmin / webmail PHP pool ran as a
distinct `hestiamail`** (`upstream:install/deb/php-fpm/www.conf:9`, socket
`/run/php/www.sock`) precisely to keep an app compromise off panel-owned files.
HestiaRE keeps two users too, but **moves the axis of separation**: the privileged
thing held apart is now the **panel PHP** (`hestia`), while the webserver and the app
PHP pools all run as `caddy` - because app state (`/var/lib/roundcube` etc.) is
`caddy`-owned, so pool-user == data-owner (fixes #234).

| Concern | Upstream: web / PHP-pool | HestiaRE: web / PHP-pool | Access boundary |
|---|---|---|---|
| Panel UI | `hestiaweb` / `hestiaweb` | `caddy` / **`hestia`** | `hestia` owns `/etc/hestia`, `/backup`; may `exec` h-*/v-* |
| phpMyAdmin / Adminer | `hestiaweb` / **`hestiamail`** | `caddy` / `caddy` | app-login gated |
| Roundcube / Tachyon (upstream: SnappyMail) | `hestiaweb` / **`hestiamail`** | `caddy` / `caddy` | pool-user == `caddy:caddy` app state (#234) |
| Customer domains | nginx/apache / **the customer** | nginx/apache / **the customer** | kernel UID |
| File Manager | `hestiaweb` / `hestiaweb` (FileGator in-panel, `ROOT_USER` ctx) | loopback nginx/apache + `caddy` forward_auth / **the customer** | kernel UID (#419) |

The two upstream PHP users (`hestiaweb` panel, `hestiamail` apps) map onto HestiaRE's
two (`hestia` panel, `caddy` apps); what changed is which side the webserver shares a
user with (upstream: webserver == panel PHP; HestiaRE: webserver == app PHP).

Rule of thumb for future work: **the panel FPM pool is `hestia`, the webserver and
everything Caddy proxies for apps are `caddy`, and anything touching a customer's files
runs as that customer.** Ownership mismatches against this table are the source of
several past bugs (#234, #441).

**Consequence for panel PHP: it cannot see inside `/home/<customer>`.** Upstream ships
`setfacl -m "g:hestia-users:---"` on every customer home, and HestiaRE puts the panel
account into that group (`sbin/h-install-hestia`), which upstream does not do for its own
panel user - only for `hestiamail`. So the deny entry applies here and every PHP
filesystem call on a customer path fails: `realpath()` returns `false`, and `is_dir()`,
`file_exists()`, `scandir()` return false or nothing, each reading like "does not exist".
That is the intended boundary, not a defect - the panel asks an `h-*` command over sudo
instead. But inherited upstream code does not know it: `realpath()` on `CUSTOM_DOCROOT`
was silently false, so the form showed empty fields and every save reset a customer's
custom document root. **Never stat a customer path from panel PHP; take the value from
the record or from a command.**

---

## 1. Panel webserver: bundled `hestia-nginx` -> OS-repo Caddy

**Upstream.** A purpose-compiled `hestia-nginx` binary, shipped as a `.deb`. Server
block `upstream:src/deb/nginx/nginx.conf`: master runs `user hestiaweb`, panel on
`8083 ssl`, protected assets served via nginx `internal;` locations (`/backup/`,
`/rrd/`, `/error/`).

**HestiaRE.** Caddy from the OS repo, configured by static files under
`share/panel-caddy/` deployed to `/etc/caddy/`:
- `share/panel-caddy/Caddyfile` - global `admin off`, `auto_https disable_redirects`,
  then `import /etc/caddy/*.conf`.
- `share/panel-caddy/hestia.conf` - panel vhost `https://:8083` (`:4`), explicit `tls`
  cert / no ACME (`:5`), `root /usr/local/hestia/web` (`:7`), a `route` block doing
  path canonicalisation + `reverse_proxy @php unix//run/hestia-php.sock` (`:82`).
- Apps pulled in via `import /etc/caddy/apps/*.conf` (`hestia.conf:55`); templates in
  `share/panel-caddy/apps/*.tpl`.

**Why.** Drop the maintenance burden of a forked/compiled `hestia-nginx` in favour of
a stock OS Caddy (the HestiaRE OS-repo-first principle). See also
`webserver-model-switch-plan.md` on the `docs` branch for the customer-webserver model.

**Follow-on.**
- `auto_https disable_redirects` is **required** so Caddy does not bind `:80` and grab
  the port the customer-facing nginx needs (`Caddyfile`, comment).
- The panel now depends on a separate FPM service over `/run/hestia-php.sock`
  (delta 2), not an in-binary PHP.
- Upstream update tooling keyed on the `hestia-nginx` deb name
  (`v-update-sys-hestia`) does not apply.
- Protected downloads had to change because Caddy's `file_server` runs as `caddy`
  (delta 3).

---

## 2. Panel PHP backend: bundled `hestia-php` -> Sury FPM + a pool per concern

**Premise correction.** Upstream does **not** compile customer PHP - it installs
customer multi-version PHP from **Sury apt** too (`upstream:install/hst-install-debian.sh:865-868`,
`upstream:bin/v-add-web-php`). What upstream compiles/bundles is the single **panel
backend**: the `hestia-php` + `hestia-nginx` debs. So the real divergence is (a) the
panel backend, and (b) the pool topology - not the customer PHP source.

**Upstream.** Two panel-plane pools, already split by trust: the panel UI pool `[www]`
as `hestiaweb` (`upstream:src/deb/php/php-fpm.conf:13`, socket `/run/hestia-php.sock`),
and a **separate** phpMyAdmin/webmail pool `[www]` as `hestiamail`
(`upstream:install/deb/php-fpm/www.conf:9`, socket `/run/php/www.sock`) - so an app
compromise cannot reach panel-owned files. Customer domains get per-domain Sury pools
as the customer.

**HestiaRE.** Sury repo factored into one idempotent helper `add_sury_repo <codename>`
(`include/helper.sh:55-74`), called by both wizard-discovery (`include/wizard.sh:267`) and
installer (`bin/h-install-hestia:92`) so only one Sury stanza is ever written (avoids
apt's "Conflicting Signed-By"). The panel runs on a **dedicated PHP tree**
`/etc/php/hestia/` (Sury reference version), not a deb, launched by the wrapper
`sbin/hestia-php-fpm` (reads `/etc/php/hestia/php-version`, `exec`s the right
`php-fpm<ver>`) under `share/panel-php/hestia-php.service`. The single pool explodes
into **five** on that one `hestia` master:

| Pool (`share/panel-php/pool.d/`) | Runs as | Socket | Client |
|---|---|---|---|
| `panel.conf` | `hestia` | `/run/hestia-php.sock` | Caddy panel |
| `phpmyadmin.conf` | `caddy` | `/run/hestia-pma.sock` | Caddy `/phpmyadmin` |
| `adminer.conf` | `caddy` | `/run/hestia-adminer.sock` | Caddy `/adminer` |
| `roundcube.conf` | `caddy` | `/run/hestia-webmail-roundcube.sock` | Caddy `:8090` |
| `tachyon.conf` | `caddy` | `/run/hestia-webmail-tachyon.sock` | Caddy `:8091` |

Plus per-customer pools on the **customer** PHP (`share/php-fpm/multiphp.tpl`,
`user=%user%`) and the FM pool (delta 5).

**Why.** Isolate by trust boundary (see the system-user table). Upstream already
separated the app PHP pool (`hestiamail`) from the panel; HestiaRE keeps the split but
draws the line around the **panel** pool: `panel` runs as `hestia` and keeps `exec`
(its php.ini disables only `pcntl_*`, `share/panel-php/fpm/php.ini:16`), while apps and
webmail run as `caddy` to match `caddy:caddy` data ownership (fixes #234). The panel
gets `env[HESTIA]=/usr/local/hestia` as a **literal** because php-fpm wipes the master
env (a bare `$HESTIA` expands empty -> 502).

**Follow-on.**
- One `hestia` master hosts five co-tenant pools sharing **one** curated `conf.d`
  extension set built by `sbin/hestia-php-confd` - pruning an extension can break a
  co-tenant (the Roundcube `dom` 500 regression, #402; documented in
  `sbin/hestia-php-confd` header).
- "PHP pools on the box" now spans two trees: `/etc/php/hestia/fpm/pool.d/*`
  (hestia/caddy) and `/etc/php/<ver>/fpm/pool.d/*` (customers + `fm-<user>` + `dummy`).
- Panel PHP version is switchable with rollback (`bin/h-change-sys-panel-php:83-91`);
  upstream had no analogue (fixed by the deb).
- `WEB_BACKEND=php-fpm` + `%backend_lsnr%` wiring is otherwise unchanged
  (`include/domain.sh:100-131`).

---

## 3. Protected downloads: nginx `X-Accel-Redirect` -> PHP byte-streaming

**Premise correction.** It is **not** that Caddy lacks an X-Accel equivalent -
HestiaRE implements one (`share/panel-caddy/hestia.conf:87-91`, still used by
`web/list/rrd/image.php`). The real blocker is the **user**: Caddy's `file_server`
runs as `caddy`, which cannot read customer-owned `/backup` files; the panel FPM pool
runs as `hestia`, which owns them.

**Upstream.** PHP validates auth, then hands the file to nginx via
`X-Accel-Redirect`; the `internal;` `/backup/` location serves the bytes as
`hestiaweb`. PHP never streams (`upstream:web/download/backup/index.php` etc.).

**HestiaRE.** A shared helper `serve_download($file, $ctype, $allow_range=false)`
(`web/inc/download.php:10`) clears buffers and streams via an
`fopen`/`fread(8192)`/`echo`/`flush` loop guarded by `connection_aborted()` (`:70`),
with optional **single**-range support (hard cap of one range, comma guard against
multi-range amplification, #443). The three handlers include it:
`backup/index.php` (range allowed - static archive), `database/index.php` and
`site/index.php` (no range - regenerated per request). X-Accel is retained **only**
for caddy-readable panel files under the web root (rrd).

**Why.** Serving customer-owned files through Caddy would require granting `caddy`
read access to customer files - the exact capability HestiaRE avoids (same rationale
as the File Manager). Streaming from the `hestia`-owned pool keeps it contained
(#441; comment `web/inc/download.php:3`).

**Follow-on.**
- **Backup chown flipped**: `bin/h-download-backup:92` chowns fetched backups to
  `hestia:hestia` (upstream `hestiaweb:hestiaweb`) so the panel pool can read them.
- **Gzip disabled on `/download/*`** (`hestia.conf` `@encodable not path /download/*`,
  #443) - re-gzipping GB archives wastes CPU and breaks ranges.
- Panel pool `pm.max_children = 8` headroom: each download now pins a worker for the
  whole transfer (`share/panel-php/pool.d/panel.conf`, comment).
- Range/416/comma-guard logic is new panel surface that nginx previously owned.
- Traversal + impersonation hardening rides along: `basename()` guard and scoping on
  the impersonated user, not raw `$_SESSION["user"]` (#438).

---

## 4. Webmail / apps: `hestiaweb`/`hestiamail` www-data vhosts -> Caddy loopback listeners

**Premise correction.** There is **no** discrete `hestia-mail` systemd service in
either tree (`git grep hestia-mail` is empty upstream). The removed artifact is the
`hestiamail`/`hestiaweb` **system-user** model (#214, `CHANGELOG.md:448,464`) - state
it as user-model + serving-model, not a service.

**Upstream.** Webmail vhosts with a docroot at `/var/lib/roundcube` etc.; the PHP runs
on the dedicated **`hestiamail`** pool (`upstream:install/deb/php-fpm/www.conf:9`,
socket `/run/php/www.sock`), a distinct user from the `hestiaweb` panel - not a
customer `www-data` pool. (`v-add-sys-roundcube` chowns the app tree
`hestiamail:www-data`.)

**HestiaRE.** Two Caddy **loopback listeners**, each backed by a `caddy` FPM pool:
Roundcube `http://:8090 bind 127.0.0.1` -> `/run/hestia-webmail-roundcube.sock`
(`share/panel-caddy/webmail-roundcube.conf:34-52`), Tachyon `:8091`. Customer
`webmail.<domain>` vhosts become **thin reverse proxies with no docroot** that
`proxy_pass` to the loopback listener (`share/nginx/webmail/default.tpl:25`,
`share/apache2/webmail/default.tpl:29`), TLS terminating at the vhost with the
customer LE cert. Admin panel access without a customer domain is the `:8083/webmail`
route (`share/panel-caddy/apps/webmail.tpl`).

Two load-bearing Caddy subtleties: the site address is `http://:8090` + `bind
127.0.0.1` (a Host in the address would make a proxied `Host: webmail.<domain>` match
no site -> empty 200); and it is a loopback **port, not a unix socket** (OS Caddy
2.6.x can't set socket mode for the www-data proxy workers). **Tachyon is
root-mount-only** (assets hard-wired to `/tachyon/...`), so it has no `:8083`
sub-path route - only the `webmail.<domain>` path.

**Why.** App state (`/var/lib/roundcube`) is `caddy`-owned; a `www-data` pool
rendering caddy-owned state was the #234 permission bug. Running the pool as `caddy`
aligns pool user <-> data ownership <-> log dir. Ports 8090/8091 sit above the fixed
web-stack ports and below the customer FPM backend range (from 9000), so they can
never collide.

**Follow-on.**
- Customer-webserver hardening (open_basedir etc.) no longer applies to webmail - the
  trust boundary moved to the `caddy` pool.
- Webmail availability now depends on Caddy + hestia-php; if Caddy is down, all
  `webmail.<domain>` vhosts 502 even with nginx up.
- Backporting upstream `templates/mail/` changes is structurally incompatible: upstream
  `.tpl` carry docroot+fastcgi, HestiaRE `.tpl` carry `proxy_pass`. Backports
  conflict by design.

---

## 5. File Manager: FileGator (in-panel) -> TinyFileManager (per-customer process)

**Upstream.** FileGator (`upstream:bin/v-add-sys-filemanager`): a Composer/Vue app in
`$HESTIA/web/fm` running **inside the panel** as `ROOT_USER`; file access rides the
panel process, not the kernel UID. System-wide, no per-customer isolation.

**HestiaRE.** A vendored, forked single-file TinyFileManager with app-auth disabled,
in a three-layer model (#218/#419):
1. **Shared code**, one root-owned copy: `/usr/share/filemanager/fm`
   (`bin/h-add-sys-filemanager:60-65`).
2. **Per-customer FPM pool run AS the customer**: `fm-<user>` on the customer PHP,
   `user=%user%`, `listen=/run/hestia/fm/<user>.sock`,
   `open_basedir=/usr/share/filemanager/fm:/home/%user%`, `env[FM_ROOT]=/home/%user%`
   (`share/filemanager/fpm-pool.tpl`, deployed by `bin/h-add-user-filemanager`). The
   kernel UID is the file-access boundary.
3. **Caddy `forward_auth` gate** (`share/panel-caddy/apps/filemanager.tpl`): strips
   inbound `X-Hestia-*`, calls `/fm-auth.php` on the `hestia` pool to resolve identity
   (honouring impersonation), then reverse-proxies to a secret-gated per-user loopback
   vhost on `FILE_MANAGER_PORT` (default **8092**), overwriting `Host
   fm-<user>.local` and injecting the shared `X-Hestia-FM-Auth` secret. The listener
   403s without the secret (`share/filemanager/nginx.tpl:12`; apache re-asserts the
   `Require expr` in both `<Directory>` and `<FilesMatch php>`, #429/#397).

**Why.** Per-customer UID isolation: a path-traversal in the app can only reach files
the customer already owns. No Composer/Node dependency. Identity is decided **only**
by `fm-auth.php`, never the client (the "§7.2 invariant").

**Follow-on.**
- Spawns **one php-fpm pool per enabled customer** (`pm=ondemand, max_children=4`);
  cost scales with enabled users, and enabling races the socket (mitigated by a 5s
  socket-wait that fails closed before writing the flag).
- The runtime enable-gate is **socket existence** (`/run/hestia/fm/<user>.sock`), not
  the `FILE_MANAGER` flag, because the low-priv `hestia` pool cannot read
  `/etc/hestia` (700). See `web/fm-auth.php:34-58` and delta 8.
- Two-flag lifecycle: system module (`h-add-sys-filemanager`, provides
  `FILE_MANAGER_PORT`) must exist before per-user enable; the edit-user toggle and the
  `/fm/` menu both gate on `FILE_MANAGER_PORT` **and** per-user `FILE_MANAGER=yes`
  (`web/templates/includes/panel.php:175`).
- DirectLink sharing removed (a direct URL bypasses forward_auth). Backporting upstream
  FM changes is a non-starter (different app entirely); re-vendoring is controlled via
  `share/upstream/update-web-vendor.sh`.

---

## 6. SFTP jail: static `/srv/jail` bind-mounts -> per-session `pam_namespace` tmpfs

**Upstream.** `add_chroot_jail()` (`upstream:include/main.sh:1986`) creates
`/srv/jail/$user`, `chown 0:0`, and writes a **persistent systemd `.mount` unit**
bind-mounting the real home into the jail; `v-add-user-sftp-jail` appends the user to a
growing `Match User a|b|c` sshd list and does `chown root:root /home/$user` (ownership
flip so the chroot component is root-owned). A `@reboot` cron re-seeds the dummy block.

**HestiaRE.** Group-scoped, per-session, zero persistent on-disk jail state (#413):
- `add_chroot_jail()` (`include/main.sh:1780`) reduces to `groupadd sftp-jailed` +
  `usermod -aG sftp-jailed`; delete is `gpasswd -d`. No mounts, no sshd edits per user.
- `bin/h-add-sys-sftp-jail` installs the machinery once: a tmpfiles mountpoint
  (`/run/hestia/jail` 0755 root:root - sshd's `safely_chroot()` refuses a writable
  one), a per-session builder `share/security/hestia-jail.init` wired via
  `/etc/security/namespace.conf`, a PAM gate in `/etc/pam.d/sshd` that runs
  `pam_namespace` **only** for `sftp-jailed` members, and one static `Match Group
  sftp-jailed -> ChrootDirectory /run/hestia/jail/%u` block. Validated with `sshd -t`,
  restores sshd_config on failure.
- The init script builds the jail at `/run/hestia/jail/<user>/<real-home>` mirroring
  the **actual** passwd home (path fidelity), so one generic rule serves FTP
  sub-accounts whose home is deep under `web/<domain>` - a case native
  `ChrootDirectory` cannot handle. **Fail-closed**: `chmod 755` on the jail root is the
  last action, so any earlier failure leaves it world-writable and sshd rejects the
  session.

**Why.** Eliminate persistent jail state and the `chown root:root /home/$user`
ownership flip; rebuild the jail per login on tmpfs, leaving the real home untouched
(`CHANGELOG.md:36-38,90-101`).

**Follow-on.**
- **No migration** from `/srv/jail` (explicit): an in-place upgrade orphans
  `/srv/jail/*`, `.mount` units and `/etc/cron.d/hestia-sftp` - not cleaned up.
- Requires `pam_namespace` + per-session mount-namespace propagation (verified OpenSSH
  9.2-10.2 across the four distros incl. ub26 userns restriction).
- O(1) group membership replaces the O(n) `Match User` regex rewrite - no sshd restart
  per user.
- `jailbash` (interactive shell sandbox) is **shared** with upstream, only relocated
  `install/common/bubblewrap` -> `share/bubblewrap/` (#119); the shell allowlist was
  trimmed to `nologin jailbash bash sh` (`include/main.sh:1414`, #412).

---

## 7. SSH `AllowUsers` co-maintenance - NEW subsystem (#412)

**Upstream.** No `AllowUsers` handling at all (`git grep AllowUsers` empty upstream).

**HestiaRE.** The installer seeds a **commented, inert** `#AllowUsers` directive plus
guidance (`bin/h-install-hestia:121-131`); nothing is enforced until the operator
uncomments it. `manage_sshd_allowusers(add|del, user)` (`include/main.sh:1794-1860`)
edits only the `$user` token (comparing `${t%%@*}` so `root@ip` operator entries
survive), preserves commented/active state, applies a **lockout guard** (re-comments
rather than leave an active line with zero tokens), validates on a temp copy with
`sshd -t -f`, and reloads ssh **only if the line is active**. Hooked from
`h-add-user`, `h-delete-user`, `include/rebuild.sh:95` (restore path - bypasses
`h-add-user`, so without this a restored user is silently locked out), and the FTP
sub-account add/delete hooks.

**Why.** Give operators a maintained SSH allowlist without changing default behaviour
(opt-in). The `rebuild.sh` hook closes the restore gap.

**Follow-on.**
- Opt-in: no behaviour change until uncommented; once active, any account-creating path
  that bypasses these hooks locks the account out.
- **#416 seed/regex bug**: the original regex matched the guidance comment, appending
  usernames to prose. Fixed to sshd's `#?AllowUsers` form + reworded seed
  (`include/main.sh:1800-1805`). Existing installs carry the mangled comment; remediation
  is to re-seed (inert, no access impact).

---

## 8. Config locations: `$HESTIA/data` + `/etc/hestiacp` -> `/etc/hestia` (`CONF_DIR`)

**Upstream.** Mutable state lives inside the install root (`$HESTIA/data/`,
`$HESTIA/conf/`); bootstrap is `/etc/hestiacp/hestia.conf`. Update overwrites the tree.

**HestiaRE.** A single instance-config dir `/etc/hestia`, outside git, surviving
updates. `CONF_DIR="${CONF_DIR:-/etc/hestia}"` (`include/main.sh:48`), exported via
`include/helper.sh:133`. New residents that upstream lacks:

| Path | Role |
|---|---|
| `/etc/hestia/hestia.env` | bootstrap file (renamed from `hestia.conf`, #81) |
| `/etc/hestia/local.conf` | operator overrides, survive upgrades |
| `/etc/hestia/source.conf` | update-channel config (repo/token/channel) |
| `/etc/hestia/install.conf` | wizard recipe **and** live `COMPONENT_*` state (#103) |
| `/etc/hestia/conf/` | panel config; `$HESTIA/conf` is now a **symlink** here (#129) |
| `/etc/hestia/{firewall,ips,queue,users}/` | moved out of `$HESTIA/data/` (#148/#154/#156) |
| `/etc/hestia/packages/` | hosting packages: instance state, panel-created; seeded from `share/hestia/packages/` at install (#663) |
| `/etc/hestia/.done.*` | installer idempotency sentinels |

The `$HESTIA/data/` tree is **fully dissolved**. `install/` (build-time tree) was split
into `share/` (shipped runtime assets) + `templates/` (`WEBTPL`); `HESTIA_INSTALL_DIR`/
`HESTIA_COMMON_DIR` no longer exist. The `packages/` split of #119/#150 was revised in #663:
hosting packages are instance state (panel-created, restore-writable), so they live in
`/etc/hestia/packages/`, and the shipped `default`/`system.pkg` seed there from
`share/hestia/packages/` at install.

### The model is the install scope (#639)

`WEB_SYSTEM`/`PROXY_SYSTEM` decide who serves **and** what is installed. apache-only means no
nginx package on the box - not a running nginx with no vhosts, which is what it used to be. The one
shape that needs an nginx without customer web domains is **mail-only**, and it gets one through
the model: the wizard fixes that preset to `WEB_SERVER=NGINX` for the webmail vhost and ACME
termination (`share/manifest.json`). Upstream has no equivalent - it installs both servers and
decides at render time.

### Template tree: selectable vs shipped (#219)

`templates/` holds **only what somebody chooses**, everything else moved to `share/`:

| Path | Anchor | Contents |
|---|---|---|
| `templates/nginx/` | `$WEBTPL/nginx` | the nginx-only vhost selection (wordpress, laravel, …) |
| `templates/php/` | `$PHPTPL` | FPM pool profiles (`default`, `small`, `high`) - nothing generated per version since #591 |
| `templates/docker/<front>/` | `$WEBTPL/docker` | vhosts for a docker domain, per front system (#566/#592) |
| `share/web/nginx/` | `$SHARETPL/nginx` | the both-model proxy vhost + `proxy_ip` |
| `share/web/apache2/` | `$SHARETPL/apache2` | the apache vhost (both models render it) |
| `share/web/suspend/` | `$SHARETPL/suspend` | admin suspension + customer offline, per role |
| `share/web/{skel,awstats,unassigned}/` | | assets, never selectable |
| `templates/email/` | | notification mail bodies; shipped samples plus admin overrides (#393) |

Two consequences worth knowing before touching this:

- **Selectable web templates exist where nginx itself serves the content.** The criterion is the
  role, not the model name: `templates/nginx/*` are standalone web vhosts (`root` plus a fastcgi
  handler), so they only apply where nginx is the web role. Wherever apache serves, apache decides
  the shape - there is one apache vhost - and per-domain variance runs through switches instead
  (cache, http3, hsts, offline, docker). A model that adds a front therefore inherits the answer:
  serves it itself, so it offers a choice; proxies to apache, so it does not. A form that offers
  the choice where the criterion does not hold renders an empty select, which is why the package
  form only renders the row where something is selectable (#644).
- **The role picks the directory, not the service name.** In the both model nginx is the
  proxy and renders `share/web/nginx/default.tpl`; in nginx-only the same service is the
  web role and renders `templates/nginx/default.tpl`. Both files are called `default` and
  are not interchangeable - `web_template_file` in `include/domain.sh` is the only place that
  decides, and validators and renderer both go through it.
- **`PHPTPL` is its own anchor**, not `$WEBTPL/$WEB_BACKEND`. `WEB_BACKEND` is a config
  VALUE (`php-fpm`); deriving a directory name from it would mean renaming the directory
  forces renaming the value everywhere it is compared.

Upstream keeps one flat `templates/web/<service>/<backend>/` tree with every variant
selectable, including the mod_php-era apache ones.

**Why.** Separate mutable instance state from the git-managed code tree so a tarball
extraction into `/usr/local/hestia` never clobbers config or user data. The install
root stays `/usr/local/hestia`; the only per-command change was
`source /etc/hestiacp/hestia.conf` -> `source /etc/hestia/hestia.env`.

**Follow-on.**
- `/etc/hestia` is `700 root:root`: the unprivileged `hestia` user **cannot read it**,
  so any gate that must be visible to `hestia` uses structural truth (e.g. FM socket
  existence), not a config flag (delta 5).
- `$HESTIA/conf` is a **symlink**: code that stats/replaces the dir itself must respect
  it; `sed -i` on files within is safe.
- Nothing may assume `$HESTIA/data/...`, `HESTIA_INSTALL_DIR`, or `HESTIA_COMMON_DIR`
  exists. Version/upgrade pins live in `share/manifest.json`, not
  `install/upgrade/versions/`.

---

## 9. Permanent removals as structural gaps

These are settled decisions (`README.md:53-59`, registry `CODEMAP.json` `removed`),
**never** to be reintroduced. Each leaves a plumbing gap future work must respect.

| Removed | Was | Gap to respect |
|---|---|---|
| **bind9 / DNS** (#58/#283) | ~50 `*-dns-*` commands, `templates/dns`, `edit_dns` page | No DNS zone-management code path. DNS is external/managed. Only `h-list-mail-domain-dkim-dns` kept - it formats mail-stack data for somebody else's DNS. The last leftovers went in #619: `DNSTPL`, the package fields (`DNS_TEMPLATE`/`DNS_DOMAINS`/`DNS_RECORDS`/`NS`), the `U_DNS_*` counters and `h-list-user-ns`. The firewall seed keeps the original rule ids, so **6 and 7 are absent** where upstream opens port 53 - a gap, not a missing rule. Renumbering would move every later rule, and a firewall rule id is its precedence. |
| **REST API** (#146) | `v-*-api-*`, web API endpoint, key auth | No programmatic surface. Entry points are the panel UI and `h-*` CLI only; integrations shell out to `h-*`. |
| **Web Terminal** (#59) | node sidecar service, `list_terminal` page, `/_shell/` | No browser->shell bridge; `/_shell/` absent by design. Operators use SSH. Closed GHSA-gh6f. |
| **vsftpd** (#213) | `install/deb/vsftpd` | FTP is **ProFTPd only** (`share/proftpd/`); `FTP_SYSTEM` must not branch on vsftpd. |
| **SpamAssassin / spamd** (#284) | spamd config + panel spam-editor | **rspamd is the sole filter**; `ANTISPAM_SYSTEM` has no spamassassin branch. Config targets `/etc/rspamd/`. |
| **Software Installer** (#56) | webapp catalog, Node build chain | No one-click app-install surface. Composer/WP-CLI exist as CLI tools; there is no panel installer to extend. |

---

## 10. Build / release: `.deb` + apt repo -> source tarball + CI

**Upstream.** Versioned Debian `.deb` packages (incl. compiled binaries) served from a
custom apt repository.

**HestiaRE.** No packages, no binaries - source only (`README.md:32-46`): a `v*` git
tag triggers CI (`.github/workflows/release.yml`), which stamps `VERSION` and packs the
tree into one `hestiare-<version>.tar.gz`; `install.sh` fetches + extracts it into
`/usr/local/hestia` and hands off to the wizard -> `sbin/h-install-hestia`. Source/channel
is overridable via `/etc/hestia/source.conf`. The release actually runs on the public
GitHub mirror (Gitea has no release workflow); see `project-release-github-mirror` in
memory for the full Gitea-release -> mirror -> GitHub chain. No compiled artifact, no
private repo, no build toolchain on target (the earlier `just`/Make dependency was
removed - pure bash).

**Follow-on.** `VERSION` is stamped by CI, never edited. Upstream update tooling keyed
on deb package names does not apply. The panel and its PHP are OS/Sury packages + local
wrappers (deltas 1-2), so there is no `hestia-nginx`/`hestia-php` deb to update.

---

## 11. Shared bash libraries: `func/` -> `include/`

**Upstream.** `func/` holds the sourced shell libraries, plus a `func/internal/`
subdirectory for the two PHP helpers it shells out to.

**HestiaRE.** One flat `include/`. The `internal/` subdirectory is gone.

**Why.** The directory holds sourced libraries - constants, path anchors, `source_conf`,
whole subsystems like the nftables renderer - not only functions, so `func/` named a
part for the whole. `internal/` promised a boundary nothing enforces: every file in
there is exactly as internal as the rest.

**Follow-on.** Two of these are easy to miss because nothing fails loudly when they are
wrong - they just make a check look at less:

| Anchor | What breaks if it still says `func/` |
|---|---|
| `.gitea/tools/lint-shell.sh:50` (`is_shell()`) | The regex decides which paths are shell at all. Stale = 18 libraries silently drop out of both lint tiers and the gate stays green on less. |
| `.editorconfig:29` | The `shfmt` formatting contract is matched by glob; stale = the libraries lose their tab/indent rules. |

Everything else is a plain path rewrite: `$HESTIA/include/*`, the `# shellcheck source=`
directives, and `install.sh`'s bootstrap `${INSTALL_DIR}/include/`. `web/` never
referenced the directory at all. No runtime migration exists or is needed - `h-update-hestia`
copies the tree without removing, so an updated box would keep a stale `func/` that nothing
sources; per the no-migration-before-v1 rule the answer is a reinstall, not a shim.

## 12. Backup storage: flat `/backup` (0755) -> per-customer folders (0711/0750)

**Upstream.** Every archive of every customer sits flat in `/backup` at 0755: any local
system user can enumerate customer names, backup dates and sizes.

**HestiaRE.** `/backup` is 0711 and holds one folder per customer
(`/backup/$user/$user.<date>.tar`, 0750 `hestia:$user`); the run log lives inside. The flat
level remains only as the hand-off spot for a migration archive an operator drops in by
hand, plus `server.<stamp>.tar` for box state (`h-backup-server`, #710) - `server` is a
reserved login name for that reason. Records keep bare basenames, so the backup FORMAT is
untouched and bidirectional compatibility holds: a HestiaCP archive placed at the hand-off
spot restores, and our archives restore there (#789).

**Why.** Path privacy and one rights picture per customer. One resolver in
`include/backup.sh` (`backup_archive_path`) carries the two-place rule and the symlink
containment for every reader, CLI and panel.

---

## Known inconsistencies (flagged, not yet resolved)

- Per-domain backup special-cases per-domain backend tpls (`h-backup-user`), but the FM
  pool and the panel pools are outside the per-user domain backup path (delta 2/5).
