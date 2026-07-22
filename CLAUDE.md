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

Comments are terse. Nobody reads a wall of them. But some comments carry
hard-won knowledge — condense what the code *does*, keep why it *must*.

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
- Keep short (≤5-word) upstream scaffolding as-is (`# Includes`, section banners);
  don't churn near-verbatim upstream files.
- Drop `#NNN` refs in prose (keep a bare number only as a rare useful anchor).

**Verification (mechanical — the invariant is comment-only):** every added/removed
diff line must match `^\s*#`; any line that doesn't is a hit to inspect. Never
regex-strip trailing `#` (it is not a comment in `$#`, `${v#p}`, heredocs, awk).
So make every change a **full-line** comment change, not a trailing one. Plus
`bash -n` on touched scripts, `json.tool` on JSON, and a smoke run.

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
v-*    symlinks only — ease of cherry-picking HestiaCP upstream changes
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
nginx (OS), php multi (Sury 5.6–8.4), mariadb (ext repo), phpmyadmin (OS),
caddy (OS), iptables, fail2ban (OS), ipset, composer (system-wide), wp-cli (system-wide)

### Standard profile adds
apache2 (OS only — no Sury apache2 repo),
exim4 (OS), dovecot (OS), rspamd (OS), roundcube + password plugin (OS)

nginx acts as reverse proxy in front of apache2 for customer vhosts.

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
func/wizard.sh    interactive wizard (manifest-driven) → writes /etc/hestia/install.conf
func/helper.sh    installer helpers: hestia_apt, load_os_profile, seed_hestia_etc
bin/h-install-hestia  non-interactive installer (reads install.conf, COMPONENT_*-gated)
bin/hestia        umbrella: hestia install|configure|update|uninstall|status
VERSION           empty placeholder, filled at build time — never edit
CODEMAP.json      component map — read before exploring the codebase
CLAUDE.md         this file
```

### Directories (HestiaCP origin, being refined)
```
bin/              CLI commands (h-*; v-* symlinks via Issue #23)
func/             shared bash function libraries
install/          installer data: packages, templates, configs per distro
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
4. Push: `git push origin feature/N-short-desc`
5. Open PR to `dev` (host + API call in `CLAUDE.local.md`)
6. Stop. Do not merge. Author reviews and merges.

**Never push to `dev`, `main`, or `upstream/hestiacp` directly.**

### Commit message format
```
[#N] type: short description

type: fix | feat | refactor | remove | docs | test
```

### PR

Open the PR against `dev` — never merge it yourself; the author reviews and merges.
The remote host, the exact API call, use of TOKEN and the test-VM fleet live in
`CLAUDE.local.md` (untracked, so the personal host stays off the public GitHub mirror).

---

## HESTIACP COMPATIBILITY

This is non-negotiable and permanent:
- Keep `/home/$user/web|mail|conf|backup` paths
- Keep `h-*` command signatures exactly (renamed from v-*; v-* symlinks provide HestiaCP compat)
- Keep backup format bidirectional forever

When reimplementing HestiaCP functionality:
- Read the original in `upstream/hestiacp` branch first
- Reimplement clean for HestiaRE, do not copy entangled code verbatim
- Direct cherry-pick only for isolated bugfixes with no HestiaCP-specific deps

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