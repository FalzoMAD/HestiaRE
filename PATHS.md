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
├── bin/               CLI commands (h-*, v-* symlinks)
├── conf -> /etc/hestia/conf   Symlink — instance config lives in /etc/hestia (§5a)
├── share/             Shipped install-time assets: manifest.json, panel-caddy/,
│                      panel-php/, dovecot/ (consumed by the installer)
├── packages/          Hosting plan definitions (*.pkg) — ships in tarball (#150)
├── templates/         Web/mail vhost + php-fpm templates — ships in tarball (#150)
├── .sessions/         PHP panel session files (owner: hestiaweb)
├── data/
│   ├── users/         Per-user data files (not home dirs)
│   └── firewall/      Firewall rules and ipset data (→ /etc/hestia/firewall, pending)
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
├── hestia.env         Bootstrap file — sets $HESTIA, sources local.conf
│                      Do not edit directly, overwritten on upgrade
├── local.conf         User overrides — survives upgrades, outside git
├── source.conf        Update channel config (github/gitea, token, channel)
├── conf/              Panel instance config (moved from $HESTIA/conf/)
│   ├── hestia.conf    Active panel config (key=value pairs, generated)
│   └── defaults/      Known-good baseline
├── public_suffix_list.dat  TLD-validation cache (downloaded by domain.sh, refreshed weekly)
├── firewall/          Firewall rules and ipset data (moved from $HESTIA/data/firewall/)
├── ips/               IP address entries (moved from $HESTIA/data/ips/)
├── queue/             Runtime named pipes (moved from $HESTIA/data/queue/)
└── hooks/             Optional lifecycle hooks (LE + mail-domain; moved from /etc/hestiacp/hooks/)
    ├── le_pre.sh           Example: LetsEncrypt pre-hook (optional, usually absent)
    └── add-mail-domain.sh  Example: post-add-mail-domain hook (optional)
```

---

## 2. Service-Specific Paths

### Panel webserver — Caddy (replaces hestia-nginx)

| Item | Path |
|------|------|
| Binary | `/usr/sbin/caddy` (OS repo) |
| Config dir | `/etc/caddy/` |
| Global config | `/etc/caddy/Caddyfile` (global options + `import /etc/caddy/*.conf`) |
| Panel site config | `/etc/caddy/hestia.conf` |
| Port | `8083` (HTTPS) |
| Access log | `/var/log/hestia/caddy-access.log` |
| Error log | `/var/log/hestia/caddy-error.log` |
| Systemd unit | `caddy.service` |
| Install source | `conf/panel-caddy/` |

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
| Install source | `conf/panel-php/` |
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
| `WEBTPL` | `$HESTIA/templates/web` |
| `MAILTPL` | `$HESTIA/templates/mail` |
| `DNSTPL` | `$HESTIA/templates/dns` |
| `RRD` | `$HESTIA/web/rrd` |
| `SENDMAIL` | `$HESTIA/web/inc/mail-wrapper.php` |

---

## 4. Paths Changed from HestiaCP

| Item | HestiaCP | HestiaRE | Status |
|------|----------|----------|--------|
| Instance config dir | `/etc/hestiacp/` | `/etc/hestia/` | **Decided** |
| Bootstrap config file | `/etc/hestiacp/hestia.conf` | `/etc/hestia/hestia.env` | **Decided** |
| Local overrides | `/etc/hestiacp/local.conf` | `/etc/hestia/local.conf` | **Decided** |
| Install root | `/usr/local/hestia` | `/usr/local/hestia` | Unchanged — intentional |
| `$HESTIA` variable | `/usr/local/hestia` | `/usr/local/hestia` | Unchanged — no migration needed |
| Panel webserver | `hestia-nginx` package, `/usr/local/hestia-nginx/` | Caddy (OS repo), `/etc/caddy/hestia.conf` | **Decided** — see Q1 |
| Panel PHP | `hestia-php` package, `/usr/local/hestia-php/` | `hestia-php.service` (Sury php8.3-fpm), `/etc/php/hestia/fpm/` | **Decided** — Issue #25 |
| Shell profile comment | references `/etc/hestiacp/local.conf` | must reference `/etc/hestia/local.conf` | Fix in Issue #26; existence of file questioned (later issue) |
| Log dir name | `/var/log/hestia` | `/var/log/hestia` | Unchanged — OS path, no rebrand needed |
| Apt repo | `apt.hestiacp.com` | removed — no external hestia packages | **Decided** |

**Key insight:** Because the install root stays `/usr/local/hestia`, the `$HESTIA` variable and all 514 `bin/*` commands that reference it require only one change: the `source /etc/hestiacp/hestia.conf` line must become `source /etc/hestia/hestia.env`. The variable value itself is unchanged.

---

## 5. /etc/hestia/ Migration Plan

### 5a. Paths moving to /etc/hestia/ (data/-dissolution)

Migrated via the data/-dissolution PRs (#129 conf, #148 ips/queue/extensions/sessions,
later PRs firewall/users). Real move, no symlink bridge. Filenames preserved — no renames.

| Source (current) | Target | Notes |
|------------------|--------|-------|
| `/usr/local/hestia/conf/` | `/etc/hestia/conf/` | Panel instance config — **DONE (#129)**: `/usr/local/hestia/conf` is now a directory symlink → `/etc/hestia/conf`; the ~466 `$HESTIA/conf/hestia.conf` refs keep working and `sed -i` stays safe. Shipped assets (manifest/panel-*/dovecot) moved to `$HESTIA/share/`. |
| `/usr/local/hestia/conf/defaults/` | `/etc/hestia/conf/defaults/` | Stays under `conf/` (not flattened — matches §1 target); follows the conf symlink. **DONE (#129)** |
| `/usr/local/hestia/data/firewall/` | `/etc/hestia/firewall/` | Rules + ipset data — pending (object-helper guard PR) |
| `/usr/local/hestia/data/ips/` | `/etc/hestia/ips/` | IP address entries — **DONE (#148)** |
| `/usr/local/hestia/data/extensions/` | *dissolved* | PSL → `/etc/hestia/public_suffix_list.dat` (single file); mail-domain hooks → `/etc/hestia/hooks/` — **DONE (#148)** |
| `/usr/local/hestia/data/queue/` | `/etc/hestia/queue/` | Runtime named pipes (recreated fresh, never copied) — **DONE (#148)** |
| `/usr/local/hestia/data/sessions/` | `/usr/local/hestia/.sessions/` | PHP panel sessions (target under install root) — **DONE (#148)** |
| `/etc/hestiacp/hooks/` | `/etc/hestia/hooks/` | Lifecycle scripts (usually empty) |

### 5b. Deliberately not moved (pending separate analysis)

| Path | Reason |
|------|--------|
| `$HESTIA/data/users/` | Part of the backup format — dedicated PR after the object-helper guard |

### 5c. Known conflicts / open issues

**Two files named `hestia.conf` — resolved in Issue #81**

The naming conflict between the two `hestia.conf` files has been resolved:

1. **`/etc/hestia/hestia.env`** — Bootstrap file (renamed from `/etc/hestia/hestia.conf`).
   Sourced as the very first action by every `h-*`/`v-*` command. Sets `$HESTIA` and `$PATH`.
   Content: `export HESTIA='/usr/local/hestia'` + sources `local.conf`.

2. **`/usr/local/hestia/conf/hestia.conf`** — Panel instance config. Contains all
   active panel settings as `KEY='value'` pairs (WEB_SYSTEM, MAIL_SYSTEM, etc.).
   Unchanged — only file #1 was renamed.

hestiaweb/admin user consolidation remains a separate, future topic.

### 5d. Deferred to later issues

| Topic | Scope |
|-------|-------|
| `data/users/` | Backup format compatibility analysis required before any move |

---

## 6. Open Questions

| # | Topic | Status |
|---|-------|--------|
| Q1 | Caddy config structure | **DONE** — Issue #24 |
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
