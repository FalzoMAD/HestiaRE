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
| Binary | `/usr/sbin/php-fpm8.3` (Sury repo) |
| FPM config | `/etc/php/hestia/fpm/php-fpm.conf` (version-independent) |
| Panel pool | `/etc/php/hestia/fpm/pool.d/panel.conf` |
| Pool socket | `/run/hestia-php.sock` (unchanged — interface contract with Caddy) |
| PID file | `/run/hestia-php.pid` |
| Error log | `/var/log/hestia/php-fpm.log` |
| Systemd unit | `hestia-php.service` (independent of standard php8.3-fpm.service) |
| Install source | `install/panel-php/` |
| Required packages | `php8.3-fpm php8.3-mysql php8.3-curl php8.3-zip php8.3-gmp php8.3-mbstring php8.3-opcache` |

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
| Panel webserver | `hestia-nginx` package, `/usr/local/hestia-nginx/` | Caddy (OS repo), `/etc/caddy/hestia.conf` | **Decided** — see Q1 |
| Panel PHP | `hestia-php` package, `/usr/local/hestia-php/` | `hestia-php.service` (Sury php8.3-fpm), `/etc/php/hestia/fpm/` | **Decided** — Issue #25 |
| Shell profile comment | references `/etc/hestiacp/local.conf` | must reference `/etc/hestia/local.conf` | Fix in Issue #26; existence of file questioned (later issue) |
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

| # | Topic | Status |
|---|-------|--------|
| Q1 | Caddy config structure | **DECIDED** |
| Q2 | PHP FPM panel pool | **DECIDED** — Issue #25 |
| Q3 | `/etc/profile.d/hestia.sh` comment | **DECIDED** + cleanup deferred |
| Q4 | `hestiaweb` sudo wildcard scope | **OPEN** — too early, technical debt |
| Q5 | `h-add-cron-hestia-autoupdate` | **DECIDED** |

---

**Q1 — Caddy config structure: DECIDED**

- Caddy Debian package creates `/etc/caddy/` and `/etc/caddy/Caddyfile` — no `conf.d/` by default
- HestiaRE panel config: `/etc/caddy/hestia.conf`
- `/etc/caddy/Caddyfile` contains: `import /etc/caddy/*.conf`
- Caddyfile is controlled by HestiaRE — survives OS updates

---

**Q2 — PHP FPM panel pool: DECIDED — Issue #25**

- Dedicated `hestia-php.service` unit using `/usr/sbin/php-fpm8.3` (Sury), independent of `php8.3-fpm.service`
- Config dir: `/etc/php/hestia/fpm/` (version-independent — survives PHP version bumps)
- Pool socket: `/run/hestia-php.sock` (unchanged from hestia-php — no Caddy config change needed)
- Pool name: `panel`, user/group: `hestiaweb`
- `pm=ondemand`, 4 children max (panel has low concurrent load)
- opcache enabled (Sury ships it; old hestia-php had none)
- Installer integration deferred to Issue #26a

---

**Q3 — `/etc/profile.d/hestia.sh` comment: DECIDED**

- Comment in the generated file must reference `/etc/hestia/local.conf` instead of `/etc/hestiacp/local.conf`
- Fix tracked in Issue #26 (installer rebuild)
- Additionally: the existence of `/etc/profile.d/hestia.sh` as a system-wide profile file is questioned — why does HestiaRE need this? Deferred as a separate later issue.

---

**Q4 — `hestiaweb` sudo wildcard scope: OPEN — technical debt**

`/etc/sudoers.d/hestiaweb` currently allows:
```
hestiaweb ALL=NOPASSWD:/usr/local/hestia/bin/*
```
The entire internal user setup (`hestiaweb`, `admin`, roles) is going on the audit list as its own issue. Wildcard stays for now, marked as technical debt.

---

**Q5 — `h-add-cron-hestia-autoupdate`: DECIDED**

- Command stays for now — auto-update mechanism is not excluded by design
- Auto-update is not active by default
- Implementation decision (HestiaRE-native mechanism vs. keep as-is) comes later
