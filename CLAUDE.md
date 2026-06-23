# CLAUDE.md – HestiaRE Development Instructions

> Load this file first. Then read `CODEMAP.json` to identify relevant files
> before opening anything else. Never read the entire codebase blindly.

---

## WHAT IS HESTIARE

HestiaRE (Refined Edition) is a lean, official derivative of HestiaCP.
Author is an original HestiaCP co-founder. This is a personal professional
tool, not a community project, not commercial.

Primary targets: Debian 12, Ubuntu 24.04 LTS, Debian 13 (priority 2 since June 2026).
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
- Existing h-* commands: one v-* symlink each (created in Issue #23)
- New h-* commands added after Issue #23: NO symlink — the v-* name never existed
- When removing a h-* command: remove the v-* symlink too — no orphans

### Panel webserver
Caddy (OS repo, port 8083) — replaces hestia-nginx.
PHP: Sury 8.2, isolated FPM pool — replaces hestia-php.

### Always installed components
nginx (OS), php multi (Sury 5.6–8.4), mariadb (ext repo), phpmyadmin (OS),
caddy (OS), iptables, fail2ban (OS), ipset, composer (system-wide), wp-cli (system-wide)

### Standard profile adds
exim4 (OS), dovecot (OS), rspamd (OS), roundcube + password plugin (OS)

### Optional (hl-service-install/remove)
apache2, proftpd, clamav, postgresql, redis, opensearch, docker-proxy, filemanager

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
install.sh        main installer (downloads release, calls just)
Justfile          just targets: install, update, check-updates, status
VERSION           empty placeholder, filled at build time — never edit
codemap.json      component map — read before exploring the codebase
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
4. Push: `git push origin feature/N-short-desc`
5. Open PR to `dev` via Gitea API (see below)
6. Stop. Do not merge. Author reviews and merges.

**Never push to `dev`, `main`, or `upstream/hestiacp` directly.**

### Commit message format
```
[#N] type: short description

type: fix | feat | refactor | remove | docs | test
```

### PR via Gitea API
```bash
curl -s -X POST "https://git.hestiare.com/api/v1/repos/Admin/hestiare/pulls" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Short description (#N)",
    "body": "Closes #N\n\nWhat changed and why.",
    "head": "feature/N-short-desc",
    "base": "dev"
  }'
```

`GITEA_TOKEN` is available as environment variable — do not hardcode.

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