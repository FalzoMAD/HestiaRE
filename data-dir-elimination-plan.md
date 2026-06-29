# Plan: `data/` vollständig auflösen (#133, erweiterter Scope)

> Ausgegliedert aus `wizard-cleanup-plan.md` und nach gemeinsamer Planungssession
> (6 Explore-Agents) auf den **echten Move des gesamten `data/`-Baums** erweitert.
> Ziel: `/usr/local/hestia/data/` vollständig auflösen — keine Symlink-Bridges.

## Context

Der Installer läuft erstmals durch; nächster großer Schritt ist, das Verzeichnis
`/usr/local/hestia/data/` **vollständig aufzulösen** — als saubere Grundlage *vor*
der Modularisierung (#119–#123) und vor den Panel-Blockern #137/#138. Der Autor will
einen **echten Move** (keine Symlink-Bridges wie bei `conf/` in #129) und hat bestätigt,
data/ vor der Weiterarbeit am Installer abzuschließen.

Die Recherche hat drei Prämissen des ursprünglichen Issues korrigiert:

1. **Kein Asset-Beschaffungsproblem.** `data/` existiert weder im Repo noch im Tarball —
   es wird **zur Installzeit gebaut**: `init_hestia_structure()` (`bin/h-install-hestia:518-540`)
   legt die Dirs an, `configure_hestia()` (`:569-587`) kopiert Inhalte aus dem
   committeten, im Tarball enthaltenen `install/common/` + `install/deb/` hinein. Templates
   shippen also bereits vollständig. Der „Move" ist damit: **Kopier-/Anlege-Ziel umstellen
   + Referenzen umstellen**, nicht „Assets suchen".
   *(Die fehlenden `install/common/templates/dns/`-Presets sind KEIN Bug — DNS/bind9 wurde
   in HestiaRE bewusst entfernt; diese Templates werden nicht gebraucht.)*

2. **Die relativen Pfade sind tiefenabhängig von `USER_DATA` — und betreffen mehr als
   firewall.** `../../../data/firewall/...` **und** `../../../conf/$type` (DB-Hosts!)
   funktionieren nur, weil `USER_DATA=$HESTIA/data/users/$user` exakt 3 Ebenen unter
   `$HESTIA` liegt. Sobald `data/users` nach `/etc/hestia/users` wandert, lösen **alle**
   diese Pfade falsch auf (`/etc/...` statt `$HESTIA/...`). Der Absolut-Pfad-Guard ist
   damit Voraussetzung für **firewall- UND users-Move** und muss auch die **DB-Host-Caller**
   umstellen. Grund für die relativen Pfade: reines Upstream-HestiaCP-Idiom (Wiederverwendung
   der user-skopierten Object-Helper für globale Dateien) — **kein** Security-/Jail-Grund.

3. **users-Move ist durchgängig de-riskt.** Jails liegen unter `/srv/jail/$user` + `/home`
   (`func/main.sh:1956-2013`), **nicht** unter `data/users`. Backups sind standort-agnostisch
   (`func/backup.sh:42` baut mit `cd $tmpdir; tar -cf … .` — kein `data/users`-Pfad im
   Archiv); alte HestiaCP-Archive restoren unverändert. Nötig: `USER_DATA` (`func/main.sh:45`)
   + wenige hardcodierte `$HESTIA/data/users`-Stellen.

**REST-API:** `data/access-keys` ist **keine TFA**, sondern REST-API-Auth-Tokens — mit
vollem Panel-UI, 5 Commands und einem noch lebenden `web/api/index.php`. Die API-Entfernung
(Ground Rule) ist also unvollständig. **Entscheidung: jetzt mit erledigen** (eigener PR).

---

## Zielzuordnung pro Subdir

**Trennkriterium:** Bei frischem Tarball-Auspacken befüllt → `/usr/local/hestia/…`;
leer bei Install, reine Laufzeit-Befüllung → `/etc/hestia/…`.

| Subdir | Ziel | Mechanik | PR |
|---|---|---|---|
| `data/api` | **DELETE** | REST-API-Reste | PR1 |
| `data/access-keys` | **DELETE** | REST-API-Auth-Tokens | PR1 |
| `data/keys` | **DELETE** | von `web/api/index.php:144` referenziert | PR1 |
| `data/extensions` | `/etc/hestia/extensions` | Move (PSL-Cache + Mail-Domain-Hooks) | PR2 |
| `data/sessions` | `/usr/local/hestia/.sessions` | Move + `panel.conf:35` | PR2 |
| `data/ips` | `/etc/hestia/ips` | Move (direkte Pfade) | PR2 |
| `data/queue` | `/etc/hestia/queue` | Move, Einträge **frisch neu anlegen** | PR2 |
| `data/packages` | `/usr/local/hestia/packages` | Move (shippt befüllt) | PR2 |
| `data/templates` | `/usr/local/hestia/templates` | Move (shippt befüllt) | PR2 |
| `data/firewall` | `/etc/hestia/firewall` | Move **nach** Guard-Fix | PR3 |
| `data/users` | `/etc/hestia/users` | Move **nach** Guard-Fix | PR4 |

`data/extensions` ist **kein** Einzelfile: `func/domain.sh:791-847` liest den
runtime-gecachten `public_suffix_list.dat` (Auto-Refresh von publicsuffix.org), und
`h-add-mail-domain:199` / `h-delete-mail-domain:83` führen optionale Operator-Hooks
`add-/delete-mail-domain.sh` aus. Kein UI. → Ganzes Dir nach `/etc/hestia/extensions`
verschieben; optionale spätere Konsolidierung mit `/etc/hestia/hooks` nur als Notiz.

`data/queue`: `init_hestia_structure:530` legt die `.pipe`-Einträge aktuell per `touch`
an (nicht `mkfifo`). Bei der Migration **nicht kopieren**, sondern am neuen Ort frisch
anlegen (aktuelles Verhalten beibehalten).

---

## PR-Struktur (4 PRs auf `dev`, Autor reviewt/merged je einzeln)

### PR1 — `feature/<n>-remove-rest-api` (REST-API final entfernen)
Keine Object-Helper-Kopplung; entfernt 3 Subdirs sauber. **De-Wiring zuerst, dann löschen.**
- **De-Wire:** Access-Key-Sektion in `web/templates/pages/edit_user.php`; Navigation/Links
  zur Access-Key-Seite; KEY-Zweig in `is_object_valid()` (`func/main.sh:330-335`).
- **Löschen Panel:** `web/api/`, `web/list/access-key/`, `web/add/access-key/`,
  `web/delete/access-key/`, `web/bulk/access-key/`, `web/templates/pages/{list_access_keys,
  list_access_key,add_access_key}.php`.
- **Löschen Commands + v-Symlinks (keine Orphans):** `h-add-access-key`,
  `h-delete-access-key`, `h-list-access-key`, `h-list-access-keys`, `h-check-access-key`.
- **Löschen func:** `check_access_key_secret/_user/_cmd` (`func/main.sh:1532-1621`).
- **Löschen data-Anlage/Refs:** `data/api` + `data/access-keys` + `data/keys` aus
  `configure_hestia` (`cp … api`, `:587`) und `init_hestia_structure`; alle Restreferenzen.
- **Verify-Gate:** `grep -rn` zeigt keine Treffer mehr auf `access-key`, `web/api`,
  `data/keys`, `data/access-keys`, `data/api`.

### PR2 — `feature/<n>-data-simple-moves` (einfache Moves, kein Object-Helper)
extensions, sessions, ips, queue, packages, templates.
- **Installzeit:** `init_hestia_structure` (`:522-538`) + `configure_hestia` (`:569-587`)
  auf neue Zielpfade umstellen (Dirs anlegen + Kopier-Ziele `packages`/`templates`).
- **Referenzen:** alle `$HESTIA/data/{extensions,sessions,ips,queue,packages,templates}`
  in `bin/` + `func/` auf die neuen absoluten Pfade umstellen (inkl.
  `is_backup_scheduled` `…/data/queue/backup.pipe` in `func/main.sh:301`).
- **sessions:** zusätzlich `share/panel-php/pool.d/panel.conf:35`
  (`session.save_path = …/data/sessions` → `…/.sessions`).
- **queue:** Einträge am Zielort frisch anlegen (kein Kopieren).
- **Migration Bestand:** über `migrate_data_layout()` (s. u.).

### PR3 — `feature/<n>-object-guard-firewall` (Guard + firewall + DB-Hosts)
- **Guard** in den 6 Object-Helpern ergänzen (`get_object_value`, `get_object_values`,
  `update_object_value`, `search_objects` — `func/main.sh:601-650`; `is_object_new`,
  `is_object_valid` — `:310-344`), USER-/KEY-Sonderfälle unverändert:
  ```bash
  if [[ "$1" == /* ]]; then conf="$1.conf"; else conf="$USER_DATA/$1.conf"; fi
  ```
  Rückwärtskompatibel (kein heutiger Caller übergibt absolute Pfade).
- **Caller auf absolut umstellen:**
  - firewall rules (9 Calls): `'../../../data/firewall/rules'` → `'/etc/hestia/firewall/rules'`
    in `h-add/delete/change/move/list/suspend/unsuspend-firewall-rule`.
  - ipset (3 Dateien): `ipset_hstobject='../../../data/firewall/ipset'` →
    `'/etc/hestia/firewall/ipset'`.
  - **DB-Hosts (6 Dateien):** `"../../../conf/$type"` → `"$HESTIA/conf/$type"` in
    `h-add-database`, `h-{change,suspend,unsuspend,delete}-database-host`,
    `h-list-database-host`.
- **firewall-Move:** `init_hestia_structure`/`configure_hestia` (Kopier-Ziel + `sed -i`
  auf `rules.conf` `:578-586`), direkte Caller (`h-add/delete-firewall-ban` → `ban.conf`,
  `h-add/delete-firewall-chain` → `chains.conf`, `h-change-sys-port:78`), alle restlichen
  `$HESTIA/data/firewall`-Refs.
- **Gezielter Test:** `is_object_valid` mit absolutem UND (legacy) relativem Pfad;
  `h-add-firewall-ipset` + `h-update-firewall-ipset` end-to-end.

### PR4 — `feature/<n>-data-users` (users-Move, direkt nach PR3)
- `USER_DATA=$HESTIA/data/users/$user` → `/etc/hestia/users/$user` (`func/main.sh:45`).
- Hardcodierte `$HESTIA/data/users`-Stellen: `is_object_valid:326-337`,
  `h-restore-user:105,177,581-582` (`…/ssl/` → `$USER_DATA/ssl/`), `h-backup-users:35-41`.
- Alle übrigen `$HESTIA/data/users`-Refs (die meisten laufen bereits über `$USER_DATA`).
- **Migration Bestand:** `data/users` → `/etc/hestia/users` (s. u.).
- **Pflicht-Test:** Restore eines **alten HestiaCP-Archivs** in den neuen Pfad
  (verifiziert Standort-Agnostik); Backup→Restore-Round-Trip.

### Abschluss (Teil von PR4)
`PATHS.md` (§5a/§5b auf DONE) + `CODEMAP.json` durchgängig aktualisieren; verifizieren,
dass `$HESTIA/data/` nach allen vier PRs leer/entfernt ist.

---

## Migration für Bestandsinstallationen (echter Move, keine Symlinks)

Neue, idempotente `migrate_data_layout()` in `func/helper.sh`, aufgerufen von
`h-install-hestia` (frisch = No-op, Dirs entstehen direkt am Zielort) **und**
`h-update-hestia` (Bestand). Pro Subdir: wenn Quelle existiert und Ziel nicht → `mv`
(queue: frisch neu anlegen statt mv). Da es ein echter Move ohne Bridge ist, muss die
Migration im Update-Transaktionsfenster laufen: in `h-update-hestia` zwischen
Tarball-Extraktion (neuer Code) und `systemctl start hestia` (`bin/h-update-hestia:68-72`),
damit nie neuer Code auf alte Pfade trifft.

---

## Risiken & offene Punkte
- **Reihenfolge zwingend:** PR3 (Guard) **vor** PR4 (users) — sonst brechen die noch
  relativen firewall/DB-Host-Pfade beim Tiefenwechsel von `USER_DATA`.
- **Update-Fenster:** Migration muss vor Panel-Start abgeschlossen sein (s. o.).
- **`web/api`-Entfernung** darf keine Nicht-API-Funktion treffen — Verify-Gate per grep.
- Mail-Domain-Hooks ggf. später mit `/etc/hestia/hooks` konsolidieren (nur Notiz).

## Verifikation
- Pro PR: `bash -n` geänderte Skripte, `jq empty` falls JSON, `php -l` geänderte PHP.
- **PR1:** Panel lädt ohne Access-Key/API-Spuren; `grep -rn` sauber.
- **PR2:** Frischinstall legt Subdirs an neuen Orten an; PHP-Sessions funktionieren
  (`panel.conf:35`); `grep -rn '\$HESTIA/data/\(extensions\|sessions\|ips\|queue\|packages\|templates\)'` leer.
- **PR3:** firewall-Rule + ipset-Operation (inkl. `sed -i`-Schreiber wie `h-change-sys-port`)
  laufen fehlerfrei; Guard löst absolute UND relative Pfade korrekt auf.
- **PR4:** Restore eines alten HestiaCP-Archivs in `/etc/hestia/users` erfolgreich;
  `$HESTIA/data/` final leer.
- Bestands-Upgrade auf VM: `h-update-hestia` migriert alle Subdirs, Panel startet sauber.
