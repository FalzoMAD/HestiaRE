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

### Fixed

- **The panel certificate is requested at the end of the install, not only after a reboot** (#656).
  It was scheduled as an `@reboot` cron that deletes itself, so a box that is never rebooted never
  got one - measured on a public install where the cron file was still sitting there untouched
  while Caddy served the self-signed certificate. Everything ACME needs is in place by that point
  in the install: the hostname's web domain exists and the web server has just been restarted. The
  cron is written only when the immediate attempt fails, so a box without public DNS yet still gets
  its retry, and a reboot after the install stays a recommendation rather than a requirement.
- **The panel never took over its own Let's Encrypt certificate** (#656). `UPDATE_HOSTNAME_SSL` has
  been in the key registry since the fork with no repair block behind it, so it was absent on every
  box - and both readers gate on `== "yes"`, which an absent key never is. `h-add-web-domain-ssl`
  and `h-update-letsencrypt-ssl` therefore skipped the handoff in silence. Measured on a public
  box: LE issued for the hostname, the certificate sat in the user's domain directory, and Caddy
  went on serving the self-signed one from install day; setting the key and re-running
  `h-update-host-certificate` switched it over at once. Same class as the empty-value keys of #654,
  for a key that had no default anywhere to begin with.
- **phpMyAdmin dragged apache2 onto a box that has no apache2** (#656). Its unversioned `php-*`
  dependencies resolve to `libapache2-mod-phpX` on some targets, which Depends on apache2 - and
  HestiaRE never uses that apache2, it only binds `*:80`, after which nginx cannot bind its own
  `:80`/`:443`. Measured on a fresh Ubuntu 26.04 mailonly install: apache2 arrived with phpMyAdmin,
  nginx failed with `EADDRINUSE`, nothing answered on 443 - so the box had no webmail vhost and no
  ACME termination, and the smoke check reported it. Ubuntu 24.04 resolved the same dependencies
  without apache2, so it cannot be decided per release. The install now refuses apache2, but only
  when it is not already there: passing that on an apache or both model would ask apt to remove the
  web server.

### Changed

- **The mailonly preset asks nothing about databases** (#656). MariaDB is installed silently from
  the OS repositories, because Roundcube keeps a database there and nobody else ever touches it;
  PostgreSQL, Redis and phpMyAdmin are off without a question. The whole database screen therefore
  disappears from that preset.
- **The mailonly preset stops offering what a mail box has no use for** (#656): Composer, Docker,
  the file manager and phpMyAdmin. All four were already off by default there; now they are not on
  the screen at all, and each stays installable by hand afterwards. phpMyAdmin was the interesting
  one - it is *derived* from the MariaDB choice, and MariaDB is genuinely needed on mailonly because
  Roundcube keeps a database. So the derived type learned to honour a per-preset opt-out. The file
  manager points at `/home/$user`, which on a mail box is the raw maildirs: a second way into the
  mailbox with no IMAP semantics, where a deleted file is a lost mail. Exporting mailboxes that way
  is a real use case, which is why it stays installable rather than being removed.
- **Composer and Docker are no longer offered on the mailonly preset** (#656). Neither has anything
  to serve on a box with no customer web, both were already defaulted off there, and both stay
  installable by hand afterwards - the same reasoning CrowdSec already carries. The file manager is
  still offered and is a separate question.
- **MariaDB installs 11.8 by default** (#656) on the standard and nomail presets, up from 11.4.
  11.4 stays selectable because Magento 2.4.9 is approved against it.

### Fixed

- **The system configuration repair never ran** (#654). `h-repair-sys-config` sources only
  `func/main.sh`, which does not pull in `func/syshealth.sh`, so both of its modes answered
  `command not found` - and then logged the repair as executed. It was the only command calling a
  `syshealth_*` function without the source line every other one has. With it working, a running
  box gained **25 absent keys**, most of the `POLICY_*` set among them; those reached the panel as
  `""`, which reads as the permissive side at the gates that consume them. The installer now runs
  the repair as its last configure step, so a fresh box gets the whole set from one place.
- **A config key holding no value counted as present** (#654). `check_key_exists()` greps `^KEY=`,
  so `KEY=''` matched and the repair was skipped. An empty value is repaired now - but only where
  the block's own default is not empty, which excludes the nine keys that default to `''` on
  purpose without naming them anywhere. Two keys are exempt because a `h-delete-sys-*` empties them
  deliberately (`DB_PMA_ALIAS`, `WEBMAIL_SYSTEM`): repairing those would re-register a component
  that was just removed, verified by uninstalling the webmail for real and running the repair.
- **`POLICY_SYSTEM_PROTECTED_ADMIN` had two homes that disagreed** (#654) - the installer wrote
  `yes`, the repair `no`. Harmless while the repair only fired on an absent key, and an
  admin-protection downgrade the moment it fires on an empty one. The repair says `yes` now and the
  installer seed is gone, as is the one for `POLICY_USER_CHANGE_THEME`: one home per default.
- **`BACKEND_PORT` lost a repair that pointed at a deleted file** (#654). It scraped the port out of
  the hestia-nginx config Caddy replaced, so it produced nothing; the value is written at install
  time and every consumer falls back to 8083.

### Changed

- **`cli_json()` states its contract instead of implying it** (#578). It now declares `: array`, so
  "always an array" is checked rather than agreed, and a caller may drop its own `is_array()` on
  the strength of it. The same declaration names the limit it always had: a command whose JSON is a
  scalar loses its value there, silently, and two comparisons then read the other way round. Those
  callers take the new `cli_value()`, which answers `null` - the state they already test for.
- **The panel reads a CLI result in one place** (#578). The remaining 61 sites that decoded a
  command's JSON by hand now go through `cli_json()`, which closes the class the fatal sites above
  belonged to rather than only its instances. Two shapes were deliberately left alone: a site whose
  exit code or raw output is still consulted (a `check_*()` above the decode), and one whose value
  is a scalar rather than a list - `reset/index.php` reads a reset-key timestamp there and compares
  it against `null` and against `time()`, and an empty array answers both the other way round.
  Side effect worth having: `cli_json()` owns its `$output`, so 4 sites where a second `exec()`
  would have appended to the first one's output are gone with it.
- **A conditionally rendered control now reads through the gate that rendered it** (#649). A control
  the form did not render sends no key, and every form carried its own idea of what that means -
  three separate patches of the same class in one week. `post_or_keep()` and `post_checkbox()` hold
  the rule now, and each gate is named once so the view and the POST section read the same
  expression instead of two hand-written copies that drift. Converted across the web domain, user,
  package, mail and server forms; a hidden witness field was rejected because it is client-supplied
  and a forged one would claim a control the user was never offered.
- **A customer could set a control the policy had taken away from them** (#649). With
  `POLICY_USER_CHANGE_THEME=no` the theme select is not rendered, but the handler read the key
  whenever a request carried one - so a hand-made POST set the theme anyway. Value controls now
  decide on the server-side gate, not on the presence of the key, which is what the checkbox path
  already did.
- **The SSH key list warned on a user without keys** (#649): the command answers with nothing and
  the template iterated a null.
- **Two commands stopped running on every save** (#649): enabling HTTP/3 and applying a cache
  duration now run off the difference to the stored field. That is the intended semantics, but it
  also drops a side effect - a vhost that had drifted was quietly re-applied by any save, and only
  an explicit rebuild does that now.

### Changed

- **`h-update-user-cgroup` refuses to run while `RESOURCES_LIMIT` is off** (#650). All four callers
  already gated, so the behaviour is unchanged - but the safety lived outside the command, where a
  fifth caller would inherit the trap without being told. The check is idempotent and does not
  hinder `h-add-sys-cgroups`, which sets the switch before it applies anything.

### Changed

- **PHP has a format contract again** (#647). Upstream formats with prettier, which needs node and
  therefore cannot run on our runner, so nothing had enforced the style since the fork - and
  php-cs-fixer, the node-free replacement, defaults to PSR-12 with four spaces and rewrote whatever
  it touched. `.php-cs-fixer.dist.php` pins the actual house style (PSR-12, tabs) and the tree was
  formatted to match it once; vendored PHP is excluded by deriving the list from `VENDORED.json`.

### Fixed

- **A failed CLI read redirected and then rendered the page anyway** (#578).
  `check_return_code_redirect()` sent a `Location` header without stopping, so all 14 call sites
  carried on parsing a record the command had never produced - the null derefs above are downstream
  of exactly that. Same omission in the session-timeout branch of `main.php`, which rendered on
  against the session it had just destroyed while its sibling branch exited.
- **Nine forms silently offered an empty list** (#578) where a failed call left a null to iterate:
  the package and language selects on add/edit user, the language list on the server page, the
  ipset lists on the firewall forms, the IP select on the web domain form, the backup exclusions,
  the SSH key duplicate check and the PHP-FPM services list.
- **A suspended customer was served a rendered page** (#578). The suspension check sat in
  `top_panel()`, which `render_page()` calls *after* including `header.php` - with output buffering
  off the headers were already gone, so the `Location` was never sent and, without an `exit()`, the
  rest of the page rendered against the session just destroyed. Measured on a real suspended
  account: 13883 bytes of complete HTML and no redirect header at all. The check now runs in the
  session block before a single byte goes out, and answers 302 with an empty body. An admin
  impersonating a suspended customer is still not logged out, as before.
- **The logout did not rotate the session id** (#578), so an id captured beforehand was the id the
  browser kept and the next request adopted. `/logout/` destroyed the session with three calls of
  its own instead of `destroy_sessions()`, which now starts a fresh session and regenerates.
  Measured across a real logout: the cookie was unchanged before, and changes now. #438 had already
  rotated at the impersonation transitions; this was the plainer case still open.
- **`$is_real_root_user` compared two empty strings** (#578). With `ROOT_USER` absent the `?? ""`
  form answered yes for an empty session user - permissive at the one line that decides who the
  root account is, and it gates the root-only server policies. Both sides must now be non-empty.
- **An unreadable system config left every policy standing open** (#578). `load_hestia_config()`
  copies `h-list-sys-config` into the session and never checked whether it got anything; a failed
  call left the session without a single policy key, and an absent key is the permissive reading at
  every gate that gets it - the password reset was allowed although the admin had switched it off,
  the protected-admin flag read as unset, and both log policies read as granted. Measured, not
  reasoned: with an empty session those five gates decide open. The panel now answers 503 rather
  than deciding without its own configuration; a table of closed per-policy defaults was rejected
  because it goes stale the day a policy is added. `top_panel()` gained the matching guard - a user
  row that comes back empty (exit 0, no output) used to pass the suspension check and write `null`
  into `userContext`.
- **23 panel pages died instead of showing an empty list when a CLI call failed** (#578). The pages
  read a command's JSON without ever looking at its exit code; a failed call leaves the output
  empty, `json_decode("")` is `null`, and the first `ksort()`/`array_reverse()`/`array_keys()` on it
  is a TypeError under PHP 8. These are the list pages - the first thing a user sees after logging
  in. They now read through `cli_json()`, which was introduced with #575 for the two unauthenticated
  entry points. Counted from scratch rather than from the issue's table, which had missed
  `array_reverse()`: with it the sort-order branch is fatal too, so the pages failed regardless of
  which sort order the user had set.
- **Three saves that wrote a field nobody touched** (#649). A web domain materialised
  `FASTCGI_CACHE`/`FASTCGI_DURATION` on its first save on every model that does not render the
  cache control, because with nothing stored the duration field displays a 2m default and the
  absent key was compared against it - which also ran `h-delete-fastcgi-cache` on a box without an
  nginx web role. A mail domain lost `ANTIVIRUS` on any plain save wherever no antivirus system is
  installed. The phpMyAdmin alias was rewritten from an absent key on a box without a mysql host.
- **A new package wrote its resource limits unquoted** (#649) while `RESOURCES_LIMIT` was off, so
  four lines in the package file disagreed with the quoting of every other line in it.

- **A package could not be saved from the panel on an apache web role** (#644), which is three of
  the four models. The web-template select renders empty there - the apache templates moved to
  `share/` and are not selectable - and an empty select submits no key at all, so the handler read
  one that was never sent and died with a fatal 500. The row is only offered where something is
  selectable now, and a rejected form no longer falls through into the write path, which used to
  save the package regardless of its own validation errors. Saving also stopped blanking
  `CPU_QUOTA`, `MEMORY_LIMIT` and `SWAP_LIMIT`: their controls only exist while `RESOURCES_LIMIT`
  is on, and an absent control is not a cleared value. The same file carried four more of the
  class: a three-`r` typo left the shell check dead while an absent control silently demoted the
  package to `nologin`, `DOCKER_LIMIT` fell back to a literal instead of the stored value, and the
  backend and proxy rows demanded fields they never offered when their lists were empty. The
  system-package lock also read `$_GET` while the write used `$_POST`, so a crafted POST walked
  around it.
- **Four dead ends found by clicking every panel page** (#644): `/list/web-log/` answered a URL
  without a domain with a fatal, the incremental-backup list counted a string when its command
  failed, `/list/notifications/` rendered a template that has never existed, and the add-package
  form read a variable that only the POST path sets. A request without a CSRF token no longer logs
  a warning before being refused.
- **Saving a user replaced the theme they had chosen** (#645). No option in the select carried
  `selected`, because the marker was keyed on a session variable rather than on the value being
  rendered - and an unmarked select submits its first option, `dark`. The two policy checks that
  decide whether the session even carries a theme also disagreed on their default (`!== "yes"` at
  login against `=== "no"` everywhere else), so the policy shipping unset dropped it on every
  login. The policy ships with an empty value, and the repair that would have set it only fired on
  a *missing* key - it now treats empty as missing.

- **Every domain rebuild on an apache-only box wrote to `/etc/nginx`** (#642). `nginx -v` without
  the binary prints an error message, which carries no `/` for `cut` to split on and sorts above
  every real version - so the box read as "nginx 1.25.1 or newer" and tried to drop the http2
  marker into a directory apache-only does not have. The probe fails closed now.

## v0.15.0 (2026-08-13)

Closes the template restructuring (#219) and the Docker series (#389/#566), and takes the
read side of the object accessors with it.

### Added

- **Docker per customer, from the daemon to the domain** (#389/#566/#592/#618/#619). Each enabled
  customer gets a *companion* account running a rootless daemon, its own loopback **/24** from
  127.20.0.0/16 (`DOCKER_IP` = its `.1` = the daemon's default bind, so a tutorial compose file
  publishes with no address in it), and a per-domain switch: `DOCKER` / `DOCKER_PORT` /
  `DOCKER_OCTET` on the web record make the front proxy to the container - no backend vhost, no FPM
  pool, no PHP selector, WebSockets through, LE and CrowdSec and bot limits still attached.
  `TPL`/`PROXY` stay untouched, so a web-model switch keeps the choice. Templates live per front in
  `templates/docker/<system>/` and are offered in their own menu. Separation between local users is
  one rendered nft rule per /24 with the webserver allowlisted, derived from the records so it
  survives a firewall rebuild. Admin switch in edit-user, gated on an unjailed login shell; turning
  it off deletes containers, images and volumes and therefore asks for the customer's name.
  Resource cap through the package (`DOCKER_LIMIT`: `unlimited`/`low`/`medium`/`high`) on the
  companion's systemd slice, where the daemon and all containers live - percentages are native
  systemd syntax and the cap is not gated on the box-wide `RESOURCES_LIMIT`.
- **HTTP/3 (QUIC) as a per-domain switch** (#613). Was three `wordpress*-http3` template variants;
  is now `h-add-web-domain-http3` plus an SSL-section checkbox that works on any template, through
  an include fragment the merged SSL block already globs. Offered only where nginx is built
  `--with-http_v3_module` (deb12 / ub24 are not - the old variants broke `nginx -t` there). UDP/443
  is in the standard firewall seed, so the advertised endpoint is reachable after a rebuild.
- **Suspension and the offline switch render from `share/`** (#586). Suspending used to pick a
  template from the selectable tree, which apache never had - on apache-only the vhost came out
  empty and the domain served the box default page. Both models render the same suspend page now,
  and a customer-facing offline switch (`h-add-web-domain-offline`) serves a 503 maintenance page.
- **Proxy caching is a switch** (#587), not a template variant: `h-add-web-domain-cache` with a
  duration, on any template.
- **Panel users get their uid from a dedicated band** (`func/identity.sh`, #388), deterministic per
  username, with the companion block one thousand below. A smoke guard checks the preconditions -
  `UID_MAX`/`GID_MAX` below the band, subordinate ranges wide enough, no two panel users sharing a
  uid - because a collision only surfaces much later.
- **DNSBL management from the CLI** (#555): `h-add-sys-mail-dnsbl` / `h-delete-sys-mail-dnsbl` /
  `h-list-sys-mail-dnsbl`.

### Changed

- **A template is one file, and a domain has one vhost config** (#593). The `.tpl`/`.stpl` pair is
  gone: a template carries both server blocks split by a marker, and renders one `<system>.conf` -
  the SSL block only when SSL is on. That removes the "fixed in the .tpl, forgotten in the .stpl"
  divergence class. Restore discards archived vhosts and re-renders, so a HestiaCP two-file backup
  restores as one merged vhost and the backup format stays bidirectional.
  `h-change-web-domain-sslhome` is removed with its `v-*` symlink.
- **The PHP version is its own field** (#591, closes #550). `PHP_VERSION` carries the version,
  `BACKEND` only the pool profile (`default` / `small` / `high`). Existing records migrate on their
  next rebuild, reading the version from the pool the vhost actually points at rather than from the
  system default - the two diverge after any default change. The archive carries `BACKEND` rewritten
  to HestiaCP's `PHP-<ver>` plus native `PHP_VERSION`/`PHP_PROFILE`; a restore prefers the native
  pair and aborts before the first write if an archived version is not installed
  (`RESTORE_PHP_FALLBACK=yes` maps to the default instead - never silently).
- **`templates/` holds only what somebody chooses** (#588/#589/#590): `nginx/`, `php/`, `docker/`.
  The apache vhost, the both-model proxy vhost, suspend/offline, skeleton, awstats and mail bodies
  moved to `share/`. The six apache templates went entirely - both apache models already rendered
  the php-fpm variant, so the mod_php-era variants were unreachable. Two rules keep the flat tree
  working: the **role** picks the directory (nginx is the proxy in the both model, the web role in
  nginx-only), and `PHPTPL` is its own anchor rather than `$WEBTPL/$WEB_BACKEND`.
- **Templates are validated the way they are rendered, and aged-out values are mapped** (#588).
  One resolution function for validator and renderer; every write passes through
  `accept_web_template`, which maps a legacy value onto its replacement **with its side effect** - a
  restored `caching` domain comes back with the cache switch on. A CLI typo still errors; a restore
  falls back rather than abort over one record.
- **The web model decides the install scope** (#639). apache-only means no nginx on the box at all.
  Mail-only still gets one for the webmail vhost and ACME, because the wizard fixes that preset to
  NGINX - an exception carried by the model. Leaving a server behind stops and disables it; `--purge`
  removes the package, symmetrically for both servers.
- **An install stage is only skipped for the answers it ran with** (#636). Stage markers carry the
  fingerprint of their `install.conf`; re-answering the wizard re-runs what changed. A legacy empty
  marker no longer counts as done.
- **PROVENANCE recomputed for all three folders** against `upstream/hestiacp@bc3720a` (snapshot
  2026-08-10). `DNSTPL` is gone from `func/main.sh` with the rest of the DNS leftovers, and
  PATHS.md/STRUCTURE.md/CODEMAP carry the flattened template tree.
- **Scanner bans drop, credential bans still reject** (#555): the verdict is per jail chain.
- **`/proc` hardening lives in `/etc/fstab`**, not an `@reboot` cron job, and its exemption gid is
  resolved at every boot instead of baked in at install time. A smoke guard verifies the live mount,
  since fail-open is invisible.

### Removed

- **The DNS leftovers** (#619). No local DNS server is planned, so `DNS_TEMPLATE`, `DNS_DOMAINS`,
  `DNS_RECORDS`, `NS`, `SUSPENDED_DNS` and the `U_DNS_*` counters are gone from packages, user
  records and every listing format, together with `h-list-user-ns`. `h-add-user-package` no longer
  validates fields the panel does not post - which is why no package could be saved from the panel.
  The DKIM record view stays: that formats mail-stack data for somebody else's DNS.

### Fixed

- **Object reads matched a domain as a regular expression** (#594). The dot is a wildcard, so with
  `a.b.com` and `aXb.com` on one box a read on one could return the other's record,
  `is_object_valid` could confirm a domain that does not exist, and `add_object_key` could write
  into the wrong record. Nine accessors and 54 call sites match literally now. The backup exclusion
  parsers mix a literal name with an intentional `*` and matched by prefix - an exclusion for
  `aXb.com` also kept `a.b.com` out of the archive; they compare by index now, and the backup
  counts what it packed against what the records say.
- **An alias owned by another customer was never refused** (#601). `is_web_alias_new` compared
  `"$user"` with `"$user"` - the loop had overwritten the caller's name with the owner from the file
  path, so only the `type == web` half of the check survived and a mail domain could take a foreign
  alias.
- **HSTS did nothing on an apache front** (#638). The fragment carried nginx syntax whatever the
  front was, and no apache template included it: switch on, record `yes`, no header. Both halves
  move together - feeding `add_header` to apache would break `configtest` for the whole box. A guard
  catches a domain claiming HSTS whose fragment is missing or written for the other server.
- **The ip domain counter drifted one under the truth per backup-restore cycle** (#599): the restore
  recounts, and that recount could not see records holding a NAT'd box's public address.
- **A user named after a service died at `groupadd`** (#625). `h-add-user` checked `/etc/passwd` but
  never `/etc/group`, and the group is created as the mirror of the user. Both are checked now, plus
  a curated list of accounts our components create later - a name free today must not become a
  collision after an `h-add-sys-*` run.
- **The FTP account commands disagreed about the name** (#625): add prefixed it with the owner while
  delete and the change commands wanted the stored form. All four take either.
- **A domain name acting as a regex could delete another customer's cache zone** (#583) and three
  more unescaped `sed` patterns on the write side.
- **A missing web template wrote a silent 0-byte vhost** (#586).
- **`h-change-sys-php` took effect one round late** and rebuilt the stock on the old version (#585).
- **The dummy FPM pool leaked into the isolated panel master** with a placeholder socket (#604).
- **Two config repairs never ran** (#559), and a deleted key in `hestia.conf` came back on the next
  syshealth run (upstream #5584).
- **A failing CLI call took the login page down** and let the post-password gates pass (#575).
- **A dead SnappyMail mirror produced a green install with no webmail** (#573): an unbounded
  download in an install path is a hang, and a script without `set -e` turns a failed download into
  a green install of nothing.
- **Backup retention could delete another user's archives** (#556, upstream #4918), and restic
  restored only the first domain or database of a multi-object user (#555, upstream #4987).
- **The panel served its own includes, templates and locale data over HTTP** (#554, upstream #5446).
- **The Cloudflare realip fallback trusted a client-controlled header** (#553), and one range in the
  panel's IP validator was wrong in both directions.
- **A Let's Encrypt account whose `user.key` no longer matched failed forever** (#555, upstream
  #5294); a valid host certificate looked invalid and was reissued on every run (#555).
- Smaller inherited ones: the services list showed uninstalled database servers (#556), the manual
  ban chain picker offered a chain that no longer exists (#555), the firewall list showed rules in
  reverse evaluation order (#554), `useradd` ran on every rebuild (#555, upstream #5557), `quotaon`
  warnings read as install errors (#555, upstream #5465), a quote in a certificate field broke the
  SSL JSON (upstream #5586), and five leftovers around domain creation (#601).

## v0.14.0 (2026-08-06)

The firewall round: one nftables table, fail2ban as a removable addon, and CrowdSec as a
three-way model.

### Added

- **The firewall renders as one nftables `inet` table** (#495, #481), IPv4 and IPv6 together,
  behind a seam that keeps the invariants when the renderer changes.
- **fail2ban is a removable addon** (#497) and **the model is switchable at runtime** (#498):
  fail2ban only, CrowdSec only, both, or neither.
- **Layer-7 jails, so a fail2ban-only box has real web coverage** (#496, #515, #531).
- **The whitelist is a first-class object** (#495, #496) - `excludes.conf` only suppressed *new*
  bans and left existing ones in place.
- **IPv4/IPv6 parity** (#496, #536, #545, #548): service accepts, jails, blocklists and the panel
  rows all carry both families.
- **Panel surfaces for firewall state** (#496, #527, #482): jail status, ban lists, manual bans.
- **Curated IP blocklists** (#481), refreshed on a systemd timer rather than the daily cron queue.
- **Smoke guards for the datapath** (#481, #495, #496): a running daemon is not a loaded ruleset.
- **A CODEMAP consistency check** (#513), after the map drifted within a few PRs.

### Security

- **The webmail loopback listeners are restricted to the connecting UID** (#507).
- **`source_conf` no longer executes code smuggled into a config key** (GHSA-xffx-jj33-p2px class).
- **The webmail vhost overwrites the client-IP headers it forwards** (#515), so a client cannot
  spoof the address a ban is written for.
- **Ten panel controllers checked CSRF before the role** (#496) - both guards worked, the order
  decides which one an attacker gets to probe.
- **CrowdSec's credential files are 0600** (#494).

### Fixed

- **fail2ban had been installing a config it could not start** (#496), and **a fresh install
  aborted silently in its stage** (#520).
- **The firewall broke IPv6 by dropping ICMPv6** (#534).
- **Restarting the firewall from the panel destroyed the ruleset** (#496): the service row fell
  through to `systemctl restart nftables`, which loads the distro ruleset over ours.
- **CrowdSec was never installed by a fresh install** (#186): the gate read config keys the
  installer shell cannot see - `wcv` writes, it does not export.
- **A live web-model switch left the fail2ban web jails watching the old log dir** (#537), and
  **fail2ban and CrowdSec doubled up in the combined model** (#542).
- **A fail2ban restart wiped the persistent banlist** (#496).
- **`is_format_valid` failed silently when a name matched no variable** (#496) - it validated by
  variable name, so a typo passed everything.
- Smaller ones: the panel answered plain HTTP with a bare 400 (#547), the standalone CrowdSec
  commands raced a model switch (#528), the installer never named `nftables` (#548), and dead
  references from removed subsystems (#548).

### Changed

- **`iptables` and `ipset` are no longer installed** (#548); nothing has called either since the
  nftables renderer landed.
- **`FIREWALL_SYSTEM` reads `nftables`** (#495) - the value names the backend. Pre-v1, no migration.
- **Adding, renaming or restoring a web domain tells fail2ban about its log** (#496).
- **CrowdSec is one three-way model question instead of two** (#186).
- **PROVENANCE reconciled against `upstream/hestiacp@ca19b9f`** (#548).

### Removed

- **The mysqld jail** (#496) - 3306 is not in the shipped ruleset.
- **The UA-based `web-badbots` jail** (#531) - user-agents are trivially forged.
- **`h-refresh-sys-theme`** and its symlink (#548): it called a command that does not exist.

## v0.13.0 (2026-08-03)

### Added

- **CrowdSec** (#186) - an nginx-gated, removable addon in four layers (local decisions, CAPI,
  a fleet mesh, and an L3 feeder), offered in the wizard as one three-way choice.
- **Server-native web bot rate-limiting** (#482) - `func/botpolicy.sh`, nginx `limit_req` or
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
