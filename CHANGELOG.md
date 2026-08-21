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

- **A lint run that measured nothing reported the cleanest possible result** (#770). The format
  ratchet compared how many files are exempt now against how many were exempt on the base branch,
  and an unreadable base counting zero failed closed - but a current side counting zero did not,
  because zero is not greater than zero. With the exempt list now empty, zero is also the expected
  result, so a run that read no files at all was indistinguishable from a clean one. Both sides now
  report how many files they looked at, and a side that looked at none fails.

### Changed

- **The 32 shell files the format check had exempted are formatted** (#770). They were unformatted
  before the gate existed, so it skipped them - which left the check blind on exactly the files most
  likely to need it, `include/main.sh` and `install.sh` among them. The list is now empty and every
  shell file is measured. Whitespace and a few redundant semicolons only: each file was compared
  against its previous revision in minified form, and the fleet smoke run passes on all four targets.

### Removed

- **The backup pages no longer offer DNS** (#713). Zones stopped being backed up when the
  subsystem went, but the panel kept a DNS column, a list of zones with checkboxes and per-zone
  restore links, and the restore handlers still accepted what those checkboxes posted - all of it
  fed by a field the backup fills with nothing. The `[DNS]` argument of `h-restore-user` stays, as
  does the empty `DNS=` in the backup record: both are HestiaCP compatibility, and the panel now
  passes the argument unset rather than offering a way to fill it.

### Fixed

- **The shell format check passed on files it had never measured** (#713). It compared a file
  against its state on the base branch by piping that revision into `shfmt`, but `shfmt` picks up
  `.editorconfig` from the file's path and content on standard input has none - so the base was
  judged by the tool's own defaults, came back unformatted whatever it contained, and every
  freshly introduced misformat was waved through as inherited debt. The settings are now passed
  explicitly, and the set of files the check exempts is counted on both sides: it may shrink,
  never grow.

- **Saving the backup exclusions cleared the cron exclusion** (#768). A customer set to skip their
  cron jobs kept that setting only until someone opened the exclusions page and pressed save: the
  form had no cron field, so the handler wrote an empty one over it, and the next backup silently
  carried the jobs again. The page now offers the field and the lister reports it. A single job name
  is refused rather than stored: the backup tests the value only against `*`, so anything else would
  have been accepted, shown back and then ignored.

- **A restore that could not take a whole section reported success** (#754). Three databases handed
  to the customer because the box has no database engine ended in a zero exit status, while a single
  database that could not be loaded - the same loss reached by another branch - ended in red. Which
  one you got depended on whether the section was entered at all, not on what the customer was left
  with. A section this host has no subsystem for now counts as a part that did not come back, and so
  does a docker setup that could not be re-enabled. What is handed over because this product does
  not do it at all - DNS zones - still does not colour the status: a HestiaCP migration is not a
  failed restore for carrying zones we never claimed to keep.

- **A restore under a different customer name deleted the source customer's database and reported
  success** (#764). Restoring an archive under a new name on the same box - what a careful operator
  does as a rehearsal before migrating - dropped the live database the archive came from, left its
  record claiming it was still there, and ended with a zero exit status. The deletion took the name
  out of the **archive** while everything else worked on the target's name; where the two coincide,
  which is every same-name restore, nothing showed. The name to clear now comes from the customer
  being restored into, and the check that it belongs to them sits in the delete itself rather than
  in its callers, so the next caller cannot arrive without it. A refusal is named and counts as a
  part that did not come back.

- **A second FTP account came back under the old customer's name** (#764). The conversion replaced
  the first occurrence of the source prefix in the whole colon-separated field, so the second
  account kept it - and a name carrying the prefix in the middle lost it from there instead. Each
  entry is converted on its own now, anchored at the front, the way the database name already was.

- **A restore dropped the customer's panel notifications without a word** (#713). The backup copied
  a fixed list of names out of the customer's data directory, and a list only ever covers the files
  that existed when it was written - `notifications.conf` never made it in. Both sides now walk the
  directory and skip a named set instead, each entry with its reason next to it, so the next file
  added there travels by default rather than by amendment. What stays out: the customer's restic
  repository password, the records the sections rebuild themselves, and the panel login history,
  which is a per-box view of who was signed in - down to IP addresses, browser fingerprints and
  session ids - rather than something a customer takes along.

- **The restore report says that webmail settings and address books are not in the archive** (#713).
  They live in one table set per box, shared by every mailbox, so the server backup carries them -
  but silence on the point made "my contacts are gone" a discovery for after the restore.

- Smaller: a new account no longer gets an empty `dns` directory and `dns.conf` for a subsystem that
  was removed, and a MySQL password statement can no longer survive from one database into the next
  in a rebuild loop (#713).

- **A restore under a different customer name pointed the site's password protection into the old
  customer's home** (#756). The `.htaccess` fragments travel inside the archive with an absolute
  path written into them, and the rebuild only wrote its own when none was there - which after a
  restore is never. Where that path did not exist the domain answered 403 even with the right
  password; where it did, the site was gated by **another customer's** password file. Both files
  are now derived from the record on every rebuild, so they name the customer who actually owns the
  domain, and an account the record no longer knows is dropped from the file instead of living on
  in it. An account the record names but carries no hash for is named and left out rather than
  written as a line that can never match. Where the record names no account at all the fragments go
  rather than staying behind, and the pair belonging to the web server this host does not run is
  dropped too - it is inert until the web model is switched, and then it is not.

- **A restore over an existing customer called a fresh archive "pre-#120" and said nothing about a
  web model that really did differ** (#753). The banner inside the run read a member that is only
  unpacked when the account is created, so on the most common path it never saw it. It is gone
  rather than repaired: the preflight report already carries the same sentence, from the probe, and
  before anything is written - two reports of one fact are two chances to disagree.

- **The consent error pointed at a token that could not satisfy it** (#755). Refusing on
  `php-fallback` while suggesting `all` sent the operator in a circle, because `all` deliberately
  does not cover it. The message now names the tokens that were actually refused, says what `all`
  stands for, and the command's own example no longer teaches the form that does not work.

- **A restored domain kept its CrowdSec or bot-limit setting on a host that cannot render it, and
  the report called the archive fully restorable** (#755). Those protections survive as settings on
  purpose - they take effect if the module arrives later - but silence made an inactive protection
  look like a live one. The report names them, asking the renderers' own capability checks rather
  than a second copy of the condition. It reads them only where the module is installed, so the one
  function whose job is to be honest before anything is written cannot be what fails without it.

- Smaller: a zstd database dump no longer prints its size into the middle of the restore log, where
  it read like an error, and a `*` in an archived bot-limit value no longer expands against the
  working directory (#755).

- **Rebuilding a single database set the customer's database count to 1** (#757). The singular
  command had inherited the accumulator of its plural sibling without that command's flush in front
  of the loop, so it wrote "whatever the variable held, plus one" as the customer's total - and the
  next deletion took it to 0, which is what the panel and the counter check then showed. Disk usage
  carried the same shape, claiming one database's usage as all of it. A command that touches one
  object no longer claims a total; the plural form owns the counting and the disk queue owns the
  usage. The counter check now also watches the suspended mirrors, which are derivable from the
  records like the rest and were the one group in its exclusion list without a reason - so a value
  knocked out of step becomes visible instead of waiting for somebody to rebuild the customer.

- **A PostgreSQL database came back from a restore with its password destroyed** (#752). The rows
  all returned and the customer's application could no longer connect, which reads as a broken app
  rather than as a restore - and on a same-box restore nothing said a word. The hash was being
  parsed out of `psql`'s aligned table: the backup took the first line, which is the column
  heading, and the create and password-change paths filtered for `md5`, which matches no SCRAM
  hash at all. Every pgsql record was therefore written with an empty password, and the rebuild
  wrote that emptiness into `pg_authid`. The hash is now read as a value, an empty one never
  replaces a credential that works, and the run says when it kept one. The same guard covers MySQL,
  which was only safe because its own read path happened to work.

- **A restored PostgreSQL role could not log in at all** (#752). The rebuild created it with a bare
  `CREATE ROLE`, which is `NOLOGIN` in PostgreSQL - so a restored database was unreachable whatever
  its password said, and that is why the empty password went unnoticed for so long. Roles get
  `LOGIN` as they always did on the add path, but only together with a password: a role that has
  none stays shut, because turning it into a login role would open it wherever `pg_hba.conf`
  carries a `trust` line.

- **A database restored onto another host without a password now says so, and the run ends
  accordingly** (#752). The two cases had been reported with one sentence: on the same host an
  existing password is kept, on a fresh host - the migration case - the account is created without
  one and nothing can connect to the database at all. Saying "kept unchanged" there claimed a
  credential that never existed. The second case is now named as such and counts as a part that
  did not come back, so a queue or a script sees it rather than finding it in the log.

- **A customer whose `user.conf` lost a package limit was locked out of their own package** (#711).
  An absent or empty limit is not a limit of zero, but that is how the comparison read it, so every
  attempt to add a web domain, mail domain, database or cron job was refused with a message blaming
  the customer's package - measured, with no domains at all. The limit is now taken from the
  customer's package file when the record cannot answer, and a defect in the record never presents
  itself as a limit somebody has hit. `user.conf` repair seeds real values from that same package
  file instead of inserting empty ones, and says so rather than guessing when the package is gone.

- **`user.conf` could end up with the same key twice** (#711). The repair that ran before the
  generic one addressed its insert with a bare `/MAIL_ACCOUNTS/`, which also matches
  `U_MAIL_ACCOUNTS`, so `RATE_LIMIT` was written after both - and `FILE_MANAGER` after both of
  those. Which value then won depended on the reader: `source_conf` keeps the last, `grep | head -1`
  the first. The two repairs are now one, and it also removes the extra lines a box is already
  carrying - keeping the one `source_conf` was using, and saying which - because a duplicate that is
  only prevented from now on stays on every box that already has it.

- **A user's login shell could be set from the caller's environment** (#711). Where the record had
  no `SHELL`, the rebuild fell back to the ambient `$SHELL`, and where that was unset `grep -w ""`
  matched every line of `/etc/shells` - handing `# /etc/shells: valid login shells` to `useradd`.
  The shell now comes from the record, falls back to a named default off the curated allowlist, and
  can never be a comment line.

- **The config repair worked against a smaller key set than the code writes** (#711). Every field a
  command stores with `add_object_key` or `update_object_value` has to be in `syshealth_known_keys`,
  or the repair functions call a record healthy while fields they never heard of are missing from
  it. Web records gain `CROWDSEC`, `BOTLIMIT`, `ALLOW_USERS` and `LETSENCRYPT_FAIL_COUNT`; mail
  records gain `LETSENCRYPT_FAIL_COUNT`, the six `U_SMTP_RELAY*` and the five `U_SPAM_*` fields. A
  value that is already set is never touched, and an empty one is inert for every one of these
  fields - checked per field rather than by analogy. `sanitize_config_file` clears exactly the
  registered keys between two objects, so the unregistered ones stayed set for the next one; no
  current path acts on that, because the readers take the record and the one function that reads
  such a value as a plain variable only ever handles one domain per process, but it stopped being
  something the caller's process model has to keep true.

- **The webmail store on a box without a database engine was not backed up** (#710). Where there is
  no engine, Roundcube keeps every mailbox's identities, address books and settings in a SQLite file
  under `/var/lib/roundcube/db/` - which is exactly the state the server backup exists for, and the
  only one it was missing. It is snapshotted with SQLite's own `.backup` rather than copied, because
  these run in WAL mode and a plain copy taken mid-transaction can lose commits that are already
  durable. On the way back the archived file is verified whole before the live one is touched at
  all, so a damaged archive leaves the running webmail alone, and the replacement is a single
  rename that carries the existing owner and mode. Where the `sqlite3` client is absent the restore
  declines rather than installing something it cannot check - unlike a database too broken to dump,
  a missing client is a prerequisite one `apt` away.

### Added

- **The state that belongs to the box has its own backup** (#710). The webmail databases hold every
  mailbox's identities, address books and settings in one table set, so no per-customer archive can
  carry them without carrying other customers' rows; the same is true of `hestia.conf`, the hosting
  packages and the firewall sources. `h-backup-server` takes them, `h-list-server-backups` shows what
  each archive holds, and `h-restore-server` puts back the components that are named. There is
  deliberately no whole-archive verb: restoring all of it would overwrite the configuration of a
  running host in one step, so a run without a component refuses before it writes anything. Naming a
  component says which live state to replace, not that replacing it is intended, so each one is
  consented to before the first write - the question names the paths and databases this host would
  actually lose, and without a terminal the consent has to arrive in the argument or nothing is
  written. A database is dropped and recreated rather than loaded on top, because a table the
  archive predates would otherwise survive into a schema that never existed; a dump that did not
  finish is refused before the target is touched, on the way in as well as on the way out, and a
  copy of the live database is taken first so that a load which fails for some other reason is
  rolled back instead of leaving a half-built schema. A run that did not restore everything says so
  in a closing summary and ends in a failing exit status, rather than reporting success with the
  detail buried in warnings. What a
  box can back up is derived from what it actually has, never from a fixed list - a target without a
  database engine produces a webmail component of directories and no dumps. The archive is root's
  alone at 0600, because `/etc/roundcube` carries the `des_key` and the database password.

- **An archive put into the backup folder by hand becomes visible to the panel** (#709).
  `h-add-user-backup` writes the `backup.conf` record a foreign archive never had, and writes it
  from the archive's own members rather than from its name - the name is a claim, the members are
  the finding. Until now a HestiaCP archive could only be restored from the command line, and
  nothing said so. It takes a basename and no path, resolves only inside the backup folder, and the
  record is marked `ADOPTED`: the nightly rotation prunes by age and would otherwise take the
  migration source first, and deleting the entry now forgets the record while leaving the operator's
  file where they put it.

- **What a restore cannot put back is handed to the customer instead of left in the archive** (#708).
  DNS zones with their records and rendered zone files, custom web templates, and the raw members of
  any section this host has no subsystem for - a database dump this box cannot load among them - land
  in `~/leftovers/<timestamp>/`, owned by the customer at 0700, with the loss report beside them. A
  dump in hand is somewhere else in minutes; inside an archive it has to be found first. `leftovers`
  joins `conf`, `web`, `mail`, `tmp` and `dns` as a reserved name in the home: a directory a customer
  had under that name before would stop being archived.

  Same derivation as the loss report, so the two cannot drift, and the same consent rules as every
  other section. "Nothing to hand over" is printed rather than left as silence, and a run that named
  objects says so instead - it was asked for those, not for the rest of the archive. The directory is
  on the backup's fixed exclusion list, so it does not grow into the next archive.

- **An archive says who wrote it** (#707). `hestia/origin` carries producer, version, format,
  compression mode and timestamp, and the report prints them. It is forensics, never detection:
  no archive written before today has one and a HestiaCP archive never will, so anything keying on
  it would be deciding by its absence. Where it disagrees with the members - it claims gzip and the
  archive is zstd - the members are what the restore acts on and the report says both. Verified
  inert in the other direction on a real HestiaCP 1.10.3 box: a HestiaRE archive restores there
  cleanly and the extra member is ignored.

- **A backup archive can be inspected before a restore touches anything** (#707).
  `h-list-backup-contents` reads the archive FILE rather than the `backup.conf` record, so an
  archive put into `/backup` by hand - a HestiaCP one - can be looked at at all; until now nothing
  could see it. The same report runs as the restore's preflight, before the first write.

  It answers what the restore used to answer only by doing it, or not at all: DNS zones **by name**,
  because that is the question somebody moving off HestiaCP is actually asking; sections that would
  be dropped in full because this host has no such subsystem, **with the object count**; templates
  and PHP versions that will be rewritten; record keys and package limits this host has no use for.
  An empty report is printed in words - "nothing falls away" and "the probe read nothing" had no
  way of looking different before.

- **A database whose engine this host does not run is named, and skipped instead of fatal** (#707).
  `DB_SYSTEM` is a comma list - a HestiaCP box routinely carries `pgsql,mysql` - and the import was
  a `case` over the type with no default branch, so a postgres dump on a MariaDB-only host took the
  whole run down at that object. Measured against a real HestiaCP archive: three web domains and two
  mail domains were already written, and the second database, every cron job and the entire home
  directory never arrived. The preflight names it before the first write, and the restore finishes
  everything else and then exits non-zero saying what did not come back.

- **A restore asks before it writes, section by section** (#707). The only question it used to ask
  sat inside the web section, so refusing it left the account, its data directory and its home
  behind - a customer that exists and holds nothing. Consent is collected before the first write
  now, and the run either has it for everything it plans to do or it has not started at all. Naming
  objects in a selector is itself the consent for that section, so the panel's per-object restore
  and the four `h-restore-*` wrappers work exactly as before; with a terminal the run prompts per
  section; and where nobody can be asked - the queue, the panel - the consent travels as a `CONSENT`
  argument from a closed set (`all`, the five sections, `php-fallback`). An argument rather than an
  environment prefix, because the queue line is executed by bash and an env prefix in front of it
  would put operator input into a command line (#661). Sections this host cannot serve are never
  asked about; the report already says they will be dropped.

  `all` deliberately does **not** cover `php-fallback`: moving a customer's domains onto a different
  PHP version is not "restore everything", and #591 exists because that used to happen quietly.

### Security

- **A restore selector reaches the queue through a closed character set** (#707). The five selectors
  are spliced into the line `h-update-sys-queue` runs through `bash` as root, and they only had a
  deny list of three characters in front of them - a pipe, a semicolon, a backtick and a `$(` all
  went in. Not exploitable: they land inside single quotes and the one character that ends those was
  already refused. But a deny list holds only as long as the quoting around it does, and it was a
  too-wide allowed set that put a pipe on that line once before. A home entry with a space still
  passes, because `my documents` is a name a customer can really have; one with a tab is refused,
  because `tar` prints that escaped in the listing the restore matches against, so such a selector
  used to be accepted and then quietly select nothing.


- **The backup exclusion list is read through the hardened reader** (#706). Three places still used
  a raw `source` on a file the customer's panel writes, while the fourth already used `source_conf`
  - the same shape as the upstream advisory that reader exists for. `add_object_key`'s existence
  check is anchored too: unanchored, a key that is a suffix of one already in the record counted as
  present and was silently never added.

- **The listers print their values with `printf`, not by splicing them into an `echo`** (#728). The
  JSON emitters built their output as one big quoted string with `'$VAR'` holes, which leaves the
  value unquoted - so the shell split and globbed it *after* `json_escape` had run. Whitespace runs
  inside a value collapsed, and a value holding a `*` was replaced by the filenames in the working
  directory: text that never went through the escaper, so a filename containing a `"` opens a
  second key in the document. 53 emitters, 693 values. Where a lister happened to have set
  `IFS=$'\n'` for an unrelated loop it was inert - by luck, not by design.

- **A record is quoted on its way into the parser, at every call site** (#723). Forty-six `h-*` and
  helper calls handed the record over unquoted, so the shell split and globbed it before either
  parser saw a character: a cron record holding `MIN='*'` picked up any file named `MIN='...'` in
  the working directory and the parsed value became that filename. A customer only has to create
  one such file in a directory an admin later runs a command from. Two of the forty-six are shared
  helpers - `get_object_values` and `get_domain_values`, the latter with 42 calling files. Unquoted
  also collapsed runs of whitespace inside a value.

- **A failing `mktemp` no longer lets the panel write into an unset path** (#703). Thirty save
  routes took `exec("mktemp")` and used `$output[0]` without checking it, so a failure produced an
  empty path: `fopen()` on it aborts the request with a fatal, and the certificate or service
  config the route was about to hand to the CLI is gone with it. They now go through
  `private_tmpfile()` / `private_tmpdir()`, which return `false` and make the caller branch. The
  login route is covered too - it wrote the password hash the same way. The backup exclusion list
  also stopped leaving its tempfile behind.

- **An archived record is checked before it is trusted** (#705). Appending the archived line
  verbatim is what preserves the fields, but it also puts a line this box did not write into a live
  config, and not every reader goes through the tokenizer - some parse with `sed` on quote
  boundaries, and the listers splice into JSON. A record must now be exactly `KEY='VALUE'`, with the
  quote, backslash, backtick, doublequote and newline refused; `$` stays allowed because the crypt
  hashes carry it. Mail records were appended with no check at all before. The three archive parses
  are quoted now - unquoted, the archive content word-split and globbed before the parser saw it.

### Removed

- **Vesta archives are refused instead of half-supported** (#707). The restore carried a container
  variable through twenty-six path joins and a `sed` over `cron.conf` so that a `./vesta` archive
  could be read - a permanent constraint on every path in the restore, for a panel that has not
  produced an archive in years. The container is a constant now, and a Vesta archive is detected,
  named in the report and refused before the first write.

### Fixed

- **A home entry whose name carries a backslash or a tab comes back** (#736). The restore built its
  list of home entries from `tar -t`, which prints such names *escaped*, and then asked for a file
  under the escaped name - so the unpack failed and took the whole section with it, including the
  entries that were fine. A customer creates that state themselves, with one folder copied out of a
  Windows share, and it only shows when the restore is needed. The names come from the directory the
  container unpacked into now, which cannot disagree with itself, and a single entry that cannot be
  read is named as a failure instead of abandoning the rest. Inherited: HestiaCP 1.10.3 does the
  same.

- **Removing CrowdSec no longer leaves its domains answering 500** (#743). The uninstall took away
  the bouncer and the init config and left every per-domain fragment behind, still calling
  `require("hestia_bouncer")` - and since the directive keeps parsing while the lua module is
  installed, `nginx -t` stayed green and the reload put the breakage live on the spot. The fragments
  go with it now, found in the tree rather than from the records, because one can outlive the other.
  The records keep their `yes`, so reinstalling brings the protection back.

- **A domain carrying `CROWDSEC='yes'` no longer breaks the whole nginx config on a box without
  CrowdSec** (#741). The per-domain fragment was written from the record and gated only on the web
  model, so an nginx that has no bouncer got a `rewrite_by_lua_block` it cannot parse - and that
  invalidates the entire configuration, not the one domain. Nothing looks wrong until something
  reloads, at which point every site on the box is affected. The fragment is now intent *and*
  capability, decided by the artefact the CrowdSec apply step installs; the record keeps its `yes`,
  so moving back to a CrowdSec box restores the protection. Reachable on any rebuild, and the normal
  way in is a restore between two HestiaRE hosts with different addons.

- **The directory-listing switch stopped printing a `sed` error on every rebuild** (#731). It patched
  the SSL vhost as a second file, which the merged template has not produced since both blocks moved
  into one - so every unsuspend and every restore of an SSL domain wrote a "cannot read
  apache2.ssl.conf" line to stderr while doing the right thing. The one `sed` already covers both
  blocks; the second only runs where a legacy pair actually exists.

- **A queued job removes its own line, not every line naming the customer** (#733). The cleanup on
  every abort path matched ` <customer> `, and since the scheduler quotes a restore's arguments the
  pattern never matched the restore's own line - it matched the customer's queued *backup* instead.
  So a refused restore deleted the backup that was waiting and left itself in the queue to fail
  again on every tick, both without a word. The line is now located as fixed text by command,
  customer and archive, and only the first hit is removed.


- **Suspending a web domain no longer switches its forced HTTPS and HSTS off for good** (#720). The
  rebuild re-renders those switches by calling delete and then add. The add half refuses on a
  suspended domain, the delete half has already written `no` into the record - so a suspend printed
  four `is suspended` errors and left the domain with `SSL_FORCE='no'`, `SSL_HSTS='no'`, no proxy or
  FastCGI cache and, in a restore, no FTP account. Unsuspending did not bring any of it back: the
  domain came out of a suspension no longer redirecting to HTTPS. A suspended domain renders the
  suspend template, which includes the existing fragments unchanged, so the rebuild leaves them
  alone until the domain is unsuspended.

- **A domain that was suspended when it was archived comes back suspended** (#720). The restore
  forced `SUSPENDED='no'`, so a locked domain was served again the moment it was restored. It keeps
  the archived value now; `SUSPENDED_WEB` is recounted from the records as before.

- **A customer directory with a space in its name no longer aborts the restore** (#706). The restore
  walked the list of home directories with an unquoted `for`, so `my documents` became two names and
  the run died on `Can't unpack my user dir container` - after the web, mail and database sections
  had already been written. The four lists that come out of the archive rather than out of a
  validator are read line by line now, and the certificate copy globs instead of parsing `ls`, where
  the domain was also spliced unquoted into a regex and its dots matched any character.

- **Restoring an archive under a different customer name no longer duplicates every database
  record** (#721). The existence check looked for the archived name while the record carries the
  renamed one, so it never matched: the fresh branch ran every time, and a second restore of the
  same archive appended everything again - two records became four. It also meant the branch that
  protects a database already on the target was unreachable in exactly that case.

- **The two search commands report the record, not an escaped copy of it** (#719).
  `parse_object_kv_list_non_eval` escaped `"` and `$` on the way in and never undid it, so every
  value it parsed carried the backslashes: `h-search-object` and `h-search-user-object` emitted
  `\"` where the record holds `"`. The escaping protected nothing - the data reaches the parser
  through a quoted expansion and is assigned through another, so neither character is ever
  re-expanded. The same function also read its pairs through word splitting, which globs, so a
  record value containing a `*` came back as a filename from the working directory.
  **The search output changes shape**: it was wrong before, and anyone parsing it gets correct
  values now. The only consumer in the tree is the panel's search page, where this is plainly a
  correction; upstream carries the identical escaping, so `v-search-object` and
  `v-search-user-object` now differ from HestiaCP's output - deliberately, because HestiaCP's is
  the broken one.

- **A record value containing a quote no longer breaks the JSON the panel reads** (#704). The
  `h-*` commands build JSON by string concatenation, so a `"` or a backslash anywhere in a
  record - a domain alias, a notification, a certificate subject, a log line - produced a document
  `json_decode` rejects, and the panel showed an empty page instead of the object. Escaping now
  happens once, in `json_escape` (`include/main.sh`), applied by all 85 emitters. Three listers
  carried a local half-fix that covered the fields upstream #5585 named and missed the rest. A hand
  check on the `docs` branch (`tests/lint/`) derives both the spliced and the escaped names
  from the source, so a field added later cannot slip past unescaped - and reports the opposite
  defect too, a value escaped by hand as well as by the helper, which is how a doubled `\"` reached
  the panel from five emitters. Alongside it, 17 listers read the record with `read` and no `-r`,
  so a backslash in any value was eaten before anything was escaped at all.

- **A restored web domain keeps every field it had** (#705). The restore rebuilt the record from a
  hand-written list of keys, so anything the list did not know simply did not come back: the
  domain's `AUTH_USER`/`AUTH_HASH` - its password protection - along with `WP`, `DIR_LIST`,
  `CROWDSEC` and `BOTLIMIT`. The repair pass then re-inserted those keys empty, so the record looked
  healthy afterwards and the page was open. It only fires when the domain is new on the target,
  which is exactly migration and disaster recovery. The archived line is the record now, edited in
  place, with only named fields rewritten - a field added later survives without anyone remembering
  it. The same applies to the database record.

- **A DKIM record without its private key is now a named failure** (#705). An archive whose record
  says `DKIM='yes'` but carries no `.pem` left a `cp` error on stderr while the restore reported
  success: the panel showed DKIM on, exim signed nothing, and the published TXT record kept
  announcing a key - so every message failed DKIM rather than merely being unsigned. The restore
  finishes the rest and then exits non-zero naming what did not come back.

- Smaller inherited ones, all in the backup path: a dead `google_download` call left over from the
  B2 removal, `egrep` in five places, and `sftp_delete` printing the backup name and the remote path
  on stdout - which the panel showed the customer as part of the error message when a remote delete
  failed.

## v0.16.0 (2026-08-18)

Closes the webmail replacement (#584), WordPress as a domain option (#682), the panel form
reordering (#621) and the read-side hardening of the panel (#578/#649).

### Added

- **WordPress as a panel-managed web-domain option** (#682). A checkbox under the PHP version
  installs a complete WordPress as the customer, through the pinned wp-cli running the domain's own
  backend PHP: verified en_US core with the panel language as a language pack, a database, a cron
  entry instead of wp-cron, and admin credentials shown exactly once. An installed site offers admin
  login, core update and a delete behind a typed-domain confirmation. Unticking detaches - the site
  keeps running, the panel lets go - and the custom document root disappears while WordPress is
  managed, because pointing the domain elsewhere would orphan the installation.

- **Both webmailers at once, chosen per mail domain** (#584). The runtime always supported
  coexistence; the entry path did not. The wizard question is a checklist now, one row per client,
  so a third client is one more row instead of doubling a radio's options. The `WEBMAIL` record's
  value domain is decided on write and known statically rather than by install state, so a client
  that is merely absent keeps its record and heals when it returns.

- **A user's hosting package travels with its backup and is restored** (#663). A restore onto a box
  that never had that package recreates it instead of leaving the user pointing at nothing.
  Add-only: a package of that name already on the target is kept as it is, even with different
  values - the admin owns the target definition.

### Security

- **A validator character class let `|` through into a `bash`-executed queue line** (#393, GHSA-47mf
  class). Nine validators wrote their allowed set as `[-|\.|_[:alnum:]]`, where `|` is a *member* of
  the bracket expression rather than alternation. `h-schedule-user-backup-download` writes its
  validated name unquoted into a queue line that root runs through `bash`, so a backup name like
  `x|command` was a shell pipe - reachable from the panel's download form.

- **Panel-set passwords no longer land in cleartext in auth.log** (#693/#694, external report). sudo
  logs every allowed command line verbatim to authpriv, argv included, into a rotating file that
  ends up in backups; inherited unchanged from upstream. Classic sudo takes `Defaults:hestia
  !log_allowed` (denials keep logging), sudo-rs validates no logging option at all and gets an
  rsyslog drop rule instead. Underneath, the secrets left argv entirely: they travel to the `h-*`
  commands through a 0600 tempfile, so only a path reaches the process arguments. The smoke check
  asserts both layers per run by pushing a throwaway marker through an allowed call.

- **Certificate uploads could have been written to the filesystem root** (#682 review). The SSL
  blocks in the web-domain form read `$mktemp_output[0]` unconditionally; on a failed `mktemp -d`
  that index is unset, so certificate, key and CA landed in `/` under the panel user,
  world-readable. They come from `private_tmpdir()` now, which returns false instead of a path.

- **Four panel gates decided permissively when their input was missing** (#578). An unreadable
  system config left the session without a single policy key, and an absent key is the open reading
  at every gate - the password reset was allowed although the admin had switched it off; the panel
  answers 503 now rather than deciding without its own configuration. `$is_real_root_user` compared
  two empty strings. A suspended customer was served 13883 bytes of complete HTML because the check
  ran after the headers were gone. And the logout did not rotate the session id.

- **A customer could set a control the policy had taken away from them** (#649). With
  `POLICY_USER_CHANGE_THEME=no` the theme select is not rendered, but the handler read the key
  whenever a request carried one. Value controls decide on the server-side gate now, not on the
  presence of the key.

### Changed

- **SnappyMail is replaced by Tachyon, its fork** (#584). Upstream has been dormant since October
  2024 with the maintainer gone, and no security-patch channel for an internet-facing login is
  disqualifying. Tachyon keeps the identical layout, config keys and plugin ecosystem, so the
  integration carries over as a rename. The three plugins are pinned release assets, sha256-verified
  before anything is touched - deliberately not fetched through Tachyon's own installer, which reads
  a package list from a moving branch and would hand the component that changes system passwords to
  an unpinned address. No migration for existing SnappyMail installs.

- **Webmailers no longer require MariaDB - SQLite is the recorded fallback** (#584). Both add
  commands decide the backend once at install time and record it in the app's own config: MySQL when
  the box has it, otherwise SQLite. A MariaDB added later never flips an existing install, and
  `hestia update` stays aware of the exception through that artefact.

- **The mailonly preset stops asking and installing what a mail box has no use for** (#656/#689).
  The database screen is gone; PostgreSQL, Redis, phpMyAdmin, Composer, Docker and the file manager
  are off without a question, each still installable by hand. The forced MariaDB install went with
  the sqlite webmail backend that removed its only consumer.

- **Composer comes from the OS package by default, and the source is switchable on a live box**
  (#237, closes #208). Every install used the upstream installer, whose composer then never updates.
  `h-update-sys-composer os|upstream` installs and verifies the new source **before** removing the
  old one, which is mandatory: `/usr/local/bin` shadows `/usr/bin`, so a leftover phar would
  silently mask the OS package.

- **wp-cli is pinned and verified, and the PHP-tooling downloads are bounded** (#237). The phar came
  from a moving build address with no checksum. It is a manifest pin now, fetched by one helper, and
  `wp cli update` is gone from our paths. `h-add-user-composer`'s update path actually runs:
  `[ -f "$update" ]` asked whether a file named "yes" exists, so selfupdate had been dead since
  inheritance.

- **The panel forms are reordered around what people actually change** (#621/#239). The web-domain
  form puts the 503 switch, the backend block, statistics and SSL above the fold and everything else
  behind a button that moved into the toolbar; edit-user got the same treatment. The database and
  mail-account forms lost their folds entirely - the button took about as much room as the fields it
  hid. The bottom Save row's indent is not a measured number: an invisible copy of the same button
  reserves the width, because the toolbar's Save is as wide as its translation.

- **`func/` is now `include/`, and `func/internal/` is dissolved** (#4). 18 files, ~1876 references.
  The two that mattered beyond a path rewrite are the lint gate's `is_shell()` regex and the
  `.editorconfig` glob: both decide which files get checked at all, so a stale one would have made
  the gate go green by looking at 18 files less.

- **Hosting packages move to `/etc/hestia/packages/`** (#663). They are instance state, created from
  the panel, so they belong under `CONF_DIR` rather than in the install root that an update replaces
  wholesale. The shipped ones are samples now, seeded only when absent.

- **What the panel must not reach moved to `sbin/`** (#209). `bin/` held more than commands: the PHP
  wrappers and the install, uninstall and update entry points. A directory is a boundary that cannot
  rot; a list of 213 command names would have.

- **The panel certificate and the mail SNI links leave the install root** (#564). The certificate
  lives in `/etc/ssl/hestia/` - not under `/etc/hestia/`, which is `0700` and unreadable for caddy,
  exim and proftpd - and the exim SNI directory moved into the service's own configuration.

- **A conditionally rendered control now reads through the gate that rendered it** (#649). A control
  the form did not render sends no key, and every form carried its own idea of what that means -
  three separate patches of the same class in one week. `post_or_keep()` and `post_checkbox()` hold
  the rule, and each gate is named once so view and POST read the same expression.

- **The panel reads a CLI result in one place** (#578). `cli_json()` declares `: array`, so "always
  an array" is checked rather than agreed, and the remaining 61 hand-written decodes go through it.
  A scalar result takes the new `cli_value()`, which answers `null`.

- **PHP has a format contract again** (#647). Upstream formats with prettier, which needs node and
  cannot run on our runner, so nothing had enforced the style since the fork.
  `.php-cs-fixer.dist.php` pins PSR-12 with tabs and the tree was formatted once.

- **What the installer creates no longer depends on the admin's umask.** deb13 and ub26 ship no
  `UMASK` line in `login.defs`, so 24 paths came out group-writable there - the same class that made
  cron silently refuse the Let's Encrypt fallback. Pinned once in the installer and the updater.

- **MariaDB installs 11.8 by default** (#656) on the standard and nomail presets; 11.4 stays
  selectable because Magento 2.4.9 is approved against it. **Notification-mail overrides** are read
  from a path that can hold them (#393) - the reader looked one level above the samples, so no
  override ever loaded. **`h-update-user-cgroup`** refuses to run while `RESOURCES_LIMIT` is off
  (#650): all four callers already gated, but the safety lived outside the command.

- **PROVENANCE recomputed for all four folders** against `upstream/hestiacp@5eb9396` (snapshot
  2026-08-14), with `include/` measured for the first time since it was `func/`. The raw churn rose
  where this release moved our own files rather than where upstream moved: the PHP formatting run
  and the `func/` rename account for nearly all of it (bin 12 -> 15%, web 8 -> 18%, include 28 ->
  29%, share unchanged at 8%). The 40 compiled catalogues keep their own pinned ref. `share/` gained
  the six files the reorganisations had left unlisted and lost two paths that had moved.
  CODEMAP/STRUCTURE carry the mail-template move, and the upstream pins were re-verified: tachyon
  3.2.2 and wp-cli 2.12.0 are still the latest and still match their recorded hashes, and 8.5 is
  still the newest GA PHP, so `php_supported` does not move.

### Removed

- **The custom preset** (#195). The standard path already asks everything relevant and the other
  presets carry their specialities; custom only re-asked the same questions without defaults, plus
  the implicit architecture questions nobody should answer ad hoc. A configuration beyond every
  preset means writing `/etc/hestia/install.conf` by hand.

- **The Backblaze B2 backup backend** (#696). Unused, and dropping it removes an external binary
  download from the backup path and the last plaintext-argv secret. Remaining: local, sftp, ftp,
  rclone, restic.

- **`migrate_data_layout`**, replaced by `reapply_outside_tree` (#663). It carried moves that no
  release has referenced since v0.13.0, twenty tags back, while update covers at most one minor - so
  none of them could fire. 159 lines down to 31.

### Fixed

- **Adding a subdomain under an SSL domain rendered SSL vhosts without a certificate and took nginx
  *and* apache down** (#683, first tester-reported issue). The ownership check parsed the parent's
  record in place and leaked every key into the add command's namespace, so the merged template kept
  its SSL block for the new domain before that domain's own record was written - and the dead vhost
  then blocked the restart Let's Encrypt would have needed to repair it. The same leak sat in
  mail-domain add and web-alias add, the latter surviving only by ordering luck.

- **23 panel pages died instead of showing an empty list when a CLI call failed** (#578). They read
  a command's JSON without looking at its exit code, and `json_decode("")` is `null`, on which the
  first `ksort()` is a TypeError - on the list pages, the first thing a user sees after logging in.
  Upstream of them sat `check_return_code_redirect()`, which sent a `Location` header without
  stopping, so 14 call sites carried on parsing a record their command had never produced.

- **Panel action pages consumed results their command never produced** (#670). Found by rendering
  all 144 pages against a fresh install: an uncaught `TypeError` on `/schedule/restore/` without a
  backup id, 15 pages "checking" the return code of an `exec()` a surrounding `if` had skipped, and
  `/search/` shelling out a `grep` with no pattern. The sweep now produces 0 new log lines, down
  from 47.

- **A package could not be saved from the panel on an apache web role** (#644), which is three of
  the four models: the web-template select renders empty there, an empty select submits no key, and
  the handler read one that was never sent. Four more of the class sat in the same file, including a
  three-`r` typo that left the shell check dead while an absent control demoted the package to
  `nologin`, and a system-package lock that read `$_GET` while the write used `$_POST`.

- **Saving a user replaced the theme they had chosen** (#645). No option carried `selected`, because
  the marker was keyed on a session variable rather than on the value being rendered - and an
  unmarked select submits its first option, `dark`.

- **The system configuration repair never ran** (#654). `h-repair-sys-config` sources only
  `include/main.sh`, so both modes answered `command not found` - and then logged the repair as
  executed. With it working, a running box gained 25 absent keys, most of the `POLICY_*` set among
  them, which had been reaching the panel as `""` - the permissive side at every gate. An empty
  value counts as absent now.

- **The panel never took over its own Let's Encrypt certificate** (#656). `UPDATE_HOSTNAME_SSL` has
  been in the key registry since the fork with no repair block behind it, so it was absent on every
  box while both readers gate on `== "yes"`. Measured on a public box: LE issued, the certificate
  sat in the user's domain directory, and Caddy served the self-signed one from install day. The
  certificate is requested at the end of the install now, not only from an `@reboot` cron that cron
  refused anyway because the installer's umask had left it group-writable.

- **phpMyAdmin dragged apache2 onto a box that has no apache2** (#656). Its unversioned `php-*`
  dependencies resolve to `libapache2-mod-phpX` on some targets, and that apache2 binds `*:80`,
  after which nginx cannot - measured on a fresh Ubuntu 26.04 mailonly install with no webmail vhost
  and no ACME termination. Ubuntu 24.04 resolved the same dependencies without it, so it cannot be
  decided per release.

- **Seven calls still reached the `sbin/` commands through `bin/`** (#209). They referenced them as
  `"$BIN/x"` - a variable, so a grep for the path found none of them. A fresh install died in the
  panel stage, and `hestia install`, `update` and `uninstall` dispatched into nothing.

- **Two commands refused every call that passed their optional argument** (#564).
  `is_format_valid` takes variable *names*; `h-add-mail-domain-ssl` and `h-restart-system` handed it
  the value, so the Let's Encrypt path for a mail domain was impossible.

- **Every domain rebuild on an apache-only box wrote to `/etc/nginx`** (#642). `nginx -v` without
  the binary prints an error that carries no `/` for `cut` to split on and sorts above every real
  version, so the box read as "nginx 1.25.1 or newer". The probe fails closed now.

- **The FPM pools pinned a locale that does not exist** (#239). All five set `env[LANG] =
  en_US.UTF-8`, which none of the four targets generates - awstats alone put 280 perl warnings into
  the panel log per stats run. Pinned to `C.UTF-8`, which is built into glibc.

- **The Docker disable confirmation never appeared** (#621). The guard registered itself only when
  the checkbox read as checked at page load - but Alpine drives that box and the module runs first,
  so it unhooked itself exactly when Docker was on. Underneath sat a second one: `preventDefault()`
  does not stop other listeners, and the submit handler ends in `mainForm.submit()`.

- **Binary files were bucketed by a measurement that cannot see them** (#551). `git diff --numstat`
  reports `-` for a binary, which the provenance manifests recorded as 0% churn - so every image,
  font and compiled catalogue read as unchanged from upstream, including three that plainly are not.
  Binaries are compared by hash now, with no pct at all. The 40 compiled catalogues are pinned to
  the snapshot they arrived with, because measured against a newer upstream they describe upstream's
  translation work rather than anything of ours.

- **The wizard offered Sury's pre-release PHP 8.6, which the installer then refused** (#688).
  Discovery keyed on package availability while `h-add-web-php` validates against `php_supported`:
  two reference sets, no agreement check. The wizard offers the intersection now.

- Smaller inherited ones: `.php-cs-fixer.dist.php` still pointed at `func/` and the formatter
  therefore refused to run at all (#4), `SERVER_ADDR` does not exist under Caddy so an IP allow-list
  branch in `reset/mail/` could never fire (#670), a configure re-run rewrote admin-created hosting
  packages through a `sed` that ranged over the whole glob (#663), three saves wrote a field nobody
  touched and one ran a delete on a box with no nginx role (#649), HTTP/3 and cache duration ran on
  every save instead of on a change (#649), the SSH key list warned on a user without keys (#649),
  and four dead ends turned up by clicking every page (#644).

## v0.15.0 (2026-08-13)

Closes the template restructuring (#219) and the Docker series (#389/#566), and takes the
read side of the object accessors with it.

### Added

- **Docker per customer, from the daemon to the domain** (#389/#566/#592/#618/#619). Each enabled
  customer gets a *companion* account running a rootless daemon and its own loopback /24, so a
  tutorial compose file publishes with no address in it, plus a per-domain switch that makes the
  front proxy to the container - no backend vhost, no FPM pool, LE and CrowdSec and bot limits
  still attached. Separation between customers is one rendered nft rule per /24, derived from the
  records so it survives a firewall rebuild. Resource cap through the package, on the companion's
  systemd slice where the daemon and all containers live.
- **HTTP/3 (QUIC) as a per-domain switch** (#613), replacing three template variants: a checkbox
  that works on any template, offered only where nginx is built with `http_v3` (deb12 and ub24 are
  not - the old variants broke `nginx -t` there).
- **Suspension and the offline switch render from `share/`** (#586). Suspending used to pick from
  the selectable tree, which apache never had, so on apache-only the vhost came out empty and the
  domain served the box default page. **Proxy caching became a switch** too (#587), on any template.
- **Panel users get their uid from a dedicated band** (#388), deterministic per username, with the
  companion block one thousand below and a smoke guard on the preconditions - a collision only
  surfaces much later.
- **DNSBL management from the CLI** (#555).

### Changed

- **A template is one file, and a domain has one vhost config** (#593). The `.tpl`/`.stpl` pair is
  gone, which removes the "fixed in the .tpl, forgotten in the .stpl" divergence class. Restore
  discards archived vhosts and re-renders, so a HestiaCP two-file backup restores as one merged
  vhost and the format stays bidirectional.
- **The PHP version is its own field** (#591, closes #550). `PHP_VERSION` carries the version,
  `BACKEND` only the pool profile. The archive carries both plus HestiaCP's `PHP-<ver>`, and a
  restore aborts before the first write if an archived version is not installed - never silently.
- **`templates/` holds only what somebody chooses** (#588/#589/#590). The apache vhost, the proxy
  vhost, suspend/offline, skeleton, awstats and mail bodies moved to `share/`; the six apache
  templates went entirely, since both apache models already rendered the php-fpm variant. Every
  write passes through `accept_web_template`, which maps a legacy value onto its replacement **with
  its side effect** - a restored `caching` domain comes back with the cache switch on.
- **The web model decides the install scope** (#639). apache-only means no nginx on the box at all.
  Mail-only still gets one for the webmail vhost and ACME, because the wizard fixes that preset to
  NGINX - an exception carried by the model.
- **An install stage is only skipped for the answers it ran with** (#636): stage markers carry the
  fingerprint of their `install.conf`.
- **`/proc` hardening lives in `/etc/fstab`**, not an `@reboot` cron, with its exemption gid
  resolved at every boot. **Scanner bans drop, credential bans still reject** (#555).

### Removed

- **The DNS leftovers** (#619): `DNS_TEMPLATE`, `DNS_DOMAINS`, `DNS_RECORDS`, `NS`, `SUSPENDED_DNS`
  and the `U_DNS_*` counters, out of packages, user records and every listing format. The DKIM
  record view stays - that formats mail-stack data for somebody else's DNS.

### Fixed

- **Object reads matched a domain as a regular expression** (#594). The dot is a wildcard, so with
  `a.b.com` and `aXb.com` on one box a read on one could return the other's record, and
  `add_object_key` could write into the wrong one. Nine accessors and 54 call sites match literally
  now; the backup exclusion parsers, which had matched by prefix, compare by index.
- **An alias owned by another customer was never refused** (#601). `is_web_alias_new` compared
  `"$user"` with `"$user"` - the loop had overwritten the caller's name with the owner from the
  file path.
- **HSTS did nothing on an apache front** (#638): the fragment carried nginx syntax whatever the
  front was, and no apache template included it - switch on, record `yes`, no header.
- **A user named after a service died at `groupadd`** (#625): `h-add-user` checked `/etc/passwd` but
  never `/etc/group`. Both are checked now, plus the accounts our own components create later.
- **A dead SnappyMail mirror produced a green install with no webmail** (#573): an unbounded
  download in an install path is a hang, and a script without `set -e` turns a failed download into
  a green install of nothing.
- **A failing CLI call took the login page down** and let the post-password gates pass (#575).
- **Backup retention could delete another user's archives** (#556), and restic restored only the
  first domain or database of a multi-object user (#555).
- **The panel served its own includes, templates and locale data over HTTP** (#554), and the
  Cloudflare realip fallback trusted a client-controlled header (#553).
- Smaller inherited ones: a Let's Encrypt account whose `user.key` no longer matched failed forever
  (#555), the ip domain counter drifted one under the truth per backup-restore cycle (#599), a
  domain name acting as a regex could delete another customer's cache zone (#583), a missing web
  template wrote a silent 0-byte vhost (#586), `h-change-sys-php` took effect one round late (#585),
  two config repairs never ran (#559), and the FTP account commands disagreed about the name (#625).

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
