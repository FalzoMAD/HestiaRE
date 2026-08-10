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

- **Rootless Docker per customer** (#389). Each Docker-enabled customer gets a *companion* account one
  uid block below their own, which runs their private rootless daemon as container uid 0 while the
  customer maps to container uid 1000 - the id stock images expect, so upstream compose files work
  unmodified. The customer never touches the companion: they reach the daemon through a group-owned
  socket in `~/.companion`, which lives inside their home so both travel as one backup unit. Verified
  end-to-end: the maps inside a container come out exactly as designed, and an unmodified image running
  as 1000 writes files owned by the customer on the host.

  `h-add-user-docker` / `h-delete-user-docker` enable and disable it; `h-delete-user` takes the companion
  with it, and `h-restore-user` re-creates it after a restore - the companion uid follows the customer's,
  which the identity allocator (#388) reassigns freshly, so it is recomputed rather than restored.
  Backups exclude the companion image store, since images are reproduced by pulling them; a 201 MB store
  turned a 222 MB home into a 21 MB archive.

- **Docker is installed from the official repo as a scoped addon** (`h-add-sys-docker` /
  `h-delete-sys-docker`, #389), replacing the inline `docker.io` install. The OS route cannot deliver
  this feature: neither Debian packages compose v2 at all, the OS `docker.io` spans 20.10 to 29.1 across
  the four targets, and `dockerd-rootless.sh` ships only in Debian's build. The exception stays scoped -
  the repo, keyring and pin are added by the addon and removed with it, so a box without Docker carries
  no Docker repo. The rootful daemon is disabled (service **and** socket, else socket activation brings
  it back), and the removal side refuses while customers still have it enabled unless forced. No cgroup
  delegation drop-in is installed: systemd already ships `user@.service` with `Delegate=pids memory cpu`
  on all four targets (verified down to systemd 252), which is what `--memory`, `--cpus` and
  `docker stats` need. Adding `cpuset`/`io` on the template would have widened every customer's session,
  Docker or not, for limits nothing asks for.

  The repo is deliberately **not** pinned. The condition it was added for - stop it shadowing OS packages
  - describes a risk that cannot occur: no OS package shares a name with it (Debian and Ubuntu carry
  `containerd`, `docker.io`, `docker-cli`, `docker-compose`, `docker-buildx`; the repo carries
  `containerd.io`, `docker-ce*` and the `*-plugin` variants). A pin could only have narrowed what the
  repo offers, never bounded it: apt's allow-list form does not work - a `Package: *` pin on the origin
  overrides any specific-package stanza regardless of order or quoting, which silently pinned `docker-ce`
  itself to -1 and would have blocked its security updates - and a name-based deny list cannot cover
  packages added later. `h-delete-sys-docker` still removes a pin from an earlier revision.

- **`h-check-sys-smoke` guards the identity allocator's preconditions** (#388). Not its output - panel
  users created before the change keep their old uid by design, so their position is deliberately not
  checked. What must hold is that `UID_MAX`/`GID_MAX` cap below the band (else a bare `useradd` can land
  inside it and collide with an allocation), that `SUB_UID_MAX`/`SUB_GID_MAX` cover the whole computed
  range (the shipped 600100000 would reject the companion subuid ranges of roughly 43% of usernames, and
  only at "enable Docker", long after the account was created), and that no two panel users share a uid.
  Verified in both directions: all four checks fail on a box without the guard rail and pass after it runs.

### Added

- **Panel users get their uid allocated from a dedicated band** (`func/identity.sh`). The username hash
  only picks where to start looking; the first free slot wins and is that user's uid from then on, as in
  classic HestiaCP. A taken slot is not an error - it reprobes. Customers occupy the odd thousands
  (11000-41999), each companion the interleaved block below (10000-40999), which reserves the second id
  rootless Docker needs (#389).

  Backups carry **no** authoritative identity and restores allocate a fresh uid rather than trying to
  reproduce one. Portability comes from `tar` resolving ownership by **name** on extract: the account is
  created before the unpack, so the files land on the new uid by themselves - measured, a file archived
  under uid 5001 extracts as 5099 once the name maps there. This is also why `h-backup-user` must never
  gain `--numeric-owner`: it pins the archived numbers and destroys exactly that property. HestiaCP
  archives need no special path, since their sequential uids are discarded like any other. The one case
  still needing a chown is a restore under a *different* username, where `tar` finds no local name to
  resolve to; the inherited `old_uid`/`new_uid` re-chown already covers it.

  Paired with `login_defs_guard`, which caps `UID_MAX`/`GID_MAX` below the band so a bare `useradd`
  cannot wander into it. That also raises `SUB_UID_MAX`/`SUB_GID_MAX`: the shipped default of 600100000
  sits *below* our highest range end (1048675999) and would have rejected the subordinate ranges of
  roughly 43% of all usernames.

### Changed

- **The /proc exemption gid is resolved at every boot instead of baked in at install time.** The unit
  carried the numeric gid that `procvis` happened to have when the installer ran. Delete and recreate that
  group - or let anything else claim the id - and the frozen number keeps exempting whatever now holds it,
  with nothing noticing. The unit now reads `/etc/group` in its own `ExecStart`, so the exemption is
  always whatever this host says right now, and a missing group means `gid=0`, i.e. nobody extra. That
  also settles the original name-vs-numeric argument: resolving per boot is exactly the behaviour a
  restored box needs. `gid=0` is deliberate rather than omitting the option - a remount that merely leaves
  `gid` out keeps the previous value (mount options are sticky) and `gid=` is rejected outright, so this
  is what actually withdraws a stale exemption on a running box.

- **`h-check-sys-smoke` verifies the live /proc state.** Failure of the hardening is fail-open and
  invisible to users, so the box now checks what is actually mounted: unit not failed, hidepid present,
  and the mounted gid still pointing at `procvis`. The last one caught a deliberately drifted gid during
  testing.

- **`/proc` hardening now lives in `/etc/fstab` instead of an `@reboot` cron job.** The old line remounted
  `/proc` with `hidepid=2` and re-applied it from `/etc/cron.d/hestia-proc` after boot, guarded by a
  `sleep 5`. Cron starts *after* most services, so that sleep papered over a window in which `/proc` was
  still unhardened; systemd applies fstab options before the services come up and closes it. The new
  `proc_hardening_apply` (`func/helper.sh`) also creates the `procvis` group and writes a **numeric**
  `gid=` exemption - a name would resolve to a different id on a restored box and silently exempt whoever
  holds it there. The entry is only persisted after the remount is proven to work on the running kernel,
  so LXC still degrades to the documented skip rather than to an fstab that fails at boot, and a
  hand-written `/proc` entry is left alone. Existing boxes are converted on upgrade. The exemption group
  is what makes rootless container runtimes work at all under hidepid (moby#45014), so this is a
  prerequisite for #389.

- **`sync-upstream.sh` names its source branch** and archives that branch instead of whatever the mirror
  happens to have checked out. A manual checkout in the mirror made one sync archive `1.10-beta`, which is
  *behind* `main`, so the upstream reference moved backwards while the commit still read
  "HestiaCP snapshot <today>" - only a version string deep in the tree gave it away. The subject now
  carries `(<branch> @ <sha>)`, and `UPSTREAM_BRANCH=` overrides it on purpose.

### Fixed

- **A domain name acting as a regex could delete another customer's cache zone and break nginx
  box-wide** (#583). Four sites removed lines from shared nginx pool files with the domain
  unescaped in a sed pattern - and the dot is a wildcard there, so deleting `a.b.com` also took
  `aXb.com`'s `proxy_cache_path` line. With a vhost still referencing the zone, every
  `nginx -t` fails from then on, for every customer. Two of the sites ran unconditionally on
  every domain delete or rename, so the trigger was not "a customer uses caching" but "a
  customer deletes any domain". All four now rewrite by literal match on the full
  `keys_zone=<domain>:` prefix (new `remove_pool_zone` helper; the `caching.sh` trigger inlines
  it, having no includes), and `h-add-fastcgi-cache` compares fixed-string so a cross-match can
  no longer suppress a zone append.

  The sweep for the same shape found the destructive write side beyond the pool files: record
  deletes and renames in `web.conf`/`mail.conf` (delete, rename, owner change), the webstats and
  letsencrypt queues, and every per-account edit of the mail files - `is_localpart_format_valid`
  allows dots, so deleting `john.doe` also matched `johnXdoe`'s lines. Domain-side patterns
  escape the dot (the only metacharacter a valid domain can carry); the account side switches
  to literal comparison outright (`remove_line_by_prefix`/`remove_exact_line`, ownership- and
  mode-preserving since `passwd` is dovecot:mail), so a later widening of the localpart charset
  cannot silently under-escape. `rebuild.sh`'s SSL-flag migration additionally anchors on the
  full `DOMAIN='..'` field, since its old pattern could also match inside another record's
  `CATCHALL` value. The read side (`grep` without `-F` in the object accessors) is deliberately
  not in this round - it has the blast radius of every command and is filed as #594; closing
  #583 does not close the class.

- **`h-change-sys-php` took effect one round late - and rebuilt the whole stock on the OLD
  version** (#585). The command rebuilt all domains first and switched `update-alternatives`
  last, so the rebuild still read the old default; the switch only materialised on the next
  unrelated rebuild. Measured: after `h-change-sys-php 8.2` on a 8.4 box, pool and vhost socket
  stayed at 8.4 until something else triggered a rebuild. The switch now happens before the
  loop, which also makes the "reload current version first" restart actually target the new
  version.

- **A missing web template wrote a silent 0-byte vhost** (#586, guard brought forward).
  `add_web_config` piped `cat template | sed` without checking the template exists - on
  apache-only, suspending a domain (`TPL='suspended'`, which has no apache template) produced an
  empty vhost that `apache2 -t` accepts, and the domain fell through to the box default vhost
  with the hostname certificate. It now warns on stderr and skips the write instead - a
  visible error, and deliberately not a hard abort, which would kill a rebuild loop over one
  broken record. The rebuild commands print a closing tally of skipped vhosts so the case
  survives a nightly run's log; the exit code stays untouched, because the web-model switch
  treats a nonzero rebuild as switch failure and one broken record must not veto it.

- **The packaged rootful daemon left a docker0 bridge behind** (#579). `apt-get install docker-ce` starts
  the rootful daemon as part of the package install, and it creates `docker0` before `h-add-sys-docker`
  disables it again - so the bridge stayed: empty, `down`, and holding 172.17.0.0/16. Reproduced on all
  four targets after a fresh v0.14.3 install, so it was a property of the install rather than a test
  artefact.

  It is more than untidy. `ip route get 172.17.0.2` answered `dev docker0 src 172.17.0.1`, so a route to a
  rootless container's address looked like it existed while the packets went nowhere - the containers live
  in their companion's own network namespace, which the host has no path into. That costs real time in
  exactly the area where per-user Docker gets debugged.

  Both `h-add-sys-docker` and `h-delete-sys-docker` now remove it, but only when no interface is enslaved
  to it - a host deliberately running rootful Docker keeps its bridge and its containers. A smoke guard
  covers the invariant, and skips rather than fails where the bridge is genuinely in use. Verified that
  rootless containers are unaffected: own namespace, published port bound and answering, egress intact.


- **Docker backups dropped named volumes** (#389). The exclusion that keeps container images out of a
  customer archive covered the whole Docker data root - and `volumes/` sits inside it, which is where a
  stock compose file puts its database. Reproduced: the volume content was on disk and the archive
  carried zero entries under `.local/share/docker`.

  What is kept is now a per-customer choice, made when Docker is enabled: `volumes` (the default) or
  `full`. Only those two boundaries are sound - the layer store and the metadata indexing it are
  separate directories, so keeping one without the other restores a store referencing layers that are
  not there. A missing or empty value resolves to `volumes`, which is the normal state rather than an
  edge case. One helper feeds both the pre-flight space check and the archive, since two hand-kept
  lists would drift into a check that refuses the wrong backup. A data-root directory the code does not
  recognise is still excluded, but reported in the backup log, so a future Docker layout change cannot
  quietly repeat this bug.

- **Two config repairs never ran** (#559). `syshealth_repair_web_config` tested `[ -z "$key" ]`, but the
  loop variable holds the key *name* and is never empty - so the condition was constant-false and the
  function had repaired nothing since it was written, while its mail siblings used `[ -z "${!key}" ]`
  and worked. Records therefore kept an old schema indefinitely, and any code expecting a newer key saw
  an empty value with no hint why.

  `user.conf` was worse off: it had no repair function at all. A key added to the known set reached
  existing customers only if someone happened to rebuild or restore them, and `update_user_value` is no
  help there - it rewrites an existing line and does nothing at all when the key is absent, silently.
  Both are fixed, and the user repair refreshes the key registry before reading it, because that file is
  written at install time and would otherwise be stale exactly where a newly added key matters.

- **A failing CLI call took the login page down, and let the post-password gates pass** (#575). The panel
  ran `exec()` and fed the result straight to `json_decode()`, then dereferenced it. `$return_var` was
  collected everywhere and evaluated almost nowhere. On a failed call the decode yields `null`, which
  behaves like an array until something insists on a real one: `in_array(x, null)` is a TypeError, so the
  login page answered **HTTP 500 with an empty body** - no form, no way in. Observed during a fresh
  install, where the panel is reachable before the sudo rules are final.

  Worse on the authenticated path: after the password was already verified, `LOGIN_DISABLED`, the IP
  allowlist and `TWOFA` were all read from that same result. An empty one made all three compare false,
  so a single failed CLI call would have let a disabled account in past its allowlist and its second
  factor. That path now fails closed.

  Both unauthenticated entry points (`login`, `reset`) go through a shared `cli_json()` helper that always
  returns an array; callers pick their own fallback. Also fixed alongside: the login language lookup read
  `$data[$v_user]` - the shell-quoted name, which never matched a key - so every login silently fell back
  to English; and an absent package value used to compare unequal to `"0"`, landing every user on the web
  list whatever their package held.

- **A dead SnappyMail mirror produced a green install with no webmail** (#573). The download came from the
  project's own host, which went dark in August 2026 - ICMP alive, TCP silently dropped. Three of our own
  gaps turned that outage into something worse than an outage: an unbounded `wget` (20 tries at a 900s
  read timeout) hung the installer for roughly 45 minutes, and because the script carries no `set -e`, the
  0-byte file `wget -O` leaves behind ran the whole rest of it to `exit 0` - dangling symlink, database
  created, `WEBMAIL_SYSTEM` claiming an application that had never been unpacked.

  SnappyMail now comes from the GitHub release for the version `share/manifest.json` already pinned (the
  value was read but never used for the URL), the fetch is bounded, and the archive is verified and
  unpacked before anything is removed - so an unreachable source no longer destroys a working install on
  the way down. `WEBMAIL_SYSTEM` is written on success rather than up front, and the smoke check names the
  cause instead of reporting an ambiguous 404.

- **The per-chain ban verdict was missing on the live-attach path.** `fw_jail_verdict` was wired into the
  full re-render but not into `fw_jail_attach`, which hardcoded `reject` for both families. fail2ban's
  `actionstart` reaches exactly that path, so on a fresh install every jail rule - `WEBSCAN` included -
  came up rejecting, and only picked up its `drop` if something later forced a full re-render. Found on the
  v0.14.1 fleet: deb12/deb13 happened to have re-rendered and showed `drop`, ub26 still carried the
  live-attached `reject`, from identical code. The two emitters now share one verdict table.

- **A deleted key in `hestia.conf` came back on the next syshealth run** (upstream #5584). The repair
  built `hestia.conf.new` with `touch` plus `>>`, and removed it only when it had actually rewritten the
  config - so a run that found nothing to fix left the file behind, and the next run appended into that
  stale copy. Reproduced: delete a key, run twice, the key returns. It now truncates and removes
  unconditionally. Matters here because `h-delete-sys-*` clears keys (`FIREWALL_EXTENSION`, the
  `DB_SYSTEM` tokens), so a removed component could look installed again. The same hunk fixes two inert
  patterns: `${rhs%%^\#*}` never stripped an inline comment (`^` is literal in a shell pattern) and
  `${rhs%%*( )}` needs `extglob` - both verified before and after.
- **A quote or backslash in a certificate field broke the SSL JSON the panel parses** (upstream #5585).
  Only `ISSUER` was escaped, from the earlier #5524 adoption; `SUBJECT`, `ALIASES`, the validity dates,
  `SIGNATURE` and `PUB_KEY` were interpolated raw. Applied to all three listers - mail, web and the panel
  certificate - and verified that the escaped values round-trip unchanged through a JSON parse.
### Added

- **DNSBL management from the CLI** (#555, upstream #5464). Exim has always consulted
  `/etc/exim4/dnsbl.conf`, but the list could only be edited by hand.
  `h-add-sys-mail-dnsbl` / `h-delete-sys-mail-dnsbl` / `h-list-sys-mail-dnsbl` (with `v-*` aliases, since
  upstream ships the same commands) manage it, validate the host against exim's own grammar - including
  the `host!=127.0.0.10` result filter - and restart exim. Unlike upstream there is no shadow copy under
  `conf/` and no revert-to-default comparison: exim reads exactly one path, and a second master would need
  syncing both ways. Preserving admin edits across an update belongs to #206. Deletion uses `grep -vxF`,
  so a host is matched whole and literally - removing `zen.spamhaus.org!=127.0.0.10` leaves a plain
  `zen.spamhaus.org` entry intact, verified live.

### Changed

- **Scanner bans drop, credential bans still reject** (#555). The renderer gave every jail chain the same
  `reject with icmpx type port-unreachable`. Upstream #5442 switches wholesale to `drop`; that is right for
  scanners and wrong for anything with a login behind it, where a silent black hole hides the far more
  common case of a phone retrying a stale mail password. The verdict is per chain now: only the
  scanner-signature jails drop. That needed a chain split, because seven jails shared `WEB` - three pure
  signature jails (`web-botsearch`, `web-badactor`, `web-exploit`) alongside the roundcube, SnappyMail and
  phpMyAdmin logins. The three moved to a new `WEBSCAN` chain on the same ports; everything else, including
  `web-authprobe` - whose own high `maxretry` exists for humans behind shared NAT - and `RECIDIVE`, keeps
  rejecting. Rendered document verified against nft 1.1.3: both chains match 80/443, with different
  verdicts.

### Fixed

- **Backup retention could delete another user's archives** (#556, upstream #4918). The retention list was
  built with `grep "^$user\." | grep ".tar"`, so listing user `foo` also matched `foo.bar.*.tar` -
  measured on a fixture: four files returned instead of two, including another user's backups and an
  unrelated `.tar.gz`. Since that list drives the rotation delete, `foo` hitting its retention limit
  removed `foo.bar`'s backups. Now anchored on the actual name shape (`user.YYYY-...tar`). New users
  cannot contain a dot, but the general user validator allows one, so a user restored from HestiaCP can.
  Applied to all seven affected backends - upstream fixed three, we also have sftp and rclone. The
  Backblaze path filters server-side by prefix and is left alone: the same class may apply, but it cannot
  be verified without an account.
- **The services list showed database servers that are not installed** (#556). `h-add-database-host`
  writes the type into `DB_SYSTEM` for a **remote** host too, so registering a remote PostgreSQL left a
  permanent `postgresql - stopped` row with panel buttons for a unit that does not exist. Reproduced and
  fixed live. The check fails open: a row is dropped only on a definite "no such unit", so an unexpected
  `systemctl` answer can never hide a running service.

- **The manual-ban chain picker offered a chain that no longer exists and hid two that do** (#555). It
  still listed `DNS` although bind9 is gone, and omitted `RECIDIVE`. Now lists the real set including
  `WEBSCAN`.

- **Restic restored only the first domain or database of a multi-object user** (#555, upstream #4987,
  #4986, #5100-adjacent). All three selective restore commands split a comma-separated list into a bash
  array and then iterated `$domains` rather than `"${domains[@]}"`, which expands to element 0 alone -
  measured: 1 of 3 domains processed, the rest silently skipped with a success exit. The mail command was
  broken differently: it never set `IFS` at all, so the whole list stayed one element and it tried to
  restore a domain literally named `a.de,b.de,c.de`. On top of that, web and database set `IFS=','`
  globally and never restored it, so every later word split in those scripts collapsed to a single word -
  which is what produced the malformed nginx configuration upstream reported. Splitting is now scoped and
  `IFS` restored immediately, membership is tested against an explicitly joined list, and the loops
  iterate the arrays. Verified across five selection cases per command plus a post-split word-split check.
- **A Let's Encrypt account whose user.key no longer matched failed forever** (#555, upstream #5294).
  `h-add-letsencrypt-user` exits early whenever `KID` is set, so a key replaced by a restore left the
  stored modulus stale and every later issuance was signed with a key the ACME account does not know -
  permanently, with no path back. The modulus is compared against the key on disk now and the account is
  re-registered on a mismatch; the `le.conf` rewrite also refreshes `EXPONENT`/`MODULUS`/`THUMB` instead
  of only `KID`, which is what left them stale in the first place.
- **The panel's default organisation could not pass its own validator** (#555, upstream #5483). Generating
  a self-signed certificate with the shipped defaults failed with `invalid org format :: MyCompany Inc.` -
  `is_common_format_spaces_valid` requires an alphanumeric last character, and our validator is stricter
  than upstream's here. Default is now `MyCompany Inc`.

- **The firewall list showed rules in the reverse of the order they are evaluated** (#554/#555, upstream
  #5080/#5466). The renderer emits by descending RULE id into one chain and nft takes the first match, so
  the highest id wins - but the panel sorted ascending, and its up arrow lowered a rule's precedence.
  Worse, the order depended on `userSortOrder`: one setting agreed with precedence, the other inverted it,
  so what the arrows appeared to do changed with a display preference. A ruleset is ordered data, not a
  sortable table, so the list is now always in evaluation order and ignores that preference. The arrows
  are deliberately crossed against the CLI verbs - `h-move-firewall-rule` keeps upstream's meaning of
  "up" (RULE-1) and the panel maps its visual up arrow onto it. Also fixed the move buttons themselves:
  `$move_down_enabled` was never set on the first row, so it inherited the previous row's value, and the
  disabled branch forced the arrow *visible* instead of hiding it - the bottom rule offered a "down" that
  the CLI then refuses. Verified end to end: clicking up on the 80/443 rule moved it from second to first
  in the live nft chain.

- **A valid host certificate looked invalid, so Let's Encrypt reissued it on every run** (#555, upstream
  #5397). `h-add-letsencrypt-host` validated with `openssl verify -CAfile <(openssl x509 -in $domain.ca)`,
  and `openssl x509 -in` prints only the **first** certificate in a file. A two-link chain therefore lost
  its root and verification failed with "unable to get issuer certificate", leaving `add_ssl=yes` so the
  certificate was requested again - burning the duplicate-certificate rate limit for nothing. Reproduced
  with a purpose-built two-level chain: the old form fails, passing the `.ca` file directly succeeds.
- **`useradd` ran on every rebuild and restore even when the account existed** (#555, upstream #5557),
  failing silently but writing a syslog line per user each time. All six callers of `rebuild_user_conf`
  are rebuild or restore paths, so this was the normal case rather than the exception; guarded with `id`.
- **`quotaon` warnings read as install errors** (#555, upstream #5465). It reports tmpfs it cannot stat
  and ext4 kernel-level quota support even on success. Both are filtered now; every other line and the
  exit status are untouched, verified against a stub that returns a non-zero status.

- **The panel served its own includes, templates and locale data over HTTP** (#554, upstream #5446).
  Nothing denied `/inc`, `/locale` or `/templates`, so unauthenticated requests reached them: the two
  `web/locale/*.sh` helpers and `hestiacp.pot` were returned as source, include-only PHP was executed, and
  `templates/includes/panel.php` rendered its markup outside any auth context. Measured impact today is
  low - the templates emit empty scaffolding, no data and no path disclosure - but the exposure is one
  refactor away from mattering, since any of those files gaining a `$_GET` read or assuming an
  authenticated caller becomes reachable without a session. The panel Caddy now answers 404 for those
  prefixes and for `*.map|log|sh|sql|bak|env`, placed first inside the existing `route` because `respond`
  otherwise sorts after `file_server`. Unlike upstream we do not deny `/src`: their panel root has a
  `web/src`, ours does not, so the rule would have no object. i18n is unaffected - it reads
  `languages.json` from disk, not over HTTP.

- **The Cloudflare realip fallback trusted a header the client controls** (#553). The installer rewrites
  `cloudflare.inc` from the CF API and skips that step silently when the fetch fails, so what ships in
  `share/nginx/` is what a box without egress ends up running - and it named the trusted *sources* but not
  the trusted *header*. nginx then applies its own default, `X-Real-IP`, which Cloudflare does not manage
  and forwards from the client verbatim, while `CF-Connecting-IP` is ignored outright. Measured on nginx
  1.26.3: `X-Real-IP: 1.2.3.4` became `$remote_addr` and propagated through `proxy_set_header` into apache
  `mod_remoteip` and the Roundcube jail, so a forged header could drive an arbitrary IP into the banlist
  and the nft set; conversely a real visitor behind Cloudflare logged as the edge, which fail2ban would
  eventually ban and lock everyone out behind it. The shipped file now carries
  `real_ip_header CF-Connecting-IP;`, and `h-check-sys-smoke` asserts the directive is present so the
  silent fallback cannot recur. The API-generated file was always correct - only the fallback was not.

- **One Cloudflare range in the panel's IP validator was wrong, and it was exploitable in both directions**
  (#553). `web/inc/cloudflare-ip.php` listed `131.0.232.0/22` where Cloudflare publishes `131.0.72.0/22` -
  a transcription slip in the hand-maintained list that replaced the vendored validator. Traffic from the
  real range was therefore not recognised as Cloudflare, so `get_real_user_ip()` attributed panel logins to
  the CF edge and fail2ban would ban the edge itself, locking out everyone behind it; meanwhile the range
  that is not Cloudflare's was trusted, letting whoever holds it forge `CF-Connecting-IP` on the login path
  and drive an arbitrary IP into the banlist. Both lists now match the published set exactly, and the
  header says to diff the live list rather than retype it. Found in the upstream 1.10 triage (#5273).

## v0.14.0 (2026-08-06)

The firewall release: the last subsystem still inherited near-verbatim from HestiaCP, rebuilt on nftables,
with fail2ban as a removable addon and IPv4/IPv6 parity throughout.

### Added

- **The firewall renders as one nftables `inet` table** (#495, #481), landed behind a seam whose only gate
  was byte-identical rule captures on all four targets. The rest follows from the shape rather than being
  separate features: one `nft -f` swap leaves no instant with an open policy or empty chain, where the
  iptables renderer set `-P INPUT ACCEPT` and flushed on **every** rule change; `nft -c` validates first,
  so a bad ruleset is rejected instead of half-applied; jails and bans render in the same transaction as
  the base rules, closing the window that left jails detached; persistence is the applied document,
  reloaded by an own unit, which retires the boot hazard where one unprovisioned set made
  `iptables-restore` reject the whole filter table and bring the box up unfiltered. A jail is a set plus
  one rule, so the multi-port delete bug dies with the shape that caused it. ipset is replaced by native
  sets, each rendered from a source-of-truth file so a table replace cannot lose its contents. Legacy
  iptables teardown at cutover is mandatory: iptables here is the nft shim, so a leftover ruleset lives in
  the same kernel backend and keeps being evaluated alongside ours.
- **fail2ban is a removable addon** (#497) and **the model is switchable at runtime** (#498).
  `h-change-sys-firewall-model` moves between `none` / `fail2ban` / `fail2ban+crowdsec` / `crowdsec` by
  orchestrating the addon commands. The live model is derived from artefacts on disk, and the target's
  components are added **before** the others are removed, so the box is never unprotected mid-switch.
  **crowdsec-only enforcement is wired, best-effort**: the L3 feeder denies CrowdSec's auth-family
  decisions only while fail2ban is present, so without it SSH and web brute force reach L3 at the feeder's
  ~45s latency, connections not cut. `req-limit` stays denied in every model, so a Layer-B 429 never
  escalates into a ban. Known gap: mail has no CrowdSec detection surface.
- **Layer-7 jails, so the fail2ban-only model has real web coverage** (#496, #531, #515). `web-botsearch`
  (probes for apps that are not installed), `web-badactor` (secret/config-file discovery), `web-exploit`
  (traversal, RCE payloads, appliance paths), `web-authprobe` (repeated **401 only** - a global 403 has too
  many benign causes), plus `roundcube-auth` and `snappymail-auth`. All read the per-domain `combined`
  **access** log, the only uniform source: nginx writes no error entry for a 404 and apache with php-fpm
  answers a missing `.php` with `AH01071`, so the distro's `apache-botsearch` cannot fire here at all. The
  404 is what makes botsearch safe on shared hosting - a domain really running WordPress answers
  `/wp-login.php` with 200. **Hard demarcation to Layer B**: signature-based only, never request rate; the
  rate limiter owns volume and its 429s never escalate. Thresholds count per source IP across all vhosts,
  so `web-authprobe`'s 20 is conservative, not high. Not a WAF: literal-string regex.
- **The whitelist is a first-class object** (#495, #496). `excludes.conf` suppressed *new* bans only, which
  left an already-banned admin locked out; it renders as an accept ahead of every ban match now, which is
  what makes it a recovery primitive. `h-add/delete/list-firewall-exclude` and a panel page give it a
  surface, adding an address **releases** an existing ban, and the list is mirrored into fail2ban's
  `ignoreip` as its own file - a generated block inside a shared one cannot be safely rewritten around
  admin edits. Not gated on `FIREWALL_EXTENSION`: it works without fail2ban, and hiding it would remove the
  one recovery path from the UI.
- **IPv4/IPv6 parity** (#496, #536, #545, #548). Service accepts never carried a family qualifier, so v6
  always reached the ports the jails protect - while the sets were `ipv4_addr` and the ban command
  validated v4, so a v6 brute force was logged, matched, then failed its `actionban` every time. A jail is
  two sets and two rules now, bans route by family, the CrowdSec L3 feeder covers both, a rule renders in
  its source's family, and the whitelist renders both. **Nothing presupposes a v6 stack** - the ruleset
  loads with no v6 address and with `disable_ipv6=1`. Verified on a real dual-stack host, measured from a
  second machine. Per-family split rules are a follow-up (#544).
- **Panel surfaces for firewall state** (#496, #527, #482): a jail-status page reporting configured
  **union** running jails, so a configured-but-stopped jail is visible instead of absent; the banlist lists
  CrowdSec's local L3 decisions beside fail2ban's with unban routed per source; the bot rate-limiting table
  got a toolbar deep-link, having been reachable but not discoverable.
- **Curated IP blocklists** (#481) in `share/firewall/blocklists.conf`, so adding a source is a data change
  rather than a PHP edit. `h-change-sys-blocklist-interval` sets one global refresh interval, validated as
  a systemd time span so a typo cannot leave the timer inert.
- **Smoke guards for the firewall datapath**, not just for a running daemon (#481, #495, #496, #520, #531,
  #537, #542, #545, #548): INPUT defaults to DROP; the backend binary exists; the persisted ruleset parses;
  ICMPv6 is accepted; every active rule renders and every referenced IP list is populated; no live jail
  chain lacks a record; running jails equal configured jails in both directions; no jail bans through a
  foreign action; every jail watches an existing file on the **current** web system; the two protection
  layers do not overlap; and two canaries replay real attack and injection lines through the deployed
  filters. `h-check-firewall-chain` replaces fail2ban's `actioncheck` grep of backend output, which would
  go stale the moment the renderer changed.
- **A CODEMAP consistency check** (#513), after the map drifted within a few PRs. Validates the JSON and
  that every structured path resolves. Local, not CI - the runner host carries no language runtime.

### Security

- **The webmail loopback listeners are restricted to the connecting UID** (#507). Roundcube and SnappyMail
  are plain TCP on `127.0.0.1`, so unlike the socket-based apps they had **no access control at all and any
  local user could reach them - customers included, who have shells here**. Worse, Caddy passes a
  client-supplied `X-Real-IP` through, so a customer could hand the app an arbitrary address and have a
  third party banned. IP filtering cannot separate two local users, so the rule keys on the UID.
- **`source_conf` no longer executes code smuggled into a config key** (GHSA-xffx-jj33-p2px class, #516).
  Keys were assigned with `declare -g $lhs=...` and `$lhs` was unvalidated, so `key[$(cmd)]='x'` in any
  parsed conf ran `cmd`. Keys are validated as plain identifiers now, checked against every writer in the
  code. `func/ip.sh` stopped eval-ing an IP conf as bash in the same pass.
- **The webmail vhost overwrites the client-IP headers it forwards** (#515), so a client cannot forge the
  address a jail would ban. The **Roundcube filter is hardened against username log-injection** in the same
  round: the username is logged verbatim, so it can smuggle a fake `X-Real-IP:` block; anchoring the
  genuine trailer to end-of-line backtracks the greedy match to the real one.
- **Ten panel controllers checked CSRF before the role** (#496). Both guards work, so the order changes no
  outcome today - it decides what is left when one of them has a bug, and this series produced two such
  bugs already.
- **CrowdSec's credential files are 0600** (#494); the packages generate them 0644 although both carry a
  machine password.

### Fixed

- **fail2ban had been installing a config it could not start** (#496). The installer copied `filter.d/*`
  and `jail.local` but never `action.d/hestia.conf`, so **6 of 7 jails were dead on every target** while
  the service reported healthy - the only live jail was the distro's `[sshd]`, banning into a ruleset we do
  not manage. The whole tree is installed now; our jails ship as `jail.d/hestia.local` so the package's
  file stays untouched; and the distro jail is disabled from our own config rather than by deleting a dpkg
  conffile, which the next update would restore.
- **The firewall broke IPv6 by dropping ICMPv6** (#534). The `inet` chain drops by default and accepted
  only IPv4 ICMP, so NDP and PMTUD died and IPv6 stopped working entirely: `ping6` at 100% loss, gateway
  neighbour `INCOMPLETE`. Invisible on the v4-only fleet, which is how it survived the migration. It also
  cured a ~12s SMTP greeting, where exim's reverse-DNS was timing out against unreachable v6 resolvers.
- **Restarting the firewall from the panel destroyed the ruleset** (#496). The service row is named after
  `FIREWALL_SYSTEM`, which became `nftables`, but six sites still matched a hardcoded `iptables` - so the
  row fell through to `systemctl restart nftables`, tearing down our table and loading the distro's
  `/etc/nftables.conf`. **Changing the panel port hit the same class** (#548): the command failed on that
  literal *after* writing the new port and *before* applying it, leaving the new panel port shut.
- **The panel answered a plain HTTP request with a bare 400** (#547) - "Client sent an HTTP request to an
  HTTPS server", i.e. typing the host without `https://`. The panel Caddy uses the `http_redirect` listener
  wrapper now and answers 308 to the `https://` URL on the same port. Scoped to `:8083`: applied globally
  it also wraps the plain-HTTP loopback webmail listeners and would 308 those.
- **A live web-model switch left the fail2ban web jails watching the old log dir** (#537). The running
  jails stayed on the live logs, so the box looked fine - but the **persisted** logpath is what fail2ban
  re-globs on restart, so every box that had ever switched web models was one restart away from silent
  Layer-7 blindness, from any cause.
- **fail2ban and CrowdSec doubled up in the combined model** (#542): the fail2ban web jails duplicated
  CrowdSec's http scenarios while CrowdSec kept detecting SSH brute force. Enforced in both directions at
  every transition now - **CrowdSec owns Layer-7, fail2ban owns brute force** - and the L3 feeder timer
  re-asserts it, so a manual `cscli hub upgrade` re-adding the ssh scenarios self-heals within a cycle.
- **The standalone CrowdSec add/delete commands raced a web-model switch** (#528). Both depend on the
  public web front and mutate nginx config, so a concurrent switch could flip the front between the
  apache-only refuse check and the wiring. They take the model-switch lock now, reentrant so the callers
  already holding it pass through.
- **A fail2ban restart wiped the persistent banlist** (#496): `h-delete-firewall-chain` is `actionstop`
  and deleted the records, so every stop, restart or upgrade discarded exactly the state the hestia ban
  action exists to keep.
- **A fresh install aborted silently in the fail2ban stage** (#520) - a grep over a whitelist a fresh box
  does not have, under `set -eo pipefail`; plus fail2ban refusing to start on an enabled jail whose logpath
  matches zero files, which proftpd and `web-botsearch` both hit. **And the installer duplicated config
  keys when a stage re-ran** (#523), because `wcv` appended unconditionally. Both were visible only from a
  genuinely fresh install, now a rule in CLAUDE.md.
- **The installer never named `nftables`** (#548). The renderer shells `/usr/sbin/nft`, but the package
  arrived only as a *Recommends* of `iptables` - which Debian's base image satisfies and Ubuntu's does not.
- **CrowdSec was never installed by a fresh install** (#186): the nginx-front gate read keys `main.sh`
  sources before the web stage writes them, so both were empty and the gate skipped the block. **The wizard
  never asked the fleet-mesh question** (#186, #485) - a `visible_if` on a sibling of its own combined
  screen can never be true. **And mailonly offered and default-enabled CrowdSec** (#529), which uncovered
  that jq's `//` treats a boolean `false` as absent.
- **`is_format_valid` failed silently when a name matched no variable** (#496) - it validates by *variable
  name*, so a renamed argument expanded to empty and empty meant valid. Fixing it at the root exposed **ten
  commands validating an argument they never assigned**.
- **Dead references from removed subsystems** (#548): the Server page's DNS handler exec'd a command
  removed with bind9; `h-refresh-sys-theme` called one that exists neither here nor upstream; a scheduled
  cron-job restore queued a misspelled command; `h-update-sys-defaults system` described a key set 43
  entries behind reality; a `disabled` attribute was built in a ternary whose result was never echoed.
- Smaller: `h-delete-firewall-ipset` never refused to remove a list still in use, because `check_result $?`
  sat inside the `then` branch (#495). The shipped "Block Malicious IPs" preset pointed into the `install/`
  tree dissolved in #119, so it always failed (#481). Blocklist names were double-escaped in the picker
  (#481). `h-add-firewall-chain` read the panel port from an nginx.conf Caddy had replaced (#496).
  `h-delete-user-backup-exclusions` wiped the CRON exclusion on every delete. The roundcube logrotate entry
  conflicted with the package's and won only by filename sort order (#508). Unbanning a CIDR never reached
  fail2ban, a v6 own-IP would have stopped every firewall update, and v6 IP lists were accepted and blocked
  nothing (#548).

### Changed

- **`iptables` and `ipset` are no longer installed** (#548); nothing calls either binary since the renderer
  moved to native sets. `fw_legacy_teardown` is guarded on the binary, and `docker.io` depends on iptables
  itself.
- **`FIREWALL_SYSTEM` reads `nftables`** (#495), since the value names the backend. Pre-v1, so no migration
  is owed - but the rename is what let the panel destroy a live ruleset, above.
- **Blocklists refresh on a systemd timer, not the daily cron queue** (#481) - inspectable, `Persistent`,
  and spread across a fleet with `RandomizedDelaySec`.
- **Adding, renaming or restoring a web domain tells fail2ban about its log** (#496); the glob is expanded
  once at jail start, so a later domain went unwatched until the daemon next restarted.
- **CrowdSec is one three-way model question instead of two** (#186), spanning three supported models
  rather than four combinations. `h-change-sys-crowdsec-mode` switches at runtime (#494), including the way
  *back* to the community blocklist, which had no implementation at all.
- **PROVENANCE reconciled against `upstream/hestiacp@ca19b9f`** (#548): 38 files had no entry and every
  aggregate was stale - `share/` claimed 21% weighted divergence where its own numbers give 7%.
  `source_type` was left untouched; 60 entries disagree with the manifest's own rule, which is a labelling
  decision rather than a number (#551).
- **CODEMAP's firewall and fail2ban entries are current again** (#496); the firewall entry still gave
  `FIREWALL_SYSTEM` its pre-swap value - the exact staleness that let the panel destroy a ruleset.

### Removed

- **The mysqld jail** (#496). 3306 is not in the shipped ruleset, so MariaDB is reachable only from
  loopback and the box itself - both of which `h-add-firewall-ban` refuses to ban, so the jail could only
  match and then decline to act.
- **`h-refresh-sys-theme`** and its symlink (#548): it called a command that does not exist, nothing called
  it, and nothing here caches a theme for it to regenerate.
- **The UA-based `web-badbots` jail** from the L7 proposal (#531) - user-agents are trivially forged.

## v0.13.0 (2026-08-03)

### Added

- **CrowdSec** (#186, #123) - an nginx-gated, removable addon in four layers, offered in the wizard only
  where nginx is the public front. **Layer A**: an own dependency-free LuaJIT bouncer queries the local
  LAPI per request and answers 403, rendered per web model plus a per-domain fragment. **L3**: an own
  `cscli` -> ipset feeder on a timer fills a `hestia-crowdsec` DROP chain, so the same decisions are
  dropped at SYN; `h-update-firewall` stays the sole writer and the chain `RETURN`s loopback + RFC1918
  first. The OS `crowdsec-firewall-bouncer` is deliberately unused - 0.0.25 nil-panics in its ipset path,
  verified unusable on all four targets. The feeder filters by DENYlist after an allowlist was found to
  silently drop advisory-named web exploits. **Fleet-mesh**: peers with no central LAPI, each publishing
  its own local web-tier bans and importing the union of its peers' as L7-only, hardened against a bad
  peer (validation, per-peer and total caps, `hestia-mesh:<peer>` attribution). **Transport**: two boxes
  pair over the panel port and then pull each other's list on a timer. **A pairing needs an admin on both
  boxes** - the code is 100 bits, single-use, 15 min, dead after 5 wrong guesses, and `/mesh-pair.php` is a
  plain 404 while none is live; the long-lived artefact is a per-peer token, TLS is pinned by SPKI recorded
  at pairing, and secrets never ride in argv. The LAPI stays loopback-only throughout.
  `crowdsec_apply` removes `nginx-req-limit-exceeded` on purpose: it fires on our own Layer-B 429 and
  turned deliberate throttling into bans for good bots and shared IPs.
- **Server-native web bot rate-limiting** (#482) - a standalone Layer-B subsystem (`func/botpolicy.sh`),
  independent of CrowdSec and available on any web install. Bot families are throttled with native nginx
  `limit_req` / apache `mod_qos` (429); **humans are never limited** and malicious traffic stays CrowdSec's
  job. An admin family table (10 slots, 8 curated) carries a UA match, `lenient`/`strict` rates and an
  enabled flag; per domain each family is `off`/`lenient`/`strict`, customer-editable. nginx keys per
  family **per domain** so customers do not share a bucket; apache mod_qos counts per client IP. Default
  off. Known limitation: matching is on the spoofable User-Agent.
- **Shell lint gate** (#477), check-only, in two tiers because the tree carries ~240 inherited HestiaCP
  warnings that are their own cleanup job: tier 1 is shellcheck at `severity=error` over the whole shell
  surface, tier 2 at `>=warning` over the files a change touches. Both judge **regressions, not
  inheritance** - each changed file is compared against its base version, so touching a legacy file does
  not inherit its warnings. `.gitea/tools/lint-shell.sh` holds the logic so CI and a developer run
  identical checks. The workflow is deliberately minimal: no actions (the runner host has no node by
  design), a temporary clone, `contents: read`, no secrets, no installs, no writes.

### Security

Adopts the relevant fixes from the HestiaCP 1.9.8 release (#471).

- The user editor blocks a non-`ROOT_USER` admin from modifying the `ROOT_USER` account on the POST/save
  path, not only the page render, and keys the guard on `$_SESSION["ROOT_USER"]` instead of a hardcoded
  `admin` (HestiaCP #5547 / GHSA-c69h-jgpw-h9cj). A crafted POST could otherwise change the root account's password or
  role. The guard fails closed when `ROOT_USER` is unset.
- Panel notifications are HTML-sanitized before storage (HestiaCP #5548 / GHSA-3g4r-pfpf-8697). `NOTICE` renders as raw HTML
  via Alpine `x-html` and callers interpolate into it, so the body now passes an allow-list sanitizer -
  own and dependency-free, since HestiaRE ships no Composer. `TOPIC`/`NOTICE` also gained CR/LF and length
  validators, and the shell `send_notice()` helper goes through the same path.
- Restore scheduling no longer lets an argument inject into the executed restore queue
  (GHSA-2xw3-7h62-v4gf). `h-schedule-user-restore-restic` wrote `$snapshot`/`$value` single-quoted into
  `queue/backup.pipe`, so a `'` broke out for root RCE.
- The admin debug panel escapes its variable output (HestiaCP #5550) - keys and string values were echoed raw (reflected XSS).

### Fixed

- Installer: an optional component could end up flagged on with its package absent (#480). Component
  installs ran `hestia_apt ... || true`, so a held apt lock - common right after first boot - failed the
  install and the `|| true` swallowed it. Three changes, since none alone suffices: a lock timeout, masking
  the auto-apt units for the installer's duration (restored from an `EXIT` trap, and only units it masked
  itself), and verifying against dpkg that the package actually landed.
- `h-list-sys-php` no longer lists the isolated panel FPM pool as a pseudo-version `hestia` (#464).
  Consumers build `php<v>-fpm` from the list, so the stray entry produced `phphestia-fpm`, broke
  `h-restart-web-backend` on every box and rolled back every live web-model switch at its health gate.
- Web-model switch (#120, #466): rollback uses `reload-or-restart` instead of a hard restart, so a failure
  before the restart stage cannot kill a server still serving its loaded config; cleanup also removes the
  departing model's webmail vhost source, which previously left a stale conf behind.
- Directory listing works under nginx-only (#468) - it only ever flipped apache's `Options Indexes`, so
  `DIR_LIST='yes'` was a silent no-op. nginx gets `autoindex on;` via an include fragment.
- `h-list-mail-domain-ssl` JSON escapes the certificate issuer (#471, HestiaCP #5524); a `"` or `\` in the issuer DN
  produced invalid JSON.
- Bot rate-limiting (#482): a disabled or deleted family left **dangling zone references** in the
  per-domain fragments, so `nginx -t` failed and blocked the next reload for every domain on the box.
  Fragments now skip families that are gone, the apply command re-renders every throttled domain before
  testing the config, and deleting a family strips it from every domain. A new smoke guard asserts every
  per-domain policy fragment is included by every customer-domain template - one missing include is a
  silent bypass, not a visible failure.
- CrowdSec (#186): re-adding no longer fails on the saved-state config. `/etc/crowdsec` is kept on delete,
  and a dpkg conffile prompt on `config.yaml` used to EOF under `noninteractive` and leave the package
  half-configured; both install sites now pass `--force-confdef --force-confold`.

### Changed

- PROVENANCE recomputed for all three folders against `upstream/hestiacp@ca19b9f`. 74 files accumulated
  since the last run are now listed - the CrowdSec, bot-limiting and mesh commands with their assets and
  panel routes, all `eigenbau`. Percentages are integers again, files identical to upstream are recorded
  as 0% rather than left unmeasured, and the two genuinely binary blobs are flagged instead of carrying a
  meaningless churn number. Vendored paths stay out - they belong to `VENDORED.json`.

### Removed

- The orphaned bind9/named and vsftpd server-config views (#471). Both are permanent ground-rule removals,
  the views were unreachable, and the vsftpd one called a command that does not exist. The stale `vsftpd`
  branch in the FTP-account toggle went with it (`FTP_SYSTEM` is only ever `proftpd`).
- 36 app-specific web templates (72 files) that the removed Software/App Installer had seeded. With no
  installer to place these apps they were dead weight; the standard set stays. The list is
  directory-driven, so panel and CLI follow automatically, and any pruned template can be re-imported
  from `upstream/hestiacp`.

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
