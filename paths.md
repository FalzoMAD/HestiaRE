# HestiaRE — Install Path Reference

> This file is the authoritative reference for all filesystem paths used by HestiaRE.
> Generated as part of Issue #21. Update when paths change.

---

## 1. Install Paths

| Purpose | Path | Notes |
|---------|------|-------|
| Install root | `/usr/local/hestia` | Same as HestiaCP — intentional, no rename |
| Instance config | `/etc/hestia` | Changed from `/etc/hestiacp` — only relevant path change |
| Shell profile | `/etc/profile.d/hestia.sh` | Exports `$HESTIA`, adds `$HESTIA/bin` to `$PATH` |
| Sudo rules | `/etc/sudoers.d/hestiaweb` | `hestiaweb ALL=NOPASSWD:/usr/local/hestia/bin/*` |
| Log dir | `/var/log/hestia` | Symlinked as `$HESTIA/log` |

### Install root subdirectory layout

```
/usr/local/hestia/
├── bin/               CLI commands (v-*, hl-*)
├── conf/              Runtime config
│   ├── hestia.conf    Active config (key=value pairs, generated)
│   └── defaults/      Known-good baseline (copy of conf at install time)
├── data/
│   ├── ips/           IP address entries
│   ├── queue/         Named pipes for async task processing
│   │   ├── backup.pipe
│   │   ├── disk.pipe
│   │   ├── webstats.pipe
│   │   ├── restart.pipe
│   │   ├── traffic.pipe
│   │   └── daily.pipe
│   ├── users/         Per-user data files (not home dirs)
│   ├── firewall/      Firewall rules and ipset data
│   ├── sessions/      PHP panel session files (owner: hestiaweb)
│   ├── packages/      Hosting plan package definitions (*.pkg)
│   ├── templates/     Web/DNS/mail vhost templates
│   └── api/           API integration configs
├── func/              Shared bash function libraries
├── install/           Installer data (deployed with package)
├── log -> /var/log/hestia   Symlink
├── ssl/               Panel SSL certificate and key
└── web/               Panel PHP UI
    └── rrd/           RRD graph data files
```

### Instance config layout (`/etc/hestia/`) — target state

This shows the **final target** after migrations planned for later issues.
Current state and migration steps are documented in Section 5.

```
/etc/hestia/
├── hestia.conf        Bootstrap file — sets $HESTIA, sources local.conf
│                      Do not edit directly, overwritten on upgrade
├── local.conf         User overrides — survives upgrades, outside git
├── source.conf        Update channel config (github/gitea, token, channel)
├── conf/              Panel instance config (moved from $HESTIA/conf/)
│   ├── hestia.conf    Active panel config (key=value pairs, generated)
│   └── defaults/      Known-good baseline
├── firewall/          Firewall rules and ipset data (moved from $HESTIA/data/firewall/)
├── ips/               IP address entries (moved from $HESTIA/data/ips/)
└── hooks/             Optional lifecycle scripts (moved from /etc/hestiacp/hooks/)
    └── le_pre.sh      Example: LetsEncrypt pre-hook (optional, usually absent)
```

---

## 2. Service-Specific Paths

### Panel webserver — Caddy (replaces hestia-nginx)

| Item | Path |
|------|------|
| Binary | `/usr/sbin/caddy` (OS repo) |
| Config dir | `/etc/caddy/` |
| Panel config | TBD — see Open Questions #1 |
| Port | `8083` (HTTPS) |
| Systemd unit | `caddy.service` |

### Panel PHP — Sury PHP 8.3 FPM (replaces hestia-php)

| Item | Path |
|------|------|
| Binary | `/usr/bin/php8.3` (Sury repo) |
| FPM config | `/etc/php/8.3/fpm/php-fpm.conf` |
| Panel pool | TBD — see Open Questions #2 |
| Pool socket | TBD — see Open Questions #2 |
| Systemd unit | `php8.3-fpm.service` |

### nginx (frontend proxy / webserver)

| Item | Path |
|------|------|
| Config | `/etc/nginx/nginx.conf` |
| Domain configs | `/etc/nginx/conf.d/domains/` |
| Main includes | `/etc/nginx/conf.d/main/` |
| Log dir | `/var/log/nginx/domains/` |
| Systemd unit | `nginx.service` |

### Mail — Exim4

| Item | Path |
|------|------|
| Config | `/etc/exim4/exim4.conf.template` |
| Filter | `/etc/exim4/system.filter` |
| Supplemental | `/etc/exim4/dnsbl.conf`, `spam-blocks.conf`, `limit.conf` |

### Mail — Dovecot

| Item | Path |
|------|------|
| Config | `/etc/dovecot/dovecot.conf` |
| Note | Dovecot 2.4 has breaking changes vs 2.3 — check upstream/hestiacp for Debian 13 handling |

