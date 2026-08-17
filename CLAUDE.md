# CLAUDE.md – HestiaRE Development Instructions

> Load this file first. Then read `CODEMAP.json` to identify relevant files
> before opening anything else. Never read the entire codebase blindly.

---

## WHAT IS HESTIARE

HestiaRE (Refined Edition) is a lean, official derivative of HestiaCP.
Author is an original HestiaCP co-founder. This is a personal professional
tool, not a community project, not commercial.

Targets (all first-class, equal priority): Debian 12, Debian 13, Ubuntu 24.04 LTS,
Ubuntu 26.04 LTS. Every feature must work on all four; test on the VM fleet.
Scale: ~300 domains, ~30 customers, ~15-20 servers.

Tagline: "Rethink. Rebuild. Reboot."

---

## GROUND RULES

These are absolute. Never deviate, never re-suggest rejected items.

**Never re-introduce:**
- bind9, vsftpd, Web Terminal, REST API, SpamAssassin, Software Installer

**Never suggest:**
- PHP frameworks of any kind
- Docker for HestiaRE itself
- External repos beyond: MariaDB repo, Sury PHP
- Node.js on the Gitea Act Runner host
- `ALL=(ALL) NOPASSWD:ALL` sudo rules

**Always prefer:**
- OS repos over external repos (challenge external first)
- Modular, individually removable components
- Minimal explicit sudo rules per command
- Conservative approach over clever approach

---

## COMMENT STYLE

Comments are terse. Nobody reads a wall of them. A comment earns its place by
explaining **why** the code must be this way; the **how** is the code's job, so
don't narrate it. Condense what the code *does*, keep why it *must*.

**No em-dashes (ground rule).** Never use an em-dash (`—`) or en-dash (`–`) in code
or comments; use a plain ASCII hyphen (`-`) or restructure. A hyphen reads the same
in every editor and terminal and avoids the 3-byte-per-character width surprise.
Prose docs and the translations under `web/locale/` are exempt. This is a cosmetic
convention, not security-relevant and not smoke-enforced (the check was dropped);
sweep for it opportunistically in code/comment cleanup rounds over the panel and CLI
(`bin/`, `web/` minus `web/locale/`).

**Keep verbatim (do NOT condense):**
- A comment explaining a **non-obvious edge/precondition**, or referencing an
  **issue / advisory / distro quirk** (e.g. why proftpd-basic fails, why
  mod-crypto is needed, why the AppArmor hook exists, why a guard is artefact-
  not flag-based). If a long rationale genuinely intrudes, move it to the file
  **header** or **CODEMAP** — never delete it.

**Do NOT touch (these are API/tooling, not prose):**
- Header directives parsed by Hestia for `--help`: `# info:`, `# options:`,
  `# example:`, `# labels:` (every `bin/h-*` must keep a non-empty `# info:`).
- `# shellcheck disable=…` / `# shellcheck source=…`, editor modelines,
  license/attribution headers from the upstream heritage.

**Condense:**
- **Inline** comments that merely restate *what* the code does → one line, or drop.
- **Never restate the code.** A comment above `pm.max_children = 8` that says "set
  max children to 8" is noise — the only thing worth writing is *why 8*. Same for a
  value/var assignment: the value is visible, the reason is not.
- **Line width: up to 120 columns** (not 80 — nothing here is bound to an 80-col
  terminal). Prefer one wide line over three narrow ones; wrap only past 120. Fewer
  lines beats a tall stack of short ones.
- **conf/ini keys:** a one- or two-line option change rarely needs more than a
  one-line *why*. Don't top it with a four-line banner; if the rationale genuinely
  needs a paragraph, it belongs in the file **header**, not inline above the key.
- Keep short (≤5-word) upstream scaffolding as-is (`# Includes`, section banners);
  don't churn near-verbatim upstream files.
- Drop `#NNN` refs in prose (keep a bare number only as a rare useful anchor).

