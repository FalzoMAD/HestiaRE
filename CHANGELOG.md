# Changelog

All notable HestiaRE changes are documented here, starting from the fork
point — a HestiaCP 1.9.6 snapshot, kept read-only in the `upstream/hestiacp`
branch (upstream's own history was dropped from this file with #307).

Maintenance rule: every larger change adds an entry to the Unreleased
section as part of its PR. On release, the section gets the version number.

## Unreleased

### Added
- **The webmail loopback listeners are restricted to the web server and root** (#507). Roundcube (`:8090`)
  and SnappyMail (`:8091`) are plain TCP on `127.0.0.1`, so unlike the socket-based apps they had no access
  control at all and **any local user could reach them - including customers, who have shells here**. That
  reached further than the apps themselves: Caddy passes a client-supplied `X-Real-IP` straight through, so
  a customer could hand the app an arbitrary address and, once a jail read it, have a third party banned.
  IP-based filtering cannot help (two local users share `127.0.0.1`), so the rule keys on the connecting
  **UID**, which is exactly the distinction needed. Rendered into `inet hestia` by the renderer itself, so
  it is rebuilt on every apply, survives a reboot with the rest of the ruleset, and is covered by the
  existing smoke guards rather than needing its own persistence. Verified against **both** webmail systems
  and both ends of the nft range: the proxy still gets HTTP 200, root still gets 200 (`h-check-sys-smoke`
  probes that port), and a customer is refused at connect time.

### Fixed

- **The roundcube logrotate entry conflicted with the package's** (#508). Both cover
  `/var/log/roundcube/*.log`, so logrotate reported a duplicate and skipped one of the two files entirely.
  Ours won only because `roundcube` sorts before `roundcube-core` - had it gone the other way, rotation
  would have recreated the logs `www-data:adm`, which the caddy FPM pool cannot write, silently ending
  webmail logging. Our entry now claims every path the package's does (the extension-less names included,
  for a box with an empty `log_file_ext`) and documents the ordering dependency, so the outcome no longer
  rests on filename luck. The package's file is a dpkg conffile and is deliberately left in place.
- **fail2ban bans IPv6 too** (#496). Service accept rules carry no family qualifier, so v6 already reached
  exactly the ports the jails protect - while the jail sets were `ipv4_addr` and the ban command validated
  v4, so a v6 brute force was logged, matched, and then failed its `actionban` on every attempt. A jail is
  now two sets and two rules (`f2b_<CHAIN>` / `f2b6_<CHAIN>`), and bans route by family. **Nothing
  presupposes a v6 stack**: an `ip6` rule and an `ipv6_addr` set load on a host with no v6 address and even
  with `disable_ipv6=1`, verified on the fleet, so a v4-only box is unaffected. `::1` is refused like
  `127.0.0.1`.
- `h-add-firewall-ban` / `h-delete-firewall-ban` take an address of either family (`IP_CIDR`), via a new
  `is_ip_cidr_format_valid`. The single-family validators stay for the places that genuinely mean one
  family.

### Changed

- **The mysqld jail is gone** (#496). 3306 is not in the shipped ruleset, so MariaDB is reachable only from
  loopback and the box itself - both of which `h-add-firewall-ban` refuses to ban, so the jail could only
  ever match and then decline to act. An admin who deliberately opens 3306 owns the access control for it
  and can add a jail to suit; the reason is recorded in `jail.local` rather than left as an unexplained
  `enabled = false`.

### Fixed

- **Restarting the firewall from the panel destroyed the ruleset** (#496). The service row is named after
  `FIREWALL_SYSTEM`, which became `nftables` with the renderer swap - but `h-start/stop/restart-service` and
  the three panel service pages still matched a hardcoded `iptables`. The firewall row therefore fell
  through to `systemctl restart nftables`, which **tore down our `inet hestia` table and loaded the distro's
  `/etc/nftables.conf`** instead. Verified on a live box before and after. All six sites now match the
  configured name rather than a literal.
- **Five commands validated an argument they never assigned**, found by the hardened `is_format_valid`
  (#496): `h-add-user-2fa`, `h-check-user-2fa`, `h-delete-user-2fa` passed a `system` name that never
  existed; `h-add-letsencrypt-host` passed `aliases`, which that command does not take; and
  `h-move-firewall-rule` passed `rule` (the variable is `source_rule`) plus the *value* as a second name.
  All were dead checks. `h-move-firewall-rule` now validates its rule id for the first time.

- **`is_format_valid` now fails loudly when a name matches no variable** (#496). It validates by *variable
  name* - each name is both the type to check and the variable to read via `${!name}` - so a name with no
  matching variable expanded to empty, and empty meant "nothing to check, so valid". Renaming an argument or
  typoing a type therefore disabled the check **silently** instead of failing. That had already cost us
  twice, so it is fixed at the root rather than per call site: an unset variable is a hard error, while a
  genuinely optional argument (declared, empty) is still a legitimate skip.
- **Five `h-restart-*` commands validated an argument they never assigned** (#496), found immediately by the
  hardening above. `h-restart-web` assigned `restart` *after* the verification block; `h-restart-proxy`,
  `-cron`, `-ftp` and `-mail` never assigned it at all - so `is_format_valid 'restart'` checked nothing in
  any of them, and an invalid value was accepted silently. Also fixes a `RESTARRT` typo in one header.

- `h-add-firewall-chain` read the panel port out of `$HESTIA/nginx/conf/nginx.conf`, which Caddy replaced
  (#496). It printed an error on every jail creation and fell back to 8083 - right by luck, wrong on any box
  whose panel port was changed. It reads `BACKEND_PORT` now.
- **fail2ban actually works again** (#496) - it had been installing a config it could not start. The
  installer copied `filter.d/*.conf` and `jail.local` but never `action.d/hestia.conf`, so every jail
  referencing `action = hestia[...]` was skipped and **6 of 7 jails were dead on every target**, with the
  service reporting healthy. The only live jail was the distro's own `[sshd]`, banning into a ruleset
  HestiaRE does not manage. Now: the **whole** `share/fail2ban` tree is installed (a copy that cannot skip
  a directory, unlike an enumeration), via a new `func/fail2ban.sh` shared by the installer and the future
  addon commands. Result on the fleet: 0 config errors, 7 live jails, every ban going through our action.
- **Our jails ship as `jail.d/hestia.local`** (#496) instead of overwriting `jail.local`. fail2ban reads
  `jail.conf` -> `jail.d/*.conf` -> `jail.local` -> `jail.d/*.local`, so ours is read last and wins, the
  package's own file stays untouched, and an admin has a place for overrides we will never overwrite.
- **The distro `[sshd]` jail is disabled from our own config**, not by deleting
  `jail.d/defaults-debian.conf` (#496). Upstream deletes it; that file is a **dpkg conffile**, so removing
  it is silently undone by the next package update and the second, uncoordinated firewall writer comes
  back. Load order settles it instead.
- **A proftpd jail**, gated on the FTP addon being present, and the mail jails gated on the mail block
  (#496). A jail watching a logpath that does not exist never fires and says so only in fail2ban's own log.
- **Four fail2ban smoke guards** (#496): config parses without error (checked on stderr, since the dump
  still exits 0), the live jail set equals the configured set in **both** directions, no jail bans through
  a foreign action, and every jail's logpath exists. Any one of them would have caught the breakage above.

### Fixed

- **A fail2ban restart no longer wipes the persistent banlist** (#496). `h-delete-firewall-chain` is
  fail2ban's `actionstop` and it deleted the `chains.conf` and `banlist.conf` records, so every stop,
  restart or package upgrade discarded exactly the state the hestia ban action exists to keep. It now takes
  an optional `KEEP_RECORDS` argument; `actionstop` passes it and tears down only the live wiring, while a
  human-initiated delete still purges. Verified: restart leaves the banlist intact and the ban enforced.
- **The firewall renders as one nftables `inet` table** (#495) - the renderer swap, behind the seam that
  landed first. Everything that follows is a consequence rather than a separate feature:
  - **No fail-open window.** `table` / `delete table` / `table` in one `nft -f` means there is never an
    instant with an open policy or an empty chain, which the iptables renderer could not avoid: it set
    `-P INPUT ACCEPT`, flushed, and only restored `DROP` at the end of every rule change. The rendered
    document is validated with `nft -c -f` first, so a bad ruleset is rejected instead of half-applied.
  - **One transaction for the whole ruleset.** Jails and their bans are rendered into the same document as
    the base rules; the three separate applies were an iptables necessity and were exactly what left a
    window with the jails detached.
  - **Persistence is the applied document**, reloaded by an own `hestia-nftables.service`. No dump to
    post-process, and no `ExecStartPre` that provisions sets separately - sets and the rules matching them
    load in one transaction, which retires the boot hazard where one unprovisioned set could make
    `iptables-restore` reject the whole filter table and bring the box up unfiltered. Own unit and own
    file, never `/etc/nftables.conf`: that is a dpkg conffile.
  - **A jail is a set plus one rule** instead of a chain of per-IP rules, so a ban is an element add.
    The multi-port delete bug dies with the shape that caused it: deleting a MAIL/WEB/DB/RECIDIVE jail now
    removes rule, set and record cleanly, and cannot orphan a chain.
  - **ipset is gone.** Native nft sets replace it, and every dynamic set renders from a source-of-truth
    file (`ipset/<name>.iplist`, and a new `crowdsec.iplist` the L3 feeder owns) so a wholesale table
    replace cannot lose its contents. Verified: elements survive a full rebuild.
  - **Legacy teardown runs at cutover** and is mandatory, not housekeeping - iptables here is the nft shim,
    so a leftover ruleset lives in the same kernel backend and would keep being evaluated alongside ours.
    It is driven off the live ruleset rather than `chains.conf`, so it also reclaims chains orphaned by the
    old delete bug.
  - **`FIREWALL_SYSTEM` now reads `nftables`**, since the value names the backend. Pre-v1, so no migration
    path is owed.
  - **IPv6 is prepared, never presupposed.** One `inet` table covers both families; only v4 is rendered,
    no rule references a host v6 address, and the ruleset was verified to validate, apply from scratch and
    rebuild with `disable_ipv6=1`. The lab is v4-only, so v6 filtering is **not** behaviourally tested.
- **`excludes.conf` is enforced, not just consulted** (#495). It used to suppress *new* bans only, which
  left an already-banned admin locked out and gave the file no effect outside fail2ban. It now renders as
  an accept set ahead of every ban match, which makes it the recovery primitive it was always meant to be.
  Commands and a panel page for it remain #497.

### Fixed

- `h-delete-firewall-ipset` never actually refused to remove a list that was still in use (#495). The
  guard ran `check_result $?` *inside* the `then` branch, so it saw the exit status of the successful
  lookup and always passed. nft refuses to delete a referenced set, and that refusal is now the check.
- **Firewall renderer seam** (#495) - every backend call in `bin/` and `func/` now goes through
  `func/firewall.sh`; a repo-wide sweep for direct `iptables` invocation outside that file returns nothing.
  Callers state what they want in object-model terms (`fw_rule`, `fw_jail_rebuild`, `fw_ban_add`,
  `fw_set_jump`, `fw_policy`, `fw_persist_enable`) and the library renders it, so the nftables swap becomes
  a change to one file instead of eight commands. **Deliberately zero behaviour change**: verified by
  re-capturing the effective firewall state on all four targets after running the new renderer and diffing
  it **byte-for-byte** against the pre-seam reference captures - identical on all four. Two known defects
  are preserved verbatim rather than quietly fixed, because a behaviour change here would rob that gate of
  its meaning: the swallowed apply errors (D2, fixed by the atomic nft apply) and `h-delete-firewall-chain`
  using a bare `--dport` where multi-port jails need `-m multiport` (D4, fixed in #496). Both are now
  commented at the single place they live instead of being buried in a caller. `h-update-firewall` drops
  from 243 to 176 lines, `h-stop-firewall` from 113 to 67, and the duplicated persistence block collapses
  into one helper.
- **A third firewall smoke guard, `check_firewall_chains_tracked`** (#495) - the live ruleset must not
  carry a jail chain the object model has forgotten. This is `check_firewall_sets_bootable`'s mirror
  image: there the model promised more than the live state delivered, here the live state holds more than
  the model admits to. Reachable today and reproduced: deleting a multi-port jail leaves the jump behind
  (D4), the leaked jump keeps the chain referenced so the following `-X` fails, and the next flush drops
  the jump while the teardown loop iterates `chains.conf` where the record is already gone - so nothing
  ever reclaims the chain and it survives as an orphan no `h-list-firewall*` command can see. Stays
  useful after #496 fixes the cause: an untracked chain is a rule nobody audits.
- **`h-check-firewall-chain CHAIN`** (#495) - fail2ban's `actioncheck`, replacing an
  `iptables -n -L INPUT | grep` in `share/fail2ban/action.d/hestia.conf` that would silently go stale the
  moment the renderer changes. It asserts both halves of "wired": the jail chain exists *and* the base
  chain still jumps to it - a chain can survive while a flush has dropped the jump, and in that state bans
  are recorded but never enforced. This matters more than a normal check because fail2ban answers a failed
  `actioncheck` by running actionstop + actionstart, and actionstop deletes every `banlist.conf` row for
  the chain. No `v-*` symlink.

- **Two firewall smoke guards** (#481) - `h-check-sys-smoke` now checks the firewall *datapath*, not just
  that a daemon is up. `check_firewall_closed` asserts INPUT still defaults to DROP while
  `FIREWALL_SYSTEM` is set; `check_firewall_sets_bootable` asserts every ipset the **persisted** ruleset
  matches on can actually be recreated at boot. The second reads the saved file on purpose: the kernel
  refuses `--match-set` for a set that does not exist, so a dangling reference cannot exist in the live
  ruleset and looking for one there would always pass. The reachable failure is ordering -
  `iptables-restore` is atomic per table, so one rule pointing at an unprovisioned set rejects the entire
  filter table and the box boots with policy ACCEPT and no rules, while the unit's provisioning step is
  dash-prefixed and its failure ignored. For a user ipset the check requires **both** its `ipset.conf`
  record and its cached `.iplist`, because the cache is what decides boot provisioning, not the health of
  the list source: `h-add-firewall-ipset` only re-fetches when the `.iplist` is missing, and the boot unit
  is ordered `Before=network-pre.target`, so a fetch there cannot succeed at all. With the cache present a
  long-dead URL is harmless at boot; with it missing, provisioning exits at the size/existence checks
  before `ipset create` and the set is never created, empty or otherwise. All cases negative-tested
  (forced ACCEPT policy; a persisted reference with no record; the same with the record but no cached
  list) and green across the fleet.
- **CODEMAP `firewall` and `fail2ban` components** (#481). The most security-critical subsystem in the
  product had no entry at all - a bin-glob count and one line calling `func/firewall.sh` a "symlink
  healing helper". The entries record the load-bearing INPUT emission order, the object model, the
  persistence hazard above, and the fail2ban breakage described under Fixed/known issues.
- **`h-change-sys-crowdsec-mode capi|local|mesh`** (#494) - switches the CrowdSec model at runtime, for
  the case where the fleet grew and a box should start meshing after the fact. Previously only the mesh
  half was switchable (`h-add/delete-sys-crowdsec-mesh`); there was no way back to the community
  blocklist at all, because only `crowdsec_disable_capi` existed. Its inverse `crowdsec_enable_capi` now
  does, including enrolment, and it rolls the config back to local if that fails rather than leaving
  `online_client` pointing at credentials that are not there. The live model is derived from the
  artefacts on disk, not from `install.conf` (that is the install recipe, not live state), and the
  target is always enforced in full - which also normalises the inconsistent `capi`+`mesh` combination
  the previous two-question wizard allowed.

### Security

- CrowdSec's `local_api_credentials.yaml` and `online_api_credentials.yaml` are chmod 0600 now (#494).
  The packages generate them 0644 although both carry a machine password, and customers have shell
  access on these boxes. The engine and `cscli` run as root, so nothing needs the world bit.

### Changed

- **CrowdSec is one three-way model question now instead of two** (#186). The wizard asked "community
  blocklist?" and then "fleet-mesh?", which spans four combinations while only three are supported.
  `CROWDSEC_CAPI` + `CROWDSEC_MESH` are replaced by a single `CROWDSEC_MODE` radio: `capi` (central
  blocklist + telemetry, this server alone), `local` (self-hosted, this server alone), `mesh` (local
  engine, own bans shared across the fleet). `mesh` implies local, so it disables the CAPI
  `online_client` too. Note that the two are technically orthogonal and do combine - dropping
  CAPI-plus-mesh is a deliberate product simplification, not a constraint. Both flags had exactly one
  consumer each, so this is a rename plus a mapping, no behavioural change to the three kept models.

### Fixed

- **CrowdSec was never installed by a fresh install** (#186). The installer's nginx-front gate read
  `PROXY_SYSTEM`/`WEB_SYSTEM`, but `main.sh` sources `hestia.conf` at startup - before the web stage
  writes those keys - so both were empty in that shell and the gate silently skipped the whole block
  (`crowdsec_apply` reads the same two keys for the public front and the acquisition log path). The
  security stage now re-reads `hestia.conf` first. Caught by `h-check-sys-smoke` on the v0.13.0 fleet
  installs; unnoticed until now because every earlier CrowdSec round was verified on a hotpatched box
  rather than a fresh install.
- **The wizard never asked the fleet-mesh question** (#186, #485). `CROWDSEC_MESH` was a checkbox in
  the `addons` group, and that group renders as one combined screen whose values are all set on
  submit - so its `visible_if: ADDON_CROWDSEC == true` could never be true and the row vanished,
  leaving `COMPONENT_CROWDSEC_MESH` empty with no way to enable the mesh at install time. It is a radio
  now, asked right after the addons screen like the CAPI question. The wizard refuses a manifest that
  repeats the construction instead of dropping the row quietly.

## v0.13.0 (2026-08-03)

### Added

- **CrowdSec** (#186, #123) - an nginx-gated, removable addon in four layers, offered in the wizard
  only where nginx is the public front. **Layer A**: an own dependency-free LuaJIT bouncer queries the
  local LAPI per request and answers 403; rendered per web model plus a per-domain fragment
  (`h-add/delete-web-domain-crowdsec`). **L3**: an own `cscli` -> ipset feeder on a timer fills a
  `hestia-crowdsec` DROP chain, so the same decisions are dropped at SYN; `h-update-firewall` stays the
  sole iptables writer and the chain `RETURN`s loopback + RFC1918 before dropping. The OS
  `crowdsec-firewall-bouncer` is deliberately unused - 0.0.25 nil-panics in its ipset path, verified
  unusable on all four targets. The feeder filters by DENYlist (fail2ban's ssh/ftp/mail/db lanes stay
  out of L3, CAPI stays L7-only) after an allowlist was found to silently drop advisory-named web
  exploits. **Fleet-mesh**: a peer mesh with no central LAPI - each box publishes its own local
  web-tier bans and imports the union of its peers' as L7-only mesh bans; enforcement falls out of the
  existing layers rather than being rebuilt. Imports are hardened against a bad peer (single-IPv4
  validation, per-peer and total caps, `hestia-mesh:<peer>` attribution). **Transport**: two boxes pair
  over the panel port and then pull each other's list on a timer. **A pairing needs an admin on both
  boxes** - one runs `h-add-sys-crowdsec-peer`, the other must first mint a one-time code, and
  `/mesh-pair.php` is a plain 404 while none is live. The code is 100 bits, single-use, 15 min, dead
  after 5 wrong guesses; the long-lived artefact is a per-peer token, TLS is pinned by SPKI recorded at
  pairing, and each side installs an IP-scoped ACCEPT rule (`:8083` is never narrowed to peers-only).
  Secrets never ride in argv. Admin-only **Firewall > Fleet Mesh** panel page. The LAPI stays
  loopback-only throughout. `crowdsec_apply` removes `nginx-req-limit-exceeded` on purpose: it fires on
  our own Layer-B 429 and turned deliberate throttling into bans for good bots and shared IPs.
- **Server-native web bot rate-limiting** (#482) - a standalone Layer-B subsystem
  (`func/botpolicy.sh`), independent of CrowdSec and available on any web install. Bot families are
  throttled with native nginx `limit_req` / apache `mod_qos` (429); **humans are never limited** and
  malicious traffic stays CrowdSec's job (ban -> 403). An admin family table (10 slots, 8 curated)
  carries a UA match, `lenient`/`strict` rates and an enabled flag, plus conf-only `burst`/`nodelay`;
  per domain each family is `off`/`lenient`/`strict`. nginx keys per family **per domain** so customers
  do not share a bucket; apache mod_qos counts per client IP. Edited inline on **Server Settings**
  (admin-only) and per domain in **Edit Web Domain**, where it is **customer-editable** - an admin can
  also set it while impersonating. Default off/opt-in. Known limitation: matching is on the spoofable
  User-Agent, unverified.
- **Shell lint gate** (#477), check-only, in two tiers because the tree carries ~240 inherited
  HestiaCP warnings that are their own cleanup job: tier 1 is shellcheck at `severity=error` over the
  whole shell surface (0 findings), tier 2 at `>=warning` over the files a change touches. Both judge
  **regressions, not inheritance** - each changed file is compared against its base version so touching
  a legacy file does not inherit its warnings; formatting follows the same rule. `.shellcheckrc`
  disables only verified house idioms, `.editorconfig` carries the shfmt contract, and
  `.gitea/tools/lint-shell.sh` holds the logic so CI and a developer run the identical checks. The
  Gitea workflow is deliberately minimal: no actions (the runner host has no node by design), a
  temporary clone, `contents: read`, no secrets of its own, no installs, no writes.

### Security

Adopts the relevant fixes from the HestiaCP 1.9.8 release (#471).

- The user editor blocks a non-`ROOT_USER` admin from modifying the `ROOT_USER` account on the
  POST/save path, not only the page render, and keys the guard on `$_SESSION["ROOT_USER"]` instead of a
  hardcoded `admin` (HestiaCP #5547 / GHSA-c69h-jgpw-h9cj). A crafted POST could otherwise change the
  root account's password or role. The guard fails closed when `ROOT_USER` is unset.
- Panel notifications are HTML-sanitized before storage (HestiaCP #5548 / GHSA-3g4r-pfpf-8697).
  `NOTICE` renders as raw HTML via Alpine `x-html` and callers interpolate values into it, so the body
  now passes an allow-list sanitizer (`func/internal/sanitize_html.php`: DOMDocument, default-deny,
  keeps `p/span/code/a/strong/br` + safe `href`). Own dependency-free sanitizer, since HestiaRE ships
  no Composer. `TOPIC`/`NOTICE` also gained CR/LF and length validators, and the shell `send_notice()`
  helper - the second writer - goes through the same path.
- Restore scheduling no longer lets an argument inject into the executed restore queue
  (GHSA-2xw3-7h62-v4gf). `h-schedule-user-restore-restic` wrote `$snapshot`/`$value` single-quoted into
  `queue/backup.pipe`, so a `'` broke out for root RCE. Both restore schedulers now validate and quote.
- The admin debug panel escapes its variable output (HestiaCP #5550) - keys and string values were
  echoed raw (reflected XSS).

### Fixed

- Installer: an optional component could end up flagged on with its package absent (#480). Component
  installs ran `hestia_apt ... || true`, so a held apt lock (unattended-upgrades / apt-daily, common
  right after first boot) failed the install and the `|| true` swallowed it. Three changes, since none
  alone suffices: `hestia_apt` passes `-o DPkg::Lock::Timeout` so a held lock waits; the installer masks
  the auto-apt units for its duration and restores them from an `EXIT` trap (only units it masked
  itself, so an admin-masked one is never re-enabled); and optional installs verify against dpkg that
  the package actually landed, surfacing anything missing in the closing banner.
- `h-list-sys-php` no longer lists the isolated panel FPM pool as a pseudo-version `hestia` (#464).
  Consumers build `php<v>-fpm` from the list, so the stray entry produced `phphestia-fpm`, broke
  `h-restart-web-backend` on every box and rolled back every live web-model switch at its health gate.
- Web-model switch (#120, #466): rollback now uses `reload-or-restart` instead of a hard restart, so a
  failure before the restart stage cannot kill a server that is still serving its loaded config; and
  cleanup also removes the departing model's webmail vhost source under `/home/*/conf/mail/*/`, which
  previously left a stale conf behind.
- Directory listing (`h-change-web-domain-dirlist`) now works under nginx-only (#468) - it only ever
  flipped apache's `Options Indexes`, so `DIR_LIST='yes'` was a silent no-op. nginx gets `autoindex on;`
  via an include fragment.
- `h-list-mail-domain-ssl` JSON now escapes the certificate issuer (#471, HestiaCP #5524); a `"` or `\`
  in the issuer DN produced invalid JSON.
- Bot rate-limiting (#482): a disabled or deleted family left **dangling zone references** in the
  per-domain fragments - `nginx -t` then failed and blocked the next reload for every domain on the
  box. Fragments now skip families that are gone or disabled, the apply command re-renders every
  throttled domain before testing the config and takes the web-model freeze lock, and deleting a family
  strips it from every domain. A new smoke guard asserts that every per-domain **policy** fragment
  (CrowdSec Layer A, bot limiting) is included by every customer-domain template - one missing include
  is a silent bypass, not a visible failure. The panel handlers were hardened against non-array POST
  fields and an unbounded per-row command loop.
- CrowdSec (#186): re-adding no longer fails on the saved-state config - `/etc/crowdsec` is kept on
  delete, and a dpkg conffile prompt on `config.yaml` used to EOF under `noninteractive` and leave the
  package half-configured; both install sites now pass `--force-confdef --force-confold`. The CAPI
  wizard blurbs were shortened to a couple of words each, which the layout needed.

### Changed

- PROVENANCE recomputed for all three folders against the current `upstream/hestiacp` snapshot
  (`ca19b9f`, 2026-07-30). 74 files that had accumulated since the last run are now listed - the
  CrowdSec, bot-limiting and mesh commands, their `share/` assets and the new panel routes, all
  `eigenbau`. Divergence, `upstream_ref` and `last_reconciled` refreshed throughout; percentages are
  integers again (six entries had picked up a decimal), files identical to upstream are recorded as
  0% rather than left unmeasured, and the two genuinely binary blobs are flagged instead of carrying
  a meaningless churn number. Vendored paths stay out - they belong to `VENDORED.json`.

### Removed

- Deleted the orphaned bind9/named and vsftpd server-config views and their PROVENANCE entries (#471).
  Both are permanent ground-rule removals, the views were unreachable (the services list is
  data-driven), and the vsftpd one called a command that does not exist. The stale `vsftpd` branch in
  `edit_web.php`'s FTP-account toggle went with it (`FTP_SYSTEM` is only ever `proftpd`).
- Pruned 36 app-specific web templates (72 files) from `templates/web/nginx/php-fpm/` that the removed
  Software/App Installer had seeded. With no installer to place these apps they were dead weight; the
  standard set stays (`wordpress*`, `laravel`, `magento`, `owncloud`, `prestashop`, `symfony4-5` plus
  `default`/`no-php`/`suspended`). The list is directory-driven, so panel and CLI follow automatically,
  and any pruned template can be re-imported from `upstream/hestiacp`.

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
