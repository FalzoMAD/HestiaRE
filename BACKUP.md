# BACKUP.md - backing up and restoring a customer

> `PATHS.md` has the filesystem layout, `STRUCTURE.md` why it diverges from HestiaCP,
> `CODEMAP.json` which file does what. **This file is the operator's view:** what the
> backup subsystem promises, what it does not, and which command to reach for.

**Living doc.** A change to modes, retention, paths or the panel flow updates this file
in the same PR.

---

## What this is not

Two limits, stated first because everything else reads differently without them.

**No backup here is meant to survive the loss of the server.** Not full, not
differential, not restic. Archives live on the same box unless a remote target is
configured, and the restic key lives beside the repository. What these backups protect
against is a customer breaking their own site, a bad deploy, a deleted mailbox - not a
burnt datacentre. Plan disaster recovery separately.

**restic's encryption is not a promise we make.** restic cannot write an unencrypted
repository, so encryption is a property of the tool, not a feature of this product. It
is not advertised, and no threat model rests on it.

---

## One customer, one mode

`BACKUPS_MODE` in the customer's package is the single truth. Three values, mutually
exclusive:

| mode | what a run produces |
|---|---|
| `full` (default) | one tar per run, everything in it |
| `diff` | web and mail members rebuilt against the newest full archive; the rest whole |
| `restic` | a snapshot in the customer's repository, plus a metadata package beside it |

The nightly cron runs `h-backup-users` once (`10 05 * * *`), and the customer's mode
picks the runner. A customer set to `restic` on a box without the addon gets an archive
backup and a warning in the log - not a silent skip at five in the morning.

`BACKUP_INCREMENTAL` in `hestia.conf` is the server-side switch and means exactly
"restic is installed and a repository is configured". It does not select a mode.

---

## Where things live

```
/backup/                       0711 - names are not enumerable
/backup/$user/                 0750 hestia:$user - the customer's archives and run log
/backup/$user/$user.<stamp>.tar
/backup/$user/$user.log
/backup/$user/$user.<stamp>.meta.tgz    restic only: the readable metadata package
/backup/<repo>/$user/                   restic only: one repository per customer
/home/$user/.dumps/                     restic only: the staging tree, raw
```

A hand-placed migration archive may also lie **flat in `/backup/`**. Those two places
are the only ones, `backup_archive_path` is the only resolver of them, symlinks are
refused, and every message names which of the two it found.

`/backup/$user/` is never removed by deleting the customer: **deleting a customer keeps
their backups.** For restic there is an explicit way out, below.

---

## Retention, and what protects a file

Rotation counts **sets**, not files: a differential archive belongs to the set of its
base, and a base is kept as long as any kept archive names it.

- The package's `BACKUPS` is what the local rotation keeps.
- Each remote target may keep more, via its own `BACKUPS_KEEP` (empty means mirror the
  package). A keep of 0 is refused by name - "retain nothing" is not a retention setting.
- The **record outlives the file**: record retention follows the longest keep anywhere,
  so a customer can still schedule a restore of something only a remote holds. The
  listers mark those `LOCAL='no'`.

Two things protect a file from the rotation:

- **It lies flat in `/backup/`.** The rotation only enumerates `/backup/$user/`, so a
  flat archive is structurally out of reach.
- **Its record says `ADOPTED='yes'`.** Adopted names are subtracted from the rotation
  list, and `h-delete-user-backup` forgets the record without deleting the file.

An archive inside `/backup/$user/` with **no record** has neither protection: it counts
as its own set, so with `BACKUPS='1'` the next run removes it.

---

## Adoption

A hand-placed archive is unknown until someone names it:

```
h-add-user-backup $user $archive
```

The archive is probed and every record field derived from its **contents** - domains,
databases, cron, user directories, web and proxy system. There is no version field and
no marker; a foreign archive is recognised by its features. Vesta archives are refused
by name.

A restore adopts by itself: `h-restore-user` calls the same command at the end whenever
no record names the archive it read. Restoring from something is the clearest statement
that it is wanted.

There is **no discovery**: nothing lists what is lying around in `/backup/` unadopted.
You need the filename.

---

## Remote targets

```
h-add-backup-host  sftp|ftp|rclone HOST USER PASS [PATH] [PORT] [KEEP]
h-delete-backup-host TYPE
h-list-backup-host
```

A remote target is a first-class source, not an emergency copy. Download and restore walk
**every** configured transport until the file has actually arrived - success is measured
on the content, never on an exit code, because the upload pipelines discard theirs.