**Verification (mechanical — the invariant is comment-only):** every added/removed
diff line must match `^\s*(#|;|//)` (shell/JSON `#`, ini/fpm `;`, PHP/Caddy `//`
and `#`); any line that doesn't is a hit to inspect. Never regex-strip a trailing
`#` (it is not a comment in `$#`, `${v#p}`, heredocs, awk). So make every change a
**full-line** comment change, not a trailing one. Plus `bash -n` on touched scripts,
`json.tool` on JSON, and a smoke run.

---

## ARCHITECTURE

### Paths
```
/usr/local/hestia/     install root (bin, web, conf, data, modules)
/etc/hestia/           instance config (outside git, survives updates)
/home/$user/              user data (HestiaCP compatible)
```

### CLI conventions
```
h-*    HestiaRE commands (renamed from v-* in Issue #22)
v-*    symlinks only — HestiaCP CLI compatibility
```

Symlink rules (non-negotiable):
- Committed v-* symlinks ship in the tarball; they exist only where upstream has the
  v-* command. New HestiaRE-native h-* commands get NO symlink.
- The installer does NOT blanket-create symlinks — `configure_hestia` only prunes
  dangling v-* (an alias whose h-* target was renamed/removed). `h-check-sys-smoke`
  guards that none dangle.
- Removal verb is `h-delete-*` across the board (upstream `v-delete-*` parity).

### Panel webserver
Caddy (OS repo, port 8083) — replaces hestia-nginx.
PHP: Sury 8.3, isolated FPM pool — replaces hestia-php.

### Always installed components
php multi (Sury 5.6–8.4), mariadb (ext repo), phpmyadmin (OS), caddy (OS),
iptables, fail2ban (OS), ipset, composer (system-wide), wp-cli (system-wide)

**The web model decides the web-server packages, not just who serves.** apache-only means no
nginx on the box; nginx-only and both install nginx. Mail-only needs an nginx for the customer
webmail vhost and ACME termination, and gets one because the wizard fixes that preset to NGINX -
an exception carried by the model, not by an install-everything rule.

### Standard profile adds
apache2 (OS only — no Sury apache2 repo),
exim4 (OS), dovecot (OS), rspamd (OS), roundcube + password plugin (OS)

nginx acts as reverse proxy in front of apache2 for customer vhosts - in the both model.
In apache-only there is no nginx at all.

### Minimal profile
Standard install minus apache2 and mail stack.

### Optional (h-add-*/h-delete-* commands)
proftpd, clamav, postgresql, redis, opensearch, docker-proxy, filemanager

---

## REPOSITORY STRUCTURE

### Branches
```
main              protected, release-ready only, PR required
dev               integration branch, PR required (Admin can push directly)
feature/N-desc    your working branch, N = Gitea issue number
upstream/hestiacp HestiaCP snapshot, READ ONLY, never modify
```

### Key files
```
install.sh        bootstrap: prereqs, fetch release, run wizard, hand off to h-install-hestia
include/wizard.sh    interactive wizard (manifest-driven) → writes /etc/hestia/install.conf
include/helper.sh    installer helpers: hestia_apt, load_os_profile, seed_hestia_etc
sbin/h-install-hestia non-interactive installer (reads install.conf, COMPONENT_*-gated)
sbin/hestia       umbrella: hestia install|configure|update|uninstall|status
VERSION           empty placeholder, filled at build time — never edit
CODEMAP.json      component map — read before exploring the codebase
CLAUDE.md         this file
```

### Directories (HestiaCP origin, being refined)
```
bin/              CLI commands (h-*; v-* symlinks via Issue #23)
include/          shared bash function libraries
share/            install-time service configs + assets (absorbed the old install/ tree, #119)
web/              panel UI (plain PHP, no framework)
src/              frontend assets
conf/             service configuration templates
```

---

## WORKFLOW — EVERY TASK

