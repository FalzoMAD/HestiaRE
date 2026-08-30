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

### Added

- **`install.sh --port=<n>` for an unattended install on a non-default panel port** (#730).
  `-a` used to force 8083, so an unattended install could not be given a port at all - and the
  refusal path could not be verified the way it has to be: start the install, watch it stop
  before the first write. Interactively the value prefills the prompt.

- **The smoke test checks the record grammar** (#866). Every record line has to be `KEY='value'`,
  measured with the one validator that already defines it. A line that loses its quotes stays
  readable - `source_conf` takes `KEY=value` - while every writer looks for `KEY='...'` and
  silently finds nothing: the value shows up correctly and no change to it ever sticks.

- **Customer PHP has a CPU cap against the rest of the box** (#212). Every customer php-fpm master
  runs in `hestia-customer-php.slice`, limited to `CUSTOMER_PHP_CPU_PERCENT` of the whole machine
  (`/etc/hestia/limits.conf`, default 75, seeded once and never rewritten by an update). It is a
  system protection, not a per-customer limit: hammered sites and runaway PHP cannot take panel,
  mail, database and ssh with them, but customers are not separated from each other. The panel PHP
  is a separate master and stays outside; the per-user filemanager pools are inside. The value is
  computed at every boot - systemd counts CPUQuota per core, so the share is multiplied by
  `nproc --all` and applied with `set-property --runtime`: nothing absolute is stored, and a box
  that gains cores grows its cap. The boot step never blocks a boot, but that is not fail-open:
  what survives a failure is the slice's fixed 200%, barely a limit on two cores and a hard sixth
  of a sixteen-core box - which is why the smoke test reports the LIVE value. Under overload the
  box now stays responsive and customer sites answer 502 instead - the intended trade, and the
  reason it is written down in STRUCTURE.md. Note for the first update of an existing box: the
  customer php-fpm masters are restarted once, because a reload cannot move a running master into
  the new slice.
- **Project quota is base behaviour** (#211). The installer arms /home whenever its filesystem
  supports it - no wizard item, no panel switch. A new PROJECT_QUOTA key carries the MEASURED
  state (active / pending:reason / none:reason), written from an enforcement probe with its own
  positive control, never from classification. The package DISK_QUOTA value becomes a hard
  project-quota limit on the customer's home tree (project id = uid), so files written by
  php-fpm, the docker companion or subuids all count against the customer - the #389 companion
  hole is closed by the mechanism, not worked around. ext4 gets a persistent quotaon boot unit
  (enforcement is runtime state) and, on a root fs, a one-shot initramfs hook across the reboot
  the installer demands anyway; xfs gets the mount option via fstab or GRUB rootflags. On a box
  without the capability the panel hides the field and every applier is inert; a restore onto
  such a box names the enforcement loss. The old admin toggle, h-add-sys-quota/h-delete-sys-quota
  and the never-verified reboot-script path are gone; the smoke test measures real enforcement
  and flags a drifted or stuck arming by its stored reason, and h-update-sys-quota re-arms a box
  out of none:* once the named reason is fixed.

### Fixed

- **The wizard's bash fallback threw away a numeric answer on every checklist** (#333). Without
  whiptail (no TTY, empty or `dumb` `TERM`) the wizard asks in plain bash, and `_wt_checklist`
  echoed the typed line unchanged while its two siblings mapped a number back to its tag. The
  grouped screens match the answer by LABEL, so a numeric one matched nothing and the whole screen -
  addons, databases - came out deselected without a warning or a log line; in the PHP list the
  digits reached `install.conf` verbatim and the installer tried to install `php2`. Numbers and
  names both work now, a token that is not on the screen is named instead of swallowed, and the
  prompt says what it does: the answer replaces the selection, it does not toggle it.

- **Wizard text no longer runs out of its box** (#333). The whiptail boxes were fixed at 72 columns,
  so a longer `label - description` was simply cut - and what vanished was the half explaining the
  option. The width follows the longest row now, between 60 and 100 columns and never wider than the
  terminal.

- **The always-installed tools were listed twice, and the manifest copy was the dead one** (#333).
  `share/manifest.json` carries `tools.always_installed`, but the installer ran a second, identical
  list hard-coded in `install_tools` - editing the manifest changed nothing. The installer reads the
  manifest now, and an empty or unreadable list says so instead of quietly installing nothing. The
  two lists were byte for byte the same, so nothing changes on an install.
- **The box handed its own system mail to a stranger** (#333). Cron reports and every panel
  notification are addressed to `root@<hostname>` or to the admin contact at `<hostname>`, and that
  is not a HestiaRE mail domain - so exim fell through to `dnslookup` and offered the mail to
  whatever host answers for the hostname, which refused it (`454 relay access denied`). Measured on
  a normally installed box: seven messages in the queue, among them three panel notifications and a
  cron report about the certificate run, hours old and invisible to anyone. exim now routes
  `root@`, `postmaster@` and the admin at this host locally, ahead of every outbound router, and the
  installer manages `/etc/aliases`: an admin email outside this host receives them, otherwise they
  land in the panel admin's mailbox on the box. `root` is always aliased away, because exim's
  `never_users` refuses to deliver as uid 0 - what looked like a working setup before was one that
  never delivered anything. The wizard's email prompt says which of the two happens. Deliberately
  not done by widening `local_domains`: that list also drives acceptance and relaying, and the box
  must not become addressable from outside - verified, an inbound `RCPT TO:<root@hostname>` is still
  refused with `relay not permitted` while a real mail address on the same box is accepted.

- **A rejected database import counted as a successful one everywhere** (#880). The import helpers
  send their client's output to `/dev/null` and hand back its exit code, and no caller looked at it.
  `h-change-database-owner` was the worst of the three: it deleted the dump and then the source
  database without ever asking whether the import had worked, so a failure lost both copies and
  still reported success. It now hands the source back, removes the half-built target and keeps the
  dump only where the source could not be handed back, naming where it is. The command also gained
  the cleanup trap its siblings already had: it was one of the two that removed their temporary dump
  directory on the straight-line path only, so `/backup` could keep a `tmp.*` directory for good. `h-restore-user` reports the database in the summary of parts that did
  not come back - the mechanism was there, the import was the one thing not wired into it, so a
  customer got an empty schema and nobody was told. `h-restore-database-restic` fails with `E_DB`,
  matching the rest of that file. The dump direction has checked itself all along (`mysql_dump`,
  `psql_dump`); only the import side never did.

- **An owner change could create a database record no command could remove** (#880). The new
  database and dbuser names are derived from the new owner's name and were never revalidated, so a
  longer owner pushed them past the length limit the validators enforce - `h-change-database-owner`
  wrote the record, and `h-delete-database` then refused it for exactly the same reason. Measured
  on a real move: the source database was deleted, the target never created, and the run reported
  success. Both derived names are now validated before anything is touched.

- **A failed database import no longer reports success** (#877). `h-import-database` never looked
  at the exit code of the client it invokes, and that client sends its own output to `/dev/null` -
  so a dump the server rejected ended in an `OK` log line over an empty database. An unrecognised
  `TYPE` fell through the same way: no branch ran and the untouched database was reported as
  imported. Both now fail with `E_DB`. The command stays: it is the counterpart to
  `h-dump-database` (which the panel's database download uses), and its value is that it resolves
  the type, host and admin credentials from the records - including a remote database host.

- **A nomail box had no MTA at all, and every notification was lost silently** (#872). `exim4` was
  installed only inside the mail stage, so without a mail block nothing installed one - the
  send-only step merely configured what it presumed to be there. It looked correct on Debian,
  whose base image ships `exim4-daemon-light`, and never worked on Ubuntu, which ships no MTA:
  password resets, backup reports and every other panel or CLI mail died in PHP's `mail()` with
  `sh: /usr/sbin/sendmail: not found` while the sender returned success. The installer now installs
  `exim4-daemon-light` for the send-only case (heavy stays with the full stack and replaces light
  if a box later gains a mail block), `COMPONENT_PANEL_EXIM` is finally read instead of only
  written, and the smoke test asserts the binary PHP will actually call - the old send-only check
  returned silently when exim was absent, which on a nomail box is the defect rather than a reason
  to skip.

- **The panel port never reached the panel** (#730). `h-change-sys-port` rewrote
  `$HESTIA/nginx/conf/nginx.conf` - a file that has not existed since the panel moved to Caddy -
  so any port but 8083 wrote `BACKEND_PORT`, the firewall rule and the password plugins while
  Caddy went on listening on the old one: the firewall open where nothing answered, the panel
  answering where the firewall was shut. It now moves the Caddy site and the listener-wrapper
  block, reads the CURRENT port from that site rather than from the config value, and re-renders
  the phpMyAdmin proxy include that every customer domain uses (the port is a `%panel_port%`
  placeholder there now, so a redeploy cannot reset it). It also proves its own result: the
  listener moves first and has to answer on the new port before `BACKEND_PORT`, the firewall and
  the proxies follow - otherwise the caddy files are rolled back and nothing else was touched. The
  installer no longer swallows a failed apply, and `h-check-sys-smoke` compares the live site
  against `BACKEND_PORT`.

- **The wizard accepted any number as the panel port** (#730). `0`, `80` and `70000` all passed,
  and so did `8090` or `8091`, where the loopback webmail listeners sit - a collision that only
  appears an hour later, when the installer brings those services up. The wizard now refuses
  before the first write, with a message naming the conflict partner. The reserved set is DERIVED
  from the shipped listener declarations under `share/` and `include/`, not written down: a
  listener added later cannot fall out of it, and a scan that finds nothing refuses rather than
  waving every port through. It is not a numeric band but about a dozen individual ports - the
  80xx of panel and web stack, and equally `3306`, `5432` and `4190`, which our own configs
  declare. Comment lines, application code and IP octets are excluded, each because a measurement
  showed them producing a wrong reservation.

- **The panel showed the version twice over** (#617). The server page printed a literal `v` in
  front of a version string that already carries one (`vv0.17.1`); the footer and the update box
  had it right. The version is now read with an anchored key, so a future `*_VERSION` key cannot
  turn the value into two lines.

- **Accounts without a contact name showed empty brackets** (#617). The user list printed `()`
  after the login whenever `NAME` was empty, in the row, the icon title and the mobile label. The
  parentheses now belong to the name, the way the top-bar menu already did it.

- **The admin's IP counter grew with every deleted customer IP** (#866). For the root user
  `IP_AVAIL` is the number of IPs on the box whoever owns them, and `h-add-sys-ip` counted it up
  for a customer-owned address - but `h-delete-sys-ip` never counted it down again, so the number
  drifted upward for the life of the box. Found by measuring the bookkeeping against the recount
  instead of reading it. `h-check-sys-smoke` now watches `IP_AVAIL`/`IP_OWNED` too; they were the
  two counters its drift guard never covered, which is why nothing noticed. A box that already
  drifted is corrected by `h-update-user-counters <user>` - nothing recounts on a schedule.

### Removed

- **The cPanel and DirectAdmin importers are gone** (#877). Both were VestaCP-era third-party
  scripts (`sk-import-cpanel-backup-to-vestacp`, `sk_da_importer`, the latter still labelled
  "Version 0.1 - provided without any warranty") that we carried along verbatim through the
  `v-*`->`h-*` rename and never touched otherwise. Nothing in the tree called them, and they parse
  a foreign archive format we hold no licence for, own no fixture of, and cannot test on any of the
  four targets - the cPanel one names its own broken parts in its header (certificate import,
  DKIM). That they had never run is visible in the code: both carried the same inverted branch, so
  a box with `BACKUP_TEMP` set - a supported knob - aborted every import with "File does not
  exist", while a nonexistent archive argument was not caught at all. Migration from HestiaCP is
  unaffected; that path is the backup format and is measured in both directions.

- **Two record keys nothing reads** (#865). `PLUGIN_APP_INSTALLER` belonged to the Software
  Installer, which is permanently gone - yet the self-healing wrote it back into every
  `hestia.conf`. `U_MAIL_SSL` was a per-user counter that no code read, no lister printed and the
  counter recount could not even verify. Registry, repair and emitters go together, as with
  `RESOURCES_LIMIT`. Existing records keep both keys; that is deliberate (#862), and inert.

- **The `csv` output format is gone from every command** (#861). It had no consumer anywhere - not
  in the tree, not on the docs branch, not in the scripts installed outside it - while every field
  change had to carry it through four listers in four formats. That nobody noticed
  `h-list-user-packages csv` emitting empty columns and the caller's own `$SHELL` as data is the
  evidence. `json` (for programs), `plain` (the CLI's own machine format, 43 call sites) and
  `shell` (for people) stay. An unknown format is now a named error instead of silence.

- **The per-user cgroup resource limits are gone** (#212). `RESOURCES_LIMIT`, the four package
  fields CPU_QUOTA / CPU_QUOTA_PERIOD / MEMORY_LIMIT / SWAP_LIMIT, the three `*-cgroups` commands
  and the "Limit System Resources" panel block never limited what a hosting box needs limited:
  `systemctl set-property` on `user-<uid>.slice` reaches the logind session (ssh, cron), while
  php-fpm workers live in the FPM service slice and escape it entirely (upstream #4659). Nothing
  to migrate - the switch was off by default and no box carried a persistent drop-in. The docker
  cap (DOCKER_LIMIT on the companion slice) is untouched and does work, as do the FPM pool
  profiles and request_terminate_timeout.

### Fixed

- **Every Sury-mode install died on a PHP-8.5 box** (#857). The PHP package filter ran only in
  the os_single branch, so the raw list went to apt in sury mode - and php8.5-opcache exists in
  no repo any more (opcache moved into core with 8.5). The filter now runs unconditionally in
  both stages: it keeps whatever the configured repos answer and names every other absence.

### Changed

- **mailonly no longer offers customer web** (#193). The preset installs the new mailfront model:
  WEB_SYSTEM stays empty - h-add-web-domain and every other web command refuse via their
  inherited guard, the panel hides the web area - while nginx keeps fronting the webmail vhosts
  and ACME under its own WEBMAIL_FRONT key. The webmail chain reads the front everywhere it used
  WEB_SYSTEM; on every other model the two are identical.
- **The fail2ban web jails key on existing logs** (#193). The gate enabled them unconditionally
  and fail2ban refuses to start over a logpath glob that matches nothing - a fresh box without
  CrowdSec died on the first fail2ban start (the prune the code commented was never written).
  The first domain arms them, the last one disarms them, both from the domain lifecycle.
- **nomail can actually send** (#192). Exim ran with Debian's default local-delivery-only config,
  so panel mail to any remote admin address was silently undeliverable; the installer now sets
  the internet type with loopback-only listeners - accept from localhost, deliver anywhere out.

- **The panel PHP version is the OS default, not a Sury pin** (#191). deb12 runs the panel on 8.2,
  deb13 on 8.4, ub24 on 8.3, ub26 on 8.5 - derived from the OS php meta at install (Sury-filtered,
  since the sury meta shadows the OS one) and recorded in install.conf and
  /etc/php/hestia/php-version. The OS-packaged panel apps (Roundcube, phpMyAdmin) now run on the
  PHP their distro actually tests them against. In sury_multi mode the packages still come from
  Sury; an OS default missing from php_supported fails loudly at the wizard.
- **singlephp keeps its promise: no Sury on the box** (#191). In os_single mode the installer skips
  the Sury repo entirely; panel and customer PHP come from the OS. Extension names the OS never
  shipped (imap from 8.4 on, resolute's built-in opcache) are dropped loudly instead of killing the
  install, cli+fpm stay mandatory. Asking h-add-web-php for a version the configured repos cannot
  install arms Sury on demand - the retrofit stays a single command.
- **Roundcube survives PHP 8.5** (#191). resolute's Roundcube 1.6.11 still declares array_first()
  unguarded and dies on a redeclare fatal against 8.5's new core function; the pool now disables
  the two natives (PHP 8.0+ semantics allow the userland redefinition), which is inert everywhere
  else and stays correct once the upstream polyfill fix reaches the package.
- **A PHP security update no longer leaves the panel on a deleted binary** (#191). The distro
  postinst only restarts its own unit; an apt Post-Invoke hook now restarts hestia-php exactly when
  its master image is gone from disk - which happens unattended once the panel runs OS PHP. The
  smoke test flags a stale master.

- **Adminer 6.0.1 and Alpine.js 3.16.3 vendored** (#851). The Adminer pin had fallen two security
  rounds behind (a 5.5.1 GHSA, the 6.0.x XSS/CSRF hardening incl. the trust-auth server lockout);
  the login-servers SSRF dropdown works unchanged under 6. Alpine 3.16 is a bugfix minor.
- **`update-web-vendor.sh --check` also watches the manifest pins** (#851). tachyon and wp-cli have
  no upstream/* branch - the installer fetches them itself against the pin - so their drift was
  invisible between release checklists. An empty pin fails instead of comparing nothing.

- **The standard and compact presets diverge again** (#850). standard now preselects the four
  newest PHP versions, Redis alongside MariaDB, both webmailers, restic and sieve; compact keeps
  the three PHP versions below the newest, fixes MariaDB to the OS default without asking, and
  preselects only CrowdSec, Fail2ban and rspamd - the utilities screen stays closed unless opted
  in. The CrowdSec mode texts got shorter.

### Fixed

- **Queued restarts died on their own grammar** (#855). Every h-restart-* writes itself into
  restart.pipe as "$SCRIPT now", but the inherited validator rejected exactly that value - and
  the queue runner swallows all errors, so with SCHEDULED_RESTART enabled every queued restart
  failed silently. 'now' is accepted now (run immediately, do not requeue).

## v0.17.0 (2026-08-27)

Closes the backup and restore program (#240): restic as a per-customer mode, differential
backups, remote targets that fail loudly, per-customer storage, and a restore that reads,
asks and reports before it writes.

### Added

- **restic is an addon, and the customer's package decides the mode** (#217).
  `h-add-sys-restic`/`h-delete-sys-restic` replace the unconditional install;
  `BACKUPS_MODE='full'|'diff'|'restic'` lives in the package, and the nightly run dispatches per
  customer. A restic run writes two artefacts that belong together - the snapshot and a metadata
  package beside the repository (records, SSL, PAM, cron, a spare copy of the repository key) -
  and retention treats them as a unit: `forget` decides over the snapshots, the packages follow
  the survivors. The restore path reads the metadata from the package; before, it read a tree no
  snapshot has carried, so every restic restore died at its first metadata read. Removing the
  addon refuses while a customer still runs in restic mode: deleting the tool must not delete
  backups. `h-delete-user-backups-restic` is the explicit, consent-worded way out,
  `h-list-sys-backup-orphans-restic` names what is left over, and `h-export-user-backup` writes
  one ordinary archive out of a restic customer - the migration artefact, exempt from rotation,
  travelling under `snappymail` instead of our `tachyon` so a foreign panel accepts it (#837).

- **Differential backups** (#712). A customer in diff mode gets archives whose web and mail
  members carry only what changed against the newest full; everything else stays whole. Every
  backup now carries a content map (path, BLAKE3 hash, mode, owner - `b3sum` joins the base
  packages), taken so a file changing mid-run is re-shipped rather than treated as covered. A
  diff member is named `domain_data.diff.tar.zst` - the name says what it is (#840) - and the
  restore refuses a diff whose base is missing or fails the recorded map hash, before the first
  write. `BACKUPS` counts SETS now, one full plus its diffs; a base is kept as long as its set
  is, because rotating the full first wiped the entire history in one run. Archives are
  byte-identical for an unchanged tree.

- **Remote backup targets fail loudly, keep more, and can hold the only copy** (#790). After
  every upload the target's fresh listing is asked whether the archive actually arrived - an
  unreachable target used to produce a green run and an archive that existed nowhere. Restore
  and panel download chain every configured transport; a degraded run keeps the local archive,
  names the failed target in log and mail, and exits non-zero after all bookkeeping. Every
  remote host takes an optional KEEP - its rotation keeps that many sets while the local one
  keeps the package's number - records outlive the local file, and a diff base may live on a
  remote only. **OPERATIONAL NOTE:** the ftp/sftp listings arrived CRLF-tainted and remote
  rotation was structurally dead; the first run against a grown target counts the accumulated
  archives for the first time and removes everything beyond retention.

- **Every customer's archives live in their own folder** (#789). `/backup/$user/$user.<date>.tar`
  replaces the flat layout; readers accept two places - the customer folder, then `/backup`
  itself as the hand-off spot for a migration archive dropped in by hand. `/backup` went from
  0755 to 0711, so local users can no longer enumerate customer names and backup dates; `server`
  joined the reserved login names; `h-download-backup` refuses a name that has no record for
  that customer. Restoring from an unrecorded archive adopts it (#820) - without a record the
  migration source counted as its own set and `BACKUPS='1'` removed it on the next run.

- **The state that belongs to the box has its own backup** (#710). Webmail databases,
  `hestia.conf`, the hosting packages and the firewall sources fit in no per-customer archive;
  `h-backup-server` takes them, `h-restore-server` puts back only components that are named and
  consented to. The SQLite webmail store on a box without a database engine is snapshotted with
  SQLite's own `.backup`, and was backed up by nothing before.

- **A restore reads, asks and reports before it writes** (#707/#708/#709).
  `h-list-backup-contents` inspects the archive FILE - a HestiaCP archive placed by hand can be
  looked at at all - and the same report runs as the restore's preflight. Consent is collected
  per section before the first write, as a prompt or a `CONSENT` argument, the panel's
  PHP-fallback choice included (#608). What cannot be put back lands in the customer's
  `~/leftovers/` next to the loss report; a section this host has no subsystem for is named,
  skipped and counts as a part that did not come back - a pgsql dump on a MariaDB-only box took
  the whole run down before. `h-add-user-backup` adopts a hand-placed archive from its members,
  and an archive says who wrote it (`hestia/origin`).

- **Sieve is reachable for customers, and moving mail to Spam trains the filter** (#780). The
  engine was installed, ManageSieve was listening, and nothing could reach it; both webmails now
  load their sieve integration. Moving a message into or out of Spam teaches rspamd through
  imapsieve, on the `Spam` folder exim actually files into; every learn is logged with the
  account that caused it.

### Security

- **The restore trusts nothing it did not write** (#705/#706/#707). An archived record must be
  exactly `KEY='VALUE'` before it joins a live config; the exclusion list goes through the
  hardened reader instead of a raw `source`; the restore selectors reach the root-executed queue
  line through a closed character set; a Vesta archive is refused by name.

- **Record values stopped being shell-expanded on their way to the panel** (#723/#728). 46 call
  sites handed records to the parsers unquoted and 53 JSON emitters spliced values into `echo`,
  so a `*` in a value globbed against the working directory and a crafted filename could open a
  second JSON key. Values travel quoted and through `printf` now.

- **A failing `mktemp` no longer lets the panel write into an unset path** (#703). Thirty save
  routes used the result unchecked; they now branch instead of writing a certificate or a
  password hash to a path built from an empty string.

### Changed

- **`check_result` refuses an empty or non-numeric error code** (#217). `E_BACKUP` was referenced
  and defined nowhere, so three guards silently never fired; the next typo of this class is a
  loud failure.

- **The backup compression level is validated where it is set** (#776). `BACKUP_GZIP` feeds two
  scales (gzip 1-9, zstd 1-19) and nothing checked either, so an out-of-range value killed every
  backup at 3 a.m.; the four competing defaults are one value now, measured at the knee.

- **The shell lint gate covers everything that is shell** (#777/#770). `sbin/` sat outside both
  tiers, so a change to the installer was answered with "no changed shell files"; the predicate
  now derives from content, a run that measured nothing fails, and the format-exempt list is empty.

- **PROVENANCE recomputed** against upstream 640220c (2026-08-25); the churn rise is our own
  backup cycle and comment rounds, not upstream movement, and the 40 compiled catalogues keep
  their pinned ref. The pins re-verified: tachyon 3.2.2 and wp-cli 2.12.0 still match their
  published assets, 8.5 is still the newest GA PHP. Tachyon released a 4.x major on 2026-08-25/26
  after six quiet weeks - deliberately not bumped, it gets its own evaluation round (#846).

### Removed

- **Demo mode** (#759). A config key that made 365 commands refuse to do anything, for a public
  demo box that will never exist here.

- **The backup pages no longer offer DNS** (#713). Zones stopped being backed up when the
  subsystem went; the panel kept the column and handlers, fed by a field the backup fills with
  nothing. The `[DNS]` argument and the empty `DNS=` record stay as HestiaCP compatibility.

### Fixed

- **A PostgreSQL database came back from a restore with its password destroyed** (#752). The hash
  was parsed out of `psql`'s aligned table - the backup took the column heading - and the bare
  `CREATE ROLE` on the way back was `NOLOGIN` on top, so the role could not log in whatever its
  password said. The hash is read as a value, an empty one never replaces a working credential,
  and a role restored without a password is named and colours the exit status.

- **A restore under a different customer name deleted the source customer's database and reported
  success** (#764). The deletion took the name out of the archive while everything else worked on
  the target's name - invisible on every same-name restore. The name now comes from the customer
  being restored into, and the ownership check sits in the delete itself.

- **Suspending a web domain switched its forced HTTPS and HSTS off for good** (#720). The rebuild
  called delete-then-add and the add half refuses on a suspended domain; unsuspending never
  brought the settings back. A suspended domain now renders the suspend template around its
  existing fragments, and a domain that was suspended when archived comes back suspended.

- **A restored web domain keeps every field it had** (#705). The record was rebuilt from a
  hand-written key list, so password protection and the newer switches did not come back - and
  the repair re-inserted them empty, so the record looked healthy. The archived line is the
  record now, edited in place. A DKIM record without its private key is a named failure instead
  of a green restore that fails every message.

- **A record value containing a quote no longer breaks the JSON the panel reads** (#704/#719).
  85 emitters escape through one function; the search commands stop emitting an escaped copy of
  the record.

- **One inconsistent record no longer stops every reload on the box** (#797/#741/#743). A docker
  domain restored without its address rendered `http://:3000`, a `CROWDSEC='yes'` domain on a box
  without the bouncer rendered a lua block nginx cannot parse - either invalidates the ENTIRE web
  configuration. Both fragments are now intent AND capability, the contradictory record is named
  and skipped, and removing CrowdSec takes its per-domain fragments with it.

- **logrotate was failed on every target since install day** (#798). Our roundcube rotation
  doubled the package's paths, which logrotate treats as an error; the package file is diverted
  now, and a smoke guard asks logrotate itself to parse the configuration.

- **An unreachable remote target failed anonymously, and the mail saying so never left the box**
  (#796). The sftp wrapper had no branch for a session that dies at once, so an empty reason was
  mailed; and the failure path ran with a deleted working directory, so exim refused to start and
  exactly the mail that reports a degraded run was dropped.

- **Removing sieve destroyed the mail server on two of four targets** (#780). Their
  `dovecot-core` depends on `dovecot-sieve`, so the purge took core, imapd and pop3d with it; the
  package stays where core requires it and only the configuration goes.

- **Every failed panel login wrote "Method not supported by crypt(3)." into the FPM log** (#817).
  The yescrypt branch handed `mkpasswd` the whole shadow hash as its salt, so "wrong password"
  read like a libcrypt defect - the one fault it would matter to see.

- **A customer whose `user.conf` lost a package limit was locked out of their own package**
  (#711). An absent limit read as zero; it now falls back to the package file, the repair seeds
  real values instead of empty ones, and duplicate keys are removed instead of only prevented.

- **Two backups of the same customer in one second silently replaced each other** (#841). In diff
  mode that is data loss - a diff can replace the very base it was built against. A run now waits
  a second right where it stamps.

- **Rebuilding a single database set the customer's database count to 1** (#757). The singular
  command inherited its plural sibling's accumulator without the flush, claiming one database's
  count and usage as the customer's total.

- **A failed addon install no longer hides behind a green installer line** (#843). Seven
  installer calls swallow their errors on purpose; the closing smoke run now recounts each
  requested addon by its artefact and names what is missing, the addon set derived from the
  installer file itself so a new one cannot ship unverified.

- **An archive from a box without a proxy no longer switches static serving off on the target**
  (#836); a webmail client the target does not offer is named instead of silently serving
  nothing (#837); a restic restore no longer erases the HTTP/3 switch (#835).

- **"Back" led to the administrator's own profile, not to the customer being managed** (#779),
  when managing without impersonation; and a long SSH key wraps instead of bursting its cell.

- Smaller inherited ones, almost all in the backup path: a home entry with a space, tab or
  backslash in its name aborted or lost the section (#706/#736), a restore under a new name
  duplicated every database record (#721) and pointed password protection into the old
  customer's home (#756), a refused restore deleted the customer's queued backup instead of its
  own line (#733), saving the exclusions page cleared the cron exclusion (#768), the restic bulk
  restore restored the wrong thing or nothing (#767), two addon installers announced work they
  had not done (#772), restored notifications and the second FTP account came back wrong
  (#713/#764), and a restore no longer reports success when a whole section could not come
  back (#754).

## v0.16.0 (2026-08-18)

Closes the webmail replacement (#584), WordPress as a domain option (#682), the panel form
reordering (#621) and the read-side hardening of the panel (#578/#649).

### Added

- **WordPress as a panel-managed web-domain option** (#682): a checkbox installs a complete
  WordPress as the customer through the pinned wp-cli - core, database, cron, credentials shown
  once - with admin login, core update and delete behind a typed confirmation. Unticking
  detaches; the site keeps running.
- **Both webmailers at once, chosen per mail domain** (#584); the `WEBMAIL` value domain is
  decided on write, so an absent client keeps its record and heals when it returns.
- **A user's hosting package travels with its backup** (#663) and is recreated on a box that
  never had it - add-only, an existing definition is the admin's.

### Security

- **A validator character class let `|` through into a `bash`-executed queue line** (#393):
  nine validators wrote `[-|\.|_[:alnum:]]`, where `|` is a member, and a backup name reached
  root's queue as a shell pipe from the panel's download form.
- **Panel-set passwords no longer land in cleartext in auth.log** (#693/#694): sudo logged every
  allowed argv; secrets now travel through 0600 tempfiles and the logging is off on both sudo
  flavors, asserted per smoke run.
- **Four panel gates decided permissively when their input was missing** (#578): an unreadable
  config left every policy key absent, and absent read as allowed; the panel answers 503 now.
  A suspended customer was served whole pages, and the logout did not rotate the session id.
- **A customer could set a control the policy had taken away** (#649): handlers read POST keys
  the form never rendered; value controls decide on the server-side gate now. Certificate
  uploads stopped trusting an unchecked `mktemp` (#682).

### Changed

- **SnappyMail is replaced by Tachyon, its fork** (#584): upstream is dormant with no
  security-patch channel for an internet-facing login. Plugins are pinned, sha256-verified
  release assets. Webmailers fall back to SQLite where MariaDB is absent, recorded at install
  time, which let mailonly stop installing a database engine at all (#656/#689).
- **Composer comes from the OS package by default** (#237), switchable live; wp-cli is a
  verified manifest pin instead of a moving build address.
- **The panel forms are reordered around what people actually change** (#621/#239).
- **`func/` is `include/`, packages live under `/etc/hestia/`, and what the panel must not
  reach moved to `sbin/`** (#4/#663/#209) - a directory boundary instead of a 213-name list.
  The panel certificate left the unreadable install root (#564).
- **A conditionally rendered control reads through the gate that rendered it** (#649)
  (`post_or_keep`/`post_checkbox`), and the panel decodes CLI results in one place (#578).
- **PHP has a format contract again** (#647): PSR-12 with tabs, formatted once. Installer
  output no longer depends on the admin's umask. MariaDB defaults to 11.8 (#656).
- **PROVENANCE recomputed** against upstream 5eb9396; the churn rise is our own formatting and
  renames, not upstream movement.

### Removed

- **The custom preset** (#195) - the standard path already asks everything relevant; beyond
  every preset means editing `install.conf` by hand. **The Backblaze B2 backend** (#696) and
  **`migrate_data_layout`** (#663), whose moves no supported update could still reference.

### Fixed

- **Adding a subdomain under an SSL domain rendered certificate-less SSL vhosts and took nginx
  and apache down** (#683): a record parse leaked the parent's keys into the add command's
  namespace. The same leak sat in mail-domain and web-alias add.
- **23 panel pages died instead of showing an empty list when a CLI call failed** (#578), and
  action pages consumed results their command never produced (#670).
- **A package could not be saved from the panel on an apache web role** (#644), and saving a
  user replaced their chosen theme (#645) - absent-control reads, both.
- **The system configuration repair never ran** (#654): `command not found`, logged as
  executed. Working, it seeded 25 absent keys, most of the `POLICY_*` set.
- **The panel never took over its own Let's Encrypt certificate** (#656): the repair key was
  registered with no repair behind it, and the fallback cron was refused over its own umask.
- **phpMyAdmin dragged apache2 onto boxes that have none** (#656), which then bound *:80.
- **Binary files were bucketed by a measurement that cannot see them** (#551): numstat's `-`
  read as 0% churn; binaries compare by hash now, catalogues pinned to their snapshot.
- Smaller inherited ones: seven calls still reached `sbin/` through `$BIN` (#209), two commands
  refused their own optional argument (#564), every rebuild on apache-only wrote to
  `/etc/nginx` over a failing version probe (#642), the FPM pools pinned a locale none of the
  targets generates (#239), the Docker disable confirmation never appeared (#621), and the
  wizard offered a pre-release PHP the installer then refused (#688).

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