A differential archive only needs its base to be **reachable**: locally, or on a
configured target's fresh listing. A run whose base is reachable nowhere says so and
writes a full backup instead.

---

## restic mode

An addon: `h-add-sys-restic` / `h-delete-sys-restic`. Selectable as a package value only
when the addon is present **and** a repository target is configured
(`h-add-backup-host-restic`).

**One repository per customer.** A shared repository would deduplicate across customers,
but only with a shared key - and then every customer could read every backup.

**The metadata package is readable without restic.** Beside each snapshot lies
`$user.<stamp>.meta.tgz` (0640 hestia:hestia) holding the records, SSL, PAM material, the
exclusion list and a copy of the repository key. Without restic and without the key it
stays knowable what a customer had.

**Payload goes into the repository**, staged raw under `/home/$user/.dumps`. Raw on
purpose: it deduplicates against the previous snapshot far better than compressed, which
shifts every block boundary on each change.

Snapshot and package are paired in **both** directions - the snapshot carries a
`meta:$user.<stamp>` tag, the package names the snapshot id. A package counts as an
orphan only when neither anchor resolves.

```
h-list-sys-backup-orphans-restic          what is left over without a partner
h-delete-user-backups-restic $user all    the explicit way out - names repository,
                                          size, snapshot and package count first
h-restore-file-restic                     single file out of a snapshot
```

Both of the first two refuse a **remote** repository base by name: `sftp:` and `rclone:`
targets are not paths, so a deletion would remove the packages - which carry the only
spare key - while the repository itself stayed.

---

## Exports

An export is one ordinary archive run, marked:

```
h-export-user-backup $user
```

Not a fourth mode. What comes out is the format adoption, probe, report and restore
already handle, which is how a restic customer migrates without rebuilding an archive out
of snapshots. Its record carries `MODE='export'` and `ADOPTED='yes'`, so retention never
touches it. `BACKUP_EXPORT_LIMIT` (default 2) refuses and names the existing exports
rather than clearing the oldest away.

One thing an export does differently: it writes the webmail client under the name other
panels share. Tachyon is our name for a Roundcube fork, and HestiaCP refuses the value
outright, leaving the mail domain without webmail. So an export writes `roundcube` and
keeps the original in `hestia/export-map`; restoring it here reads that back, so an
export between two HestiaRE boxes is as lossless as an ordinary archive. Nothing else in
the archive is translated.

---

## In the panel

One Backups tab. It branches on the customer's mode: an archive customer sees their
archives, a restic customer lands on the snapshot list. `?archives=1` is the way back to
the archives from before a mode switch and to the exports, which are marked as such with
the reason - retention does not rotate them.

---

## Restoring

```
h-restore-user $user $archive [WEB] [DNS] [MAIL] [DB] [CRON] [UDIR] [NOTIFY] CONSENT
```

Consent is required before the first write, and it is an **argument** (or a TTY prompt),
never an environment prefix. `all` covers the sections and deliberately not
`php-fallback`: moving a customer's domains onto another PHP version changes what they
run and is not part of "restore everything".

Before writing anything, the run prints what **this host cannot restore** from that
archive - a database engine it lacks, a web template it does not have, protections it
cannot render. What it cannot put back but the archive still holds is handed over into
the customer's own directory, 0700, never under `web/`.

An archive can be restored **under a different customer name**; the prefixes, FTP user,
custom docroot and database names are rewritten. That is why neither the backup nor the
restore ever passes `--numeric-owner`: the account is created first, so tar resolves the
archived owner by NAME onto a freshly allocated uid. (The content map's `tar -tv` listing
does use it, on purpose - that one reads ids, it does not write them.)

A run that lost a part is not a successful run - the parts that did not come back are
collected and reported at the end, with a non-zero exit.

---

## When a run refuses

The barrier measures rather than estimates, and books per **filesystem**: staging tree and
result on one device add up, on two they do not. In restic mode the demand comes from one
dry dump per database (and, on a first snapshot, a `du` over the home the backup walks);
in archive mode from a `du` over the customer. A refusal names the filesystem, the demand
and the free space.

A member that cannot be written **aborts the run**: no archive, no record. A half archive
that looks whole is worse than none - the outer tar stays perfectly readable while the
member inside is truncated, and nothing downstream would notice. Dumps are additionally
checked for their engine's completion marker, because the exit status of
`dump | compress > file` is the compressor's.