1. Read `CODEMAP.json` → identify relevant files only
2. Create branch: `git checkout -b feature/N-short-desc`
3. Make changes, commit with: `[#N] type: description`
   — larger changes also add a `CHANGELOG.md` entry (Unreleased section) in the same PR
4. **Blast-radius check** (below) — mandatory whenever an existing function, command signature,
   shared variable or config VALUE was touched
5. Push: `git push origin feature/N-short-desc`
6. Open PR to `dev` (host + API call in `CLAUDE.local.md`)
7. Stop. Do not merge. Author reviews and merges.

**Never push to `dev`, `main`, or `upstream/hestiacp` directly.**

### Blast-radius check (before every PR that touches existing code)

Changing something that already existed — especially inherited from HestiaCP — is only safe once you
know who else uses it. The issue scope is *not* the change's scope. Enumerate consumers **across the
whole tree**, `bin/` + `include/` + `web/` + `share/` + `install.sh`, not just the files in the diff:

- **A shared function**: every caller. A grep of the defining file alone is not an audit — it is how
  four live callers of a "dead" helper get missed.
- **A command signature or argument**: every caller, including `web/` PHP (`exec(HESTIA_CMD . ...)`)
  and `share/` configs (fail2ban actions, systemd units, cron pipes).
- **A config VALUE, not just a key**: every comparison against the old literal. Renaming
  `FIREWALL_SYSTEM` from `iptables` to `nftables` left six sites comparing against the old string; the
  panel's firewall row then fell through to `systemctl` and **destroyed the live ruleset**.
- **A validator or guard**: hardening one makes previously-dead checks fire. Find the callers that were
  silently passing before, and fix them in the same PR rather than exempting them.
- **A MOVED file: grep the bare name, not the old path.** A path pattern only finds references that
  spell the separator. `sbin/` cost seven live call sites written `"$BIN/hestia-php-confd"` — a
  variable, so `bin/hestia-php-confd` matched none of them and a fresh install died. `func/ -> include/`
  then cost `.php-cs-fixer.dist.php`, which writes `__DIR__ . "/func"` with no trailing slash, so the
  formatter silently refused to run. Same shape twice: sweep the **basename on its own**, then every
  variable that could prefix it, and only then the full path.
- **`h-install-hestia` is a first-class caller of `h-*`** (deliberately — one code path, never an
  installer copy that drifts). So every guard must also make sense at **install time**, against a
  half-built box: the state it rejects may be exactly what an earlier install stage just produced.
  `h-add-web-php`'s "already installed" abort keyed on the fpm binary, but the panel PHP is installed
  before the multi-PHP loop re-runs it for the full extension set — every fresh install on all four
  targets died there. Existence checks belong in the update path; a fresh install starts empty.

Prefer a **static sweep over sampling**: run the check against every call site, not a handful of
commands that happen to come to mind. Sampling is what let those five commands through the first time.
Verify empirically on a VM afterwards — including the failure path, not just the success path.

Anything that survived only by luck (a fallback that happened to be right, a check that never ran)
is a finding: fix it or record it, do not leave it silent.

### Guard review: how can the reference set shrink unnoticed?

Ask this of **every new or edited guard**, before it ships. A guard compares something against a
reference set; if that set can quietly become smaller, the guard goes green by looking at less —
which is worse than no guard, because it is trusted. Four cases have already occurred:

- an **empty key set** persisted as the registry, so every later repair agreed with nothing
- **`grep -c`** printing its count at exit 1, so a fallback `echo 0` doubled the output and `0 != 0`
- two **hard-wired service directories**, so moving a template out of them dropped it from coverage
- a recount keyed on the **local IP** while the records store the NAT address, so it counted 0 on
  every NAT'd box — and "correcting" a healthy counter to that 0 is real damage

Concretely: derive the set from the data (find the files, read the key list) rather than listing it;
prefer deciding by content over deciding by path, since a rename silently changes a path; and make
an empty or zero reference set fail rather than pass. State in the guard's comment what it does
**not** cover, so a three-quarter guard is not mistaken for a whole one.

