# Changelog

All notable HestiaRE changes are documented here, starting from the fork
point — a HestiaCP 1.9.6 snapshot, kept read-only in the `upstream/hestiacp`
branch (upstream's own history was dropped from this file with #307).

Maintenance rule: every larger change adds an entry to the Unreleased
section as part of its PR. Only whole minors get a section - point releases are
interim builds within a cycle and their changes appear under the minor they
belong to. On release, the section gets that version number and a new Unreleased
opens above it.

## Unreleased

_Nothing yet._

## v0.18.0 (2026-09-01)

_IPv6 through the whole stack, the panel PHP on the distribution's default, and a system-wide CPU cap for customer PHP._

### Added

- **IPv6 is first-class, and never presupposed** (#602, stages #888-#893). A box with both families
  serves both, a box with only IPv6 installs and runs, and a box whose kernel has IPv6 disabled
  stays a supported state. The IP object carries its family - a v6 keeps a prefix length in
  `NETMASK` and never a NAT address - and the family is decided by content, never by a flag: there
  is no `IPV6_SUPPORT` switch, the installer measures the box instead. One render engine serves all
  web templates: `%ip6%` substitutes raw with the brackets as template text, a repeatable line whose
  family placeholder is unfilled is deleted before substitution, and the structure-carrying lines
  (the apache `<VirtualHost>` tag, the nginx-to-apache hop) get resolved tokens. New domains take
  the default v6 automatically, existing ones at their next rebuild; `h-change-web-domain-ip6`
  moves it. Mail speaks both families with loopback lists derived from the kernel - a listed `::1`
  is fatal on a v6-less kernel, for exim's stock template and for dovecot alike - and pins the
  outgoing v6 through its own per-domain file. The addons followed: CrowdSec mesh pairs and pulls
  over v6, backup hosts and mesh peers may be bare addresses, the blocklist preset offers a v6 set.
  Because github.com has no AAAA, `install.sh` and `h-update-hestia` retry the release API, the
  tarball and the two foreign assets (wp-cli, Tachyon) through a mirror, and check that the tree
  they unpacked carries the tag they asked for. Measured on a box without any IPv4: a single-pass
  install, a default domain with an empty `IP` field, and a Let's Encrypt certificate for the panel
  issued over v6.
- **A panel session survives an address rotation it did not ask for** (#894). An IPv6 client
  changes its address by itself, inside its own /64, and the exact comparison threw admins out
  mid-session. A v6 session is pinned to that prefix now - but only in global unicast, because
  `::1`, NAT64 and v4-mapped addresses share a /64 with strangers and would make the pin a no-op.
  The login allow list takes CIDR in both families instead of exact strings, which could never hold
  a rotating client; the families never cross, and an entry that does not parse is refused where it
  is entered rather than at the next login.
- **Customer PHP has a CPU cap against the rest of the box** (#212). Every customer php-fpm master
  runs in `hestia-customer-php.slice`, limited to `CUSTOMER_PHP_CPU_PERCENT` of the machine
  (default 75). It is a system protection, not a per-customer limit: runaway PHP can no longer take
  panel, mail, database and ssh with it, but customers are not separated from each other. The value
  is computed at every boot, because systemd counts `CPUQuota` per core - so a box that gains cores
  grows its cap and nothing absolute is stored. Under overload the box stays responsive and
  customer sites answer 502 instead; the smoke test reports the value actually in force. On the
  first update of an existing box the customer masters are restarted once.
- **Project quota is base behaviour** (#211). The installer arms /home wherever the filesystem
  supports it - no wizard item, no panel switch - and `PROJECT_QUOTA` records the MEASURED state
  from an enforcement probe. The package `DISK_QUOTA` becomes a hard limit on the customer's home
  tree (project id = uid), so files written by php-fpm, the docker companion or a subuid all count
  against the customer. Where the capability is missing the panel hides the field, every applier is
  inert, and a restore onto such a box names the enforcement loss.
- **`install.sh --port=<n>` for an unattended install on a non-default panel port** (#730). `-a`
  used to force 8083, so an unattended install could not be given a port at all; interactively the
  value prefills the prompt.
- **The smoke test checks the record grammar** (#866). A record line that loses its quotes stays
  readable for `source_conf` while every writer looks for `KEY='...'` and silently finds nothing -
  the value displays correctly and no change to it ever sticks.

### Changed

- **The panel PHP is the distribution's default, not a Sury pin** (#191). deb12 runs the panel on
  8.2, deb13 on 8.4, ub24 on 8.3, ub26 on 8.5, so the OS-packaged panel apps run on the PHP their
  distro tests them against. `singlephp` now keeps its promise and installs no Sury repo at all;
  asking `h-add-web-php` for a version the configured repos cannot serve arms Sury on demand. Two
  consequences came with it: Roundcube survives PHP 8.5 (its unguarded `array_first()` would die on
  a redeclare fatal), and a PHP security update no longer leaves the panel on a deleted binary -
  an apt hook restarts `hestia-php` exactly when its master image is gone from disk.
- **`mailonly` installs a mail front instead of a crippled web stack** (#193). `WEB_SYSTEM` stays
  empty, every web command refuses through its inherited guard and the panel hides the area, while
  nginx keeps fronting the webmail vhosts and ACME under its own `WEBMAIL_FRONT` key. The fail2ban
  web jails now arm with the first domain and disarm with the last: they were enabled
  unconditionally, and fail2ban refuses to start over a logpath glob that matches nothing.
- **`nomail` can actually send** (#192). Exim ran with Debian's local-delivery-only default, so
  panel mail to a remote admin address was silently undeliverable.
- **`standard` and `compact` diverge again** (#850). standard preselects the four newest PHP
  versions, Redis, both webmailers, restic and sieve; compact takes the three below the newest,
  fixes MariaDB to the OS default and preselects only CrowdSec, fail2ban and rspamd.
- **Adminer 6.0.1 and Alpine.js 3.16.3 vendored** (#851). The Adminer pin had fallen two security
  rounds behind. `update-web-vendor.sh --check` now also watches the manifest pins (tachyon,
  wp-cli), which have no upstream branch to compare against and were invisible between checklists.

### Removed

- **The cPanel and DirectAdmin importers are gone** (#877). VestaCP-era third-party scripts we
  carried verbatim through the rename and never touched: nothing called them, they parse a foreign
  archive format we own no fixture of, and both carried an inverted branch that made every import
  abort. Migration from HestiaCP is unaffected - that path is the backup format, measured in both
  directions.
- **The per-user cgroup resource limits are gone** (#212). `RESOURCES_LIMIT`, the four package
  fields, the three `*-cgroups` commands and the panel block never limited what a hosting box needs
  limited: `set-property` on `user-<uid>.slice` reaches the logind session while php-fpm workers
  live in the FPM slice and escape it (upstream #4659). The switch was off by default, so there is
  nothing to migrate.
- **The `csv` output format is gone from every command** (#861). It had no consumer anywhere, while
  every field change had to be carried through four listers in four formats. `json`, `plain` and
  `shell` stay; an unknown format is a named error now.
- **Two record keys nothing reads** (#865): `PLUGIN_APP_INSTALLER` from the removed Software
  Installer, which the self-healing kept writing back, and the unread `U_MAIL_SSL` counter.
  Existing records keep both, inert.

### Fixed

- **The box handed its own system mail to a stranger** (#333). Cron reports and panel notifications
  are addressed to `root@<hostname>`, which is not a mail domain here - so exim offered them to
  whatever host answers for the hostname, which refused them. Measured on a normal box: seven
  messages stuck in the queue, hours old and invisible. Exim routes `root@`, `postmaster@` and the
  admin at this host locally now, and the installer manages `/etc/aliases`; the box stays
  unaddressable from outside, which is why `local_domains` was deliberately not widened.
- **A nomail box had no MTA at all, and every notification was lost silently** (#872). `exim4` was
  installed only inside the mail stage. It looked right on Debian, whose base image ships one, and
  never worked on Ubuntu: password resets and reports died in PHP's `mail()` while the sender
  reported success.
- **A rejected database import counted as a successful one** (#880, #877). The import helpers send
  their client's output to `/dev/null` and hand back an exit code nobody read. `h-change-database-owner`
  deleted the dump and then the source database without asking whether the import had worked; it now
  hands the source back and keeps the dump where it cannot. `h-restore-user` reports the database in
  its summary of parts that did not come back, and `h-import-database` fails instead of logging `OK`
  over an empty schema. An owner change could also derive names past the length limit, writing a
  record `h-delete-database` then refused to remove.
- **The panel port never reached the panel** (#730). `h-change-sys-port` rewrote a file that has not
  existed since the panel moved to Caddy, so any port but 8083 left the firewall open where nothing
  answered and the panel answering where the firewall was shut. It moves the Caddy site now, proves
  the new port answers before anything else follows, and rolls back otherwise. The wizard refuses a
  port that collides with a shipped listener - derived from the declarations under `share/` and
  `include/`, so a listener added later cannot fall out of the set.
- **A v6 panel login was neither logged nor bannable** (#888). `h-log-user-login` validated its
  address as IPv4-only, so no v6 login reached the auth log and the failure classes it feeds to
  fail2ban (2FA, disabled login, IP allowlist) were invisible for v6 clients. Six naive `HTTP_HOST`
  splits went with it, which had silently disabled the phpMyAdmin-over-IP guard for a bracketed host.
- **An installer re-run emptied `hestia.conf`** (found while installing a v6-only box). The seed
  truncated the file on every start of `install.sh` while completed stages skip, so a resumed
  install - which the installer's own error message invites - left the box without `WEB_SYSTEM`,
  and every web command refused on a box that has a web server.
- **Every Sury-mode install died on a PHP-8.5 box** (#857). The package filter ran only in the
  os_single branch, and `php8.5-opcache` exists in no repo any more (opcache moved into core).
- **The wizard's pre-questions were described in the manifest and hard-coded in the code** (#886).
  Two copies that had already drifted - different ids, a different question text, `8083` in three
  places - and editing the manifest changed nothing. Asker and writer walk the same list now.
- **The admin's IP counter grew with every deleted customer IP** (#866). `h-add-sys-ip` counted
  `IP_AVAIL` up for a customer-owned address and `h-delete-sys-ip` never counted it down. The smoke
  test watches `IP_AVAIL`/`IP_OWNED` now; a drifted box is corrected by `h-update-user-counters`.
- Smaller inherited ones: the wizard's bash fallback dropped a numeric answer on every checklist and
  silently deselected the whole screen (#333), its text was cut at 72 columns (#333), the
  always-installed tool list existed twice with the manifest copy dead (#333), the panel printed the
  version twice over and empty brackets after a nameless account (#617), and every queued restart
  failed silently because the validator rejected the value the restart commands write (#855).

## v0.17.0 (2026-08-27)

_The backup cycle: restic as an addon, differential backups, remote targets that fail loudly, and a restore that reports before it writes._

### Added

- **restic is an addon, and the customer's package decides the mode** (#217/#240). `BACKUPS_MODE`
  per package (`tar` or `restic`), the repository and its retention configured once for the box.
  A restic backup deduplicates against previous snapshots instead of writing a new full archive
  every night.
- **Differential backups** (#342). A `.diff.` member carries only what changed against the last
  full archive, with the full one kept as its base; the restore resolves the chain.
- **Remote backup targets fail loudly, keep more, and can hold the only copy** (#240). An
  unreachable target is an error with a name, not a silent skip; `BACKUP_KEEP` counts remote
  archives separately, and a box may keep its archives only remotely.
- **Every customer's archives live in their own folder** (#240), 0711/0750, so one customer's
  listing cannot show another's.
- **The state that belongs to the box has its own backup** (#240): `h-backup-sys` writes the
  instance configuration, the panel's own certificates and the firewall state.
- **A restore reads, asks and reports before it writes** (#240). It lists what the archive
  contains, refuses what this box cannot serve, and names every part that did not come back
  instead of ending green over a half-restored customer.
- **Sieve is reachable for customers, and moving mail to Spam trains the filter** (#331).
- **Demo mode** (#772): a switch that hides destructive actions for a demonstration box.

### Security

- **The restore trusts nothing it did not write** (#240, GHSA-2xw3). A crafted archive could
  inject shell into the executed restore queue; every value that reaches it is validated now.
- **Record values stopped being shell-expanded on their way to the panel** (#386, GHSA-8w7m/w3mx).
- **A failing `mktemp` no longer lets the panel write into an unset path** - files that would have
  landed in the filesystem root, world-readable.

### Changed

- **The shell lint gate covers everything that is shell** (#477), in two tiers, judging regressions
  rather than inherited debt.
- **The backup compression level is validated where it is set**, not where it is used.
- **PROVENANCE recomputed** against the current upstream snapshot; `source_type` reseeded from the
  fresh numbers.
- The backup pages no longer offer DNS.

### Removed

- `check_result` refuses an empty or non-numeric error code instead of exiting 0 on one.

### Fixed

- **A restore under a different customer name deleted the source customer's database** (#240). The
  worst of the round: the remap wrote the new name into the record but the delete path still had
  the old one.
- **A PostgreSQL database came back from a restore with its password destroyed** (#240).
- **Suspending a web domain switched its forced HTTPS and HSTS off for good** (#240) - unsuspending
  did not bring them back, because the suspend template had overwritten the record.
- **A restored web domain keeps every field it had** (#240). The merge takes the archived record as
  its base, so a field this code has never heard of survives a restore.
- **An unreachable remote target failed anonymously, and the mail saying so never left the box**
  (#240).
- **logrotate was failed on every target since install day** (#331) - one stanza with a missing
  brace, so nothing rotated.
- **Removing sieve destroyed the mail server on two of four targets** (#331).
- **Every failed panel login wrote "Method not supported by crypt(3)." into the FPM log** (#438).
- Smaller inherited ones: a record value containing a quote broke the panel's JSON, one
  inconsistent record stopped every reload on the box, a customer whose `user.conf` lost a package
  limit was locked out of their own package, two backups in the same second replaced each other,
  rebuilding a single database set the customer's database count to 1, a failed addon install hid
  behind a green installer line, an archive from a box without a proxy switched static serving off
  on the target, and "Back" led to the administrator's own profile instead of the managed customer.

## v0.16.0 (2026-08-18)

_Webmail replaced, WordPress as a domain option, and the read side of the panel hardened._

### Added

- **WordPress as a panel-managed web-domain option** (#682): a checkbox installs a complete
  WordPress as the customer through the pinned wp-cli, with core update and delete behind a typed
  confirmation. Unticking detaches; the site keeps running.
- **Both webmailers at once, chosen per mail domain** (#584).
- **A user's hosting package travels with its backup** (#663) and is recreated where it is missing.

### Security

- **A validator character class let `|` through into a `bash`-executed queue line** (#393): nine
  validators wrote `[-|\.|_[:alnum:]]`, where `|` is a member, so a backup name could reach root's
  queue as a shell pipe from the panel's download form.
- **Panel-set passwords no longer land in cleartext in auth.log** (#693/#694): secrets travel
  through 0600 tempfiles, and the smoke run asserts it per box.
- **Four panel gates decided permissively when their input was missing** (#578): an unreadable
  config left every policy key absent, and absent read as allowed.
- **A customer could set a control the policy had taken away** (#649): handlers read POST keys the
  form never rendered.

### Changed

- **SnappyMail is replaced by Tachyon, its fork** (#584): upstream is dormant, with no
  security-patch channel for an internet-facing login. Plugins are sha256-pinned release assets.
- **Composer comes from the OS package** (#237), and wp-cli is a verified manifest pin instead of a
  moving build address.
- **`func/` is `include/`, packages live under `/etc/hestia/`, and what the panel must not reach
  moved to `sbin/`** (#4/#663/#209) - a directory boundary instead of a 213-name list.
- **PHP has a format contract again** (#647): PSR-12 with tabs. The panel forms were reordered
  around what people actually change (#621/#239), and MariaDB defaults to 11.8 (#656).

### Removed

- **The custom preset** (#195), **the Backblaze B2 backend** (#696) and **`migrate_data_layout`**
  (#663), whose moves no supported update could still reference.

### Fixed

- **Adding a subdomain under an SSL domain rendered certificate-less SSL vhosts and took nginx and
  apache down** (#683): a record parse leaked the parent's keys into the add command's namespace.
- **23 panel pages died instead of showing an empty list when a CLI call failed** (#578).
- **The system configuration repair never ran** (#654): `command not found`, logged as executed.
  Working, it seeded 25 absent keys.
- **The panel never took over its own Let's Encrypt certificate** (#656).
- **phpMyAdmin dragged apache2 onto boxes that have none** (#656), which then bound *:80.
- Smaller inherited ones: seven calls reached `sbin/` through `$BIN` (#209), every rebuild on
  apache-only wrote to `/etc/nginx` (#642), the FPM pools pinned a locale none of the targets
  generates (#239), and the wizard offered a pre-release PHP the installer then refused (#688).

## v0.15.0 (2026-08-13)

Closes the template restructuring (#219) and the Docker series (#389/#566), and takes the
read side of the object accessors with it.

### Added

- **Docker per customer, from the daemon to the domain** (#389/#566/#592/#618/#619): a
  companion account running a rootless daemon on its own loopback /24, a per-domain switch that
  makes the front proxy to the container, per-customer separation as rendered nft rules, and the
  resource cap on the companion's systemd slice.
- **HTTP/3 as a per-domain switch** (#613), offered only where nginx has `http_v3`;
  **suspension, offline and proxy caching render from `share/`** on any template (#586/#587);
  **panel uids come from a dedicated band** (#388); **DNSBL management from the CLI** (#555).

### Changed

- **A template is one file, and a domain has one vhost config** (#593): the `.tpl`/`.stpl`
  divergence class is gone, and a HestiaCP two-file backup restores as one merged vhost.
- **The PHP version is its own field** (#591): `BACKEND` carries only the pool profile, and a
  restore aborts before the first write when the archived version is not installed.
- **`templates/` holds only what somebody chooses** (#588/#589/#590); every write maps legacy
  values through `accept_web_template` with their side effects.
- **The web model decides the install scope** (#639): apache-only means no nginx on the box;
  mail-only keeps one for webmail and ACME, an exception carried by the model.
- **An install stage is only skipped for the answers it ran with** (#636).

### Removed

- **The DNS leftovers** (#619): templates, counters and records, out of packages and listings.
  The DKIM record view stays.

### Fixed

- **Object reads matched a domain as a regular expression** (#594): with `a.b.com` and
  `aXb.com` on one box, reads and writes could land on the other's record. Literal now, across
  nine accessors and 54 call sites.
- **HSTS did nothing on an apache front** (#638): the fragment carried nginx syntax and no
  apache template included it.
- **A dead SnappyMail mirror produced a green install with no webmail** (#573): an unbounded
  download and no `set -e`.
- **Backup retention could delete another user's archives** (#556); restic restored only the
  first of a multi-object selection (#555); a failing CLI call took the login page down (#575);
  the panel served its own includes over HTTP (#554) and trusted a client-controlled realip
  header (#553).
- Smaller inherited ones: an alias owned by another customer was never refused (#601), a user
  named after a service died at `groupadd` (#625), a stale LE account key failed forever
  (#555), the ip domain counter drifted per backup-restore cycle (#599), a domain acting as a
  regex could delete another customer's cache zone (#583), and a missing template wrote a
  silent 0-byte vhost (#586).

## v0.14.0 (2026-08-06)

The firewall round: one nftables table, fail2ban as a removable addon, and CrowdSec as a
three-way model.

### Added

- **The firewall renders as one nftables `inet` table** (#495/#481), IPv4 and IPv6 together, behind
  a seam that keeps the invariants when the renderer changes - with layer-7 jails so a fail2ban-only
  box has real web coverage, curated IP blocklists on a systemd timer, and smoke guards on the
  datapath, because a running daemon is not a loaded ruleset.
- **fail2ban is a removable addon** (#497) and **the model is switchable at runtime** (#498):
  fail2ban only, CrowdSec only, both, or neither.
- **The whitelist is a first-class object** (#495/#496) - `excludes.conf` only suppressed *new* bans
  and left existing ones in place. Panel surfaces for jail status, ban lists and manual bans came
  with it (#496/#527/#482), and IPv4/IPv6 parity throughout (#496/#536/#545/#548).

### Security

- **The webmail loopback listeners are restricted to the connecting UID** (#507), and the webmail
  vhost overwrites the client-IP headers it forwards (#515), so a client cannot spoof the address a
  ban is written for.
- **`source_conf` no longer executes code smuggled into a config key** (GHSA-xffx-jj33-p2px class).
- **Ten panel controllers checked CSRF before the role** (#496) - both guards worked, but the order
  decides which one an attacker gets to probe. CrowdSec's credential files are 0600 (#494).

### Fixed

- **Restarting the firewall from the panel destroyed the ruleset** (#496): the service row fell
  through to `systemctl restart nftables`, which loads the distro ruleset over ours.
- **CrowdSec was never installed by a fresh install** (#186): the gate read config keys the
  installer shell cannot see - `wcv` writes, it does not export.
- **fail2ban had been installing a config it could not start** (#496), a fresh install aborted
  silently in its stage (#520), a restart wiped the persistent banlist (#496), and the firewall
  broke IPv6 by dropping ICMPv6 (#534).
- **`is_format_valid` failed silently when a name matched no variable** (#496) - it validates by
  variable name, so a typo passed everything.
- Smaller ones: a live web-model switch left the fail2ban web jails watching the old log dir (#537),
  fail2ban and CrowdSec doubled up in the combined model (#542), and the panel answered plain HTTP
  with a bare 400 (#547).

### Changed

- **`iptables` and `ipset` are no longer installed** (#548) - nothing has called either since the
  nftables renderer landed - and `FIREWALL_SYSTEM` reads `nftables` (#495), because the value names
  the backend.
- **Adding, renaming or restoring a web domain tells fail2ban about its log** (#496), and CrowdSec
  is one three-way model question instead of two (#186).

### Removed

- **The mysqld jail** (#496) - 3306 is not in the shipped ruleset - and the UA-based `web-badbots`
  jail (#531), because user-agents are trivially forged.

## v0.13.0 (2026-08-03)

### Added

- **CrowdSec** (#186) - an nginx-gated, removable addon in four layers (local decisions, CAPI,
  a fleet mesh, and an L3 feeder), offered in the wizard as one three-way choice.
- **Server-native web bot rate-limiting** (#482) - `include/botpolicy.sh`, nginx `limit_req` or
  apache `mod_qos`, independent of CrowdSec so a box without it still throttles bots.
- **Shell lint gate** (#477), check-only, two tiers - both judging regressions rather than the
  ~240 inherited findings.

### Security

- The user editor blocks a non-`ROOT_USER` admin from modifying the `ROOT_USER` account on the
  POST path, not only in the view.
- Panel notifications are HTML-sanitized before storage (upstream #5548 / GHSA-3g4r-pfpf-8697).
- Restore scheduling no longer lets an argument inject into the executed restore queue.
- The admin debug panel escapes its variable output (upstream #5550).

### Fixed

- An optional component could end up flagged on with its package absent (#480).
- `h-list-sys-php` listed the isolated panel FPM pool as a pseudo-version `hestia` (#464).
- The web-model switch rolls back with `reload-or-restart`, so a failure cannot leave the box with
  no web server (#120, #466).
- Directory listing works under nginx-only (#468) - it only ever flipped apache's `Options Indexes`.
- A `"` or `\` in a certificate issuer broke the mail-SSL JSON (#471, upstream #5524).
- A disabled bot family left dangling zone references, breaking `nginx -t` box-wide (#482).
- Re-adding CrowdSec no longer fails on its saved state (#186).

### Changed

- PROVENANCE recomputed for all three folders against `upstream/hestiacp@ca19b9f`.

### Removed

- The orphaned bind9/named and vsftpd server-config views (#471) - both permanent ground-rule
  removals, and the vsftpd one called a command that does not exist.
- 36 app-specific web templates (72 files) seeded by the removed Software/App Installer.

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
  one shared core (`include/web-model.sh`); the model is derived from the configured
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

The headline: the **file manager** is rebuilt per-customer (the kernel UID is the isolation boundary),
ClamAV and ProFTPD join the modular addons, and a round of security hardening lands - impersonation
drops admin privilege, and the GHSA-* advisories against the 1.9.6 fork point are fixed.

### Breaking / Upgrade notes

- The `install/` tree is dissolved and `HESTIA_INSTALL_DIR` retired (#119). No live installs pre-v1,
  so no migration path.
- File manager rebuilt (#218/#419), replacing FileGator + the SFTP-loopback connector. It runs in a
  per-customer php-fpm pool **as the customer**, reached via Panel-Caddy `/fm/` -> `forward_auth` -> a
  private loopback listener; enablement is the per-user `FILE_MANAGER` flag. All FileGator plumbing is
  gone. No migration path.
- The SFTP jail no longer uses `/srv/jail` (#413) - it is built per session under `/run/hestia/jail`
  by `pam_namespace`. Fresh installs get this automatically.
- The system removal verb is unified: `h-remove-sys-*` -> `h-delete-sys-*` (#123), restoring
  `v-delete-*` cherry-pick parity. Personal scripts calling the old names must be updated.
- ProFTPD installs now record `FTP_SYSTEM=proftpd` (#123) - it was never set before. Pre-existing
  installs keep it empty until re-run through `h-add-sys-proftpd`.

### Added

- File manager - vendored TinyFileManager, put on a diet (#218). No external CDN (GDPR/offline/CSP):
  jQuery, Bootstrap-JS, DataTables, Dropzone and Ace are replaced by vanilla JS plus a small
  Bootstrap-compatible shim, a native chunked uploader, native table filter/sort and a Prism-overlay
  editor; Bootstrap-CSS and Prism are vendored, FontAwesome comes from the panel's own copy. The panel
  light/dark theme drives the FM, and in-page media streams through PHP (the customer home is not
  web-served). Enabled **per user from Edit User** (admin-only checkbox). The vendor `--check` gate
  mechanically rejects any external `http(s)` reference (#434).
- `h-add-sys-clamav` / `h-delete-sys-clamav` - ClamAV mail antivirus as a modular addon (#123). Wires
  bidirectional exim<->clamav group access and **arms the exim `CLAMD` macro only once clamd answers on
  the socket**: `defer_ok` is fail-open, so an armed-but-blind macro would pass mail *unscanned*. Never
  preselected (the signature DB is 1-2 GB). Delete keeps saved state. Verified on all four distros.
- `h-add-sys-proftpd` / `h-delete-sys-proftpd` - ProFTPD becomes a fully removable addon (#123), with
  the curated config finally live (it was orphaned under `install/`, so the distro default was in
  effect). Cross-distro package set (`proftpd-basic` is bookworm-only, TLS split into
  `proftpd-mod-crypto`), an explicit `mod_tls` gate (its absence silently disables FTPS) and an
  AppArmor override for Ubuntu 26.
- SSH `AllowUsers` allowlist co-maintenance (#412/#413), defense-in-depth. The installer seeds a
  **commented (inert)** line; user and domain-FTP hooks keep it in sync via `manage_sshd_allowusers`,
  which edits only the account's own token (operator entries survive), validates with `sshd -t` and
  re-comments rather than leaving an active line empty (lockout guard).
- The SFTP jail is rebuilt on `pam_namespace` (#413). Per session a private tmpfs is mounted on
  `/run/hestia/jail` and an init builds the jail at the **fidelity path**, bind-mounting the real home
  - one generic rule serving both panel users and domain-FTP sub-accounts, whose home sits deep under
  `web/<domain>` where native chroot cannot follow. Fail-closed rides on sshd's own `safely_chroot()`:
  `chmod 755` is the last action, so any failure leaves the root world-writable and sshd refuses the
  session. No persistent state. Verified on OpenSSH 9.2-10.2 across all four distros.

### Changed

- SSH-access shells are now a curated allowlist (#412): `nologin` (default), `jailbash` (bwrap
  sandbox), `bash`, `sh`, intersected with `/etc/shells`. Existing off-allowlist shells are preserved,
  so saving a form unchanged never resets them. Fixes an unquoted `grep -w` that let a bare `bash`
  validate against `/bin/bash`.
- Vendored Adminer 5.4.4 -> 5.5.0 - it is vendored precisely because every target distro ships a
  CVE-affected version (#350). The SSRF-hardening `login-servers` plugin is re-pinned (#356).
- Curated assets moved out of the legacy `install/` tree (#119, no behaviour change): webmail vhost
  templates, `dhparam.pem`, the logrotate fragments and the bubblewrap assets.
- Removed the shared `www.conf` PHP-FPM pool (#397, #119). Every domain already runs its own pool, so
  the server-wide one had no serving role - but its apache catch-all *executed* unclaimed `.php` as the
  `caddy` user unconfined. Unclaimed `.php` is now denied and re-granted per vhost, so it returns 403
  instead of running in a shared context or being served as source.

### Fixed

- Panel file downloads - backups, database dumps and site archives were broken on the Caddy-fronted
  panel (#441/#443). They emitted `X-Accel-Redirect`, which Caddy served as the `caddy` user, which
  cannot read customer-owned files -> 404. They now stream via PHP `readfile()` from the panel pool,
  traversal-guarded and hardened for GB scale (buffers drained, 8 KB chunks, client disconnect frees
  the worker). A single `Range:` request is honoured for the stored backup only; a multi-range list
  (the amplification vector) falls back to the whole file.
- File manager (#218/#434): a 403 for every request on **apache-only** installs - the secret gate had
  to move into `<FilesMatch \.php$>`, where the #397 deny fallback otherwise wins; the native shim
  regained the keyboard accessibility Bootstrap-JS provided; and suspending a user now also cuts FM
  access, which `usermod --lock` never touched because the FM runs over an FPM socket.
- `update_user_value()` silently dropped a key on the **last line** of `user.conf` (#433): it deleted
  the line then inserted before the same number, which is past EOF after the delete. Fixes the shared
  helper for all ~20 callers.
- Roundcube webmail returned HTTP 500, `Class "DOMDocument" not found` (#402). The `dom` extension had
  been dropped by an audit that missed the webmail pools moved onto the same FPM master (#205).
- MariaDB install aborted on Ubuntu 26.04 (#387): its enforced `mariadbd` AppArmor profile comments out
  `capability dac_override`, which the bootstrap `mariadbd` needs for first-init, so the schema was
  never created. The profile is now unloaded for the init step only and re-enforced immediately after.
- The AV/spam columns in `list_mail.php` gate on `ANTIVIRUS_SYSTEM`/`ANTISPAM_SYSTEM` (#123) instead of
  showing a misleading green check from the stored per-domain value.
- AllowUsers co-maintenance edited the wrong line (#412) - the regex matched the seeded guidance
  comment, appending the username to the prose.
- Panel Caddy failed to come up on fresh installs: a stray `||` continuation had turned the
  unconditional `Caddyfile` copy into the failure branch of a `chown` that never fails, so Caddy kept
  serving the distro default. Also `h-restart-service hestia` now maps to the real `caddy hestia-php`
  pair.
- Webmail degrades safely when the selected client is not installed (#119). Also: the PHP-version regex
  now survives a two-digit major, and the installer no longer blanket-creates a `v-*` alias for every
  `h-*` (#123), which only minted orphans for HestiaRE-native commands.

### Security

- Impersonation ("login as") now **drops admin privilege** while acting as a customer (#438).
  Previously `userContext` stayed `"admin"` throughout, so all 161 admin-only gates remained reachable
  - a same-origin script in an impersonation session could drive admin endpoints. `userContext` is now
  the **effective** role and a durable `adminContext` holds the real one; the session id is regenerated
  at both transitions, so a captured id cannot regain admin. **Side effect:** another tab sharing the
  session is logged out at the switch. Scope note: this shrinks the reachable surface, it does not draw
  a privilege boundary - the panel process runs as `hestia` and may call any `h-*`.
- File manager media handler - panel-origin XSS hardened (#218/#432). `?media=` now derives
  `Content-Type` **only** from a server-side extension allowlist, forces everything outside it -
  **SVG included** - to `application/octet-stream` + attachment, and always sends `nosniff` plus CSP
  `default-src 'none'; sandbox`. Previously `finfo` sniffing let a customer's `evil.svg` run script
  under the panel session, including an admin's via "login as". Caddy now strips all inbound
  `X-Hestia-*` before setting the trusted ones.
- GHSA advisories fixed (#386, all at or below our 1.9.6 fork point, verified against code):
  **GHSA-fcq6** authenticated admin takeover - a gate compared against an undefined `$ROOT_USER`
  (always false), so any authenticated user could rewrite the panel service config + privileged
  crontab. **GHSA-8w7m** SQL injection via the database password, interpolated raw into `IDENTIFIED
  BY`. **GHSA-cr7q** root RCE via `eval` in the object search commands. **GHSA-5fpv** cron parsing
  hardened (defense-in-depth; the RCE sink was already closed) - note `read -r` preserves backslashes
  the old `read` stripped. **Not affected, verified against code:** GHSA-w3mx (double-eval, empirically
  refuted against the rebuilt parser), GHSA-gh6f (web terminal removed), GHSA-73p3, GHSA-fg7j,
  GHSA-47mf. `h-check-sys-smoke` gained static invariant gates for the fcq6 and cr7q fixes.

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
  `include/upgrade.sh` (#197)
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