### Mail — Rspamd

| Item | Path |
|------|------|
| Config dir | `/etc/rspamd/` |
| Systemd unit | `rspamd.service` |

### Database — MariaDB

| Item | Path |
|------|------|
| Config | `/etc/mysql/my.cnf` |
| Socket | `/var/run/mysqld/mysqld.sock` |
| Systemd unit | `mariadb.service` |

### Database admin — phpMyAdmin

| Item | Path |
|------|------|
| Web root | `/usr/share/phpmyadmin` |
| Config | `/etc/phpmyadmin/config.inc.php` |
| Temp dir | `/var/lib/phpmyadmin/tmp` |

### Fail2ban

| Item | Path |
|------|------|
| Jail config | `/etc/fail2ban/jail.local` |
| Auth log watched | `/var/log/hestia/auth.log` |

### Cron (hestiaweb crontab)

| Item | Path |
|------|------|
| Crontab | `/var/spool/cron/crontabs/hestiaweb` |
| Session cleanup | `/etc/cron.daily/php-session-cleanup` |

---

## 3. User Data Paths

User home structure — unchanged from HestiaCP, bidirectional backup compatibility preserved.

```
/home/$user/
├── web/                  Document roots and public_html
│   └── $domain/
│       └── public_html/
├── mail/                 Maildir storage
│   └── $domain/
│       └── $account/
├── conf/                 Generated service configs (immutable dir)
│   ├── web/
│   │   └── $domain/      nginx/apache vhost configs
│   ├── mail/
│   │   └── $domain/      Dovecot/Exim domain configs
│   └── dns/              Zone files (if DNS enabled)
├── backup/               User-level backups
└── tmp/                  PHP session temp (`/home/*/tmp/sess_*`)
```

Variables set in `func/main.sh`:

| Variable | Value |
|----------|-------|
| `HOMEDIR` | `/home` |
| `USER_DATA` | `$HESTIA/data/users/$user` |
| `WEBTPL` | `$HESTIA/data/templates/web` |
| `MAILTPL` | `$HESTIA/data/templates/mail` |
| `DNSTPL` | `$HESTIA/data/templates/dns` |
| `RRD` | `$HESTIA/web/rrd` |
| `SENDMAIL` | `$HESTIA/web/inc/mail-wrapper.php` |

---

## 4. Paths Changed from HestiaCP

| Item | HestiaCP | HestiaRE | Status |
|------|----------|----------|--------|
| Instance config dir | `/etc/hestiacp/` | `/etc/hestia/` | **Decided** |
| Bootstrap config file | `/etc/hestiacp/hestia.conf` | `/etc/hestia/hestia.conf` | **Decided** |
| Local overrides | `/etc/hestiacp/local.conf` | `/etc/hestia/local.conf` | **Decided** |
| Install root | `/usr/local/hestia` | `/usr/local/hestia` | Unchanged — intentional |
| `$HESTIA` variable | `/usr/local/hestia` | `/usr/local/hestia` | Unchanged — no migration needed |
| Panel webserver | `hestia-nginx` package, `/usr/local/hestia-nginx/` | Caddy (OS repo), `/etc/caddy/` | **Decided**, config path TBD |
| Panel PHP | `hestia-php` package, `/usr/local/hestia-php/` | `php8.3-fpm` (Sury), `/etc/php/8.3/fpm/` | **Decided**, pool config TBD |
| Shell profile comment | references `/etc/hestiacp/local.conf` | must reference `/etc/hestia/local.conf` | Needs update in installer |
| Log dir name | `/var/log/hestia` | `/var/log/hestia` | Unchanged — OS path, no rebrand needed |
| Apt repo | `apt.hestiacp.com` | removed — no external hestia packages | **Decided** |

**Key insight:** Because the install root stays `/usr/local/hestia`, the `$HESTIA` variable and all 514 `bin/*` commands that reference it require only one change: the `source /etc/hestiacp/hestia.conf` line must become `source /etc/hestia/hestia.conf`. The variable value itself is unchanged.

---

## 5. /etc/hestia/ Migration Plan

### 5a. Paths moving to /etc/hestia/ (decided, later issue)

These directories will be migrated in a dedicated follow-up issue.
Filenames are preserved — no renames.

| Source (current) | Target | Notes |
|------------------|--------|-------|
| `/usr/local/hestia/conf/` | `/etc/hestia/conf/` | Panel instance config |
| `/usr/local/hestia/conf/defaults/` | `/etc/hestia/defaults/` | Flattened one level |
| `/usr/local/hestia/data/firewall/` | `/etc/hestia/firewall/` | Rules + ipset data |
| `/usr/local/hestia/data/ips/` | `/etc/hestia/ips/` | IP address entries |
| `/etc/hestiacp/hooks/` | `/etc/hestia/hooks/` | Lifecycle scripts (usually empty) |

### 5b. Deliberately not moved (pending separate analysis)

| Path | Reason |
|------|--------|
| `$HESTIA/data/users/` | Part of the backup format — requires separate analysis before any move |
| `$HESTIA/data/queue/` | Runtime named pipes — leave untouched for now |
| `$HESTIA/data/packages/` | Review together with `data/templates/` in a later issue |
| `$HESTIA/data/templates/` | Review together with `data/packages/` — decision: stay or move to `/etc/hestia/` |

### 5c. Known conflicts / open issues

**Two files named `hestia.conf` — not yet resolved**

There are currently two distinct files with similar names and different roles:

1. **`/etc/hestiacp/hestia.conf`** — Bootstrap file. Sourced as the very first
   action by every `v-*` and `hl-*` command. Sets `$HESTIA` and `$PATH`.
   - Current content: `export HESTIA='/usr/local/hestia'` + sources `local.conf`
   - Target: `/etc/hestia/hestia.conf` — but migration is its own issue because
     renaming/restructuring this file involves the hestiaweb/admin user topic
     and a decision on env-file vs. conf-file structure.

2. **`/usr/local/hestia/conf/hestia.conf`** — Panel instance config. Contains all
   active panel settings as `KEY='value'` pairs (WEB_SYSTEM, MAIL_SYSTEM, etc.).
   - Target: `/etc/hestia/conf/hestia.conf` (migration in 5a above)

These two files must not be confused. The migration in 5a moves file #2 only.
File #1 stays at `/etc/hestiacp/hestia.conf` until its dedicated issue resolves
the env vs. conf question and the user/account consolidation.

### 5d. Deferred to later issues

| Topic | Scope |
|-------|-------|
| Bootstrap file restructure | `/etc/hestiacp/hestia.conf` → `/etc/hestia/hestia.conf`, env vs. conf format, hestiaweb/admin user consolidation |
| `data/packages/` + `data/templates/` | Decision: move to `/etc/hestia/` or keep under install root |
| `data/users/` | Backup format compatibility analysis required before any move |

---

## 6. Open Questions

These paths need a decision before the corresponding installer work begins. No implementation should proceed without resolution.

---

**Q1 — Caddy config structure**

Where does the panel's Caddy configuration live?

Options:
- a) `/etc/caddy/Caddyfile` — single file, simple, but mixes panel config with any other Caddy usage on the server
- b) `/etc/caddy/conf.d/hestia.conf` — drop-in directory pattern, consistent with nginx approach
- c) `$HESTIA/conf/caddy/` — inside install root, managed by HestiaRE, cleaner separation

Concern: Caddy's default Caddyfile location is `/etc/caddy/Caddyfile`. If we use a drop-in dir, we need to ensure the Caddyfile includes it. Option (b) is recommended to stay consistent with the nginx pattern already used.

---

**Q2 — PHP 8.3 FPM panel pool**

What is the pool config path and socket for the panel's isolated PHP-FPM pool?

Options:
- a) `/etc/php/8.3/fpm/pool.d/hestia.conf` → socket `/run/php/hestia.sock`
- b) `/etc/php/8.3/fpm/pool.d/hestiaweb.conf` → socket `/run/php/hestiaweb.sock`

Also needed: which user/group runs the pool? Currently `hestiaweb:hestiaweb` seems natural (panel user), but needs confirmation since `$HESTIA/data/sessions/` ownership is `hestiaweb:hestiaweb`.

---

**Q3 — `/etc/profile.d/hestia.sh` inline comment**

The installer writes this file with a hardcoded comment:
```
# Do not edit this file, will get overwritten on next upgrade,
# use /etc/hestiacp/local.conf instead
```
This must reference `/etc/hestia/local.conf`. Low risk, but needs to be caught in the installer migration.

---

**Q4 — `hestiaweb` sudo rule scope**

`/etc/sudoers.d/hestiaweb` currently allows:
```
hestiaweb ALL=NOPASSWD:/usr/local/hestia/bin/*
```
Since the install root is unchanged, this rule remains correct. However, CLAUDE.md requires minimal explicit sudo rules per command, not a wildcard over the entire `bin/` directory. This wildcard was inherited from HestiaCP.

**Challenge:** Is `NOPASSWD:/usr/local/hestia/bin/*` acceptable for HestiaRE, or should this be reduced to a specific list of commands the panel actually calls? This is a security scope question for the author.

---

**Q5 — `v-add-cron-hestia-autoupdate` command**

This command exists in `bin/` and sets up a HestiaCP auto-update cron job. It has no place in HestiaRE (updates go through `make update`). Decision needed: remove the command, or replace it with a HestiaRE-aware equivalent (`hl-schedule-update`)?