### Fresh-install verification (installer / firewall / fail2ban changes)

Any change to `h-install-hestia`, `include/fail2ban.sh`, the firewall renderer, or the service configs they
apply must be verified against a **genuinely fresh from-scratch install**, not only a re-run of the apply
step on an already-populated box. Re-running on a box that already has domains, proftpd, a whitelist, etc.
is what hid two separate breaks: the v0.12.2 template-include gap, and the installer aborting in the
fail2ban stage (a jail on a not-yet-existent log, and `grep` on an absent `excludes.conf` under
`set -eo pipefail`). Both were green on a re-run because the missing state existed by then. A smoke run
after the fact is not a substitute: by then the logs and files exist. If a full reinstall is not possible
in the moment, at minimum reproduce the empty starting state (no domains, addon not yet installed, config
file absent) before trusting the result.

### Commit message format
```
[#N] type: short description

type: fix | feat | refactor | remove | docs | test
```

### PR

Open the PR against `dev` — never merge it yourself; the author reviews and merges.
The remote host, the exact API call, use of TOKEN and the test-VM fleet live in
`CLAUDE.local.md` (untracked, so the personal host stays off the public GitHub mirror).

### Before every minor release

- Consolidate the `CHANGELOG.md` Unreleased section into the new minor (point releases stay
  inside the cycle they belong to).
- **Recompute the PROVENANCE manifests** against the current `upstream/hestiacp` snapshot, and
  reseed `source_type` from the fresh numbers. `verbatim`/`derived` is a bucketing of the measured
  `pct`, so it goes stale exactly when the numbers do — it drifted 80 entries out of step once
  (#551) because nobody re-derived it. `eigenbau` is the one curated value; a recompute never
  touches it.
- **Check the upstream pins in `share/manifest.json`** (`tachyon` + `tachyon_plugins`, `wp_cli`):
  is there a newer release, and does the pinned one still verify? Bump version + sha256 together
  and refresh the last-verified date in the `$comment`. This is the ONLY patch channel these
  components have — wp-cli has no OS package at all, and Tachyon's fork can go quiet without
  anyone noticing unless the date here forces the question (#237, #584).

---

## HESTIACP COMPATIBILITY

This is non-negotiable and permanent:
- Keep `/home/$user/web|mail|conf|backup` paths
- Keep `h-*` command signatures exactly (renamed from v-*; v-* symlinks provide HestiaCP compat)
- Keep backup format bidirectional forever

When reimplementing HestiaCP functionality:
- Read the original in `upstream/hestiacp` branch first
- Reimplement clean for HestiaRE, do not copy entangled code verbatim

**Never cherry-pick.** Every adoption is a reimplementation, including isolated bugfixes.
Challenge each upstream change on its own: what does the *diff* actually do (not the changelog
title), do we already have it or something better, and is it an improvement worth the regression
risk? Compare per function, not per file. The PROVENANCE manifests say which of our files still
track upstream closely — that is orientation for the comparison, never a merge plan.

---

## CODEMAP

Before exploring files, read `CODEMAP.json` in the repo root.
It maps components to their entry points and related files.
If a component you need is missing from the map, note it — the map
should be updated as part of the feature branch.

---

## DEBIAN 13 NOTE

HestiaCP merged deb13 support into main (June 2026).
Dovecot 2.4 has breaking changes vs 2.3.
Always check `upstream/hestiacp` for deb13-specific handling before
implementing mail-related features.

---

## WHAT NOT TO DO

- Do not run `apt upgrade` or modify system packages unless the task requires it
- Do not create files outside the repo without explicit instruction
- Do not open PRs to `main` — always target `dev`
- Do not modify `upstream/hestiacp` branch
- Do not add external repos without flagging it first
- Do not suggest or implement a REST API