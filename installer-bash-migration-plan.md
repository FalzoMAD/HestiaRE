# Plan: Installer von `just` auf reine Bash-`h-*`-Commands umstellen

## Context

HestiaRE ist ein schlanker HestiaCP-Fork. HestiaCP ist **100 % Bash**: ein ~2.500-Zeilen-Bash-Installer, 465 `h-*`-Commands (aus `v-*` umbenannt), ~8.000 Zeilen `func/*.sh`. Die aktuelle Installer-Schicht (`Justfile` + `just/*`) wurde als Zwischenschritt gebaut, ist aber laut Audit ~61 % Inline-Bash + ~39 % `h-*`-Aufrufe — überwiegend ein Wrapper ohne echten Orchestrierungsgewinn. `just` nutzt genau **eine** Abhängigkeitskante und 2 triviale Parameter; ein Task-Runner ist hier überdimensioniert. Zudem ist `just` auf Debian 12 (Primärziel) nicht paketiert und erzwang einen gepinnten Binary-Bootstrap (#109/#110) — ein Ground-Rule-Konflikt.

**Ziel:** `just` entfernen, Installer-/Lifecycle-Logik als reine Bash-`h-*`-Commands realisieren, die sich ins bestehende Command-Ökosystem einfügen und vorhandene `h-add-sys-*` nutzen. Ergebnis: ein lauffähiger, abhängigkeitsärmerer Installer in der Muttersprache des Projekts; die `just`/Debian-12-Pinned-Binary-Saga entfällt ersatzlos. (Bestätigt durch zwei unabhängige Analysen, eine bewusst *für* `just`; Go/Rust verworfen: bringt Per-Arch-Build/Release-Last zurück + Fremdsprache.)

## Bestätigte Rahmenbedingungen

- **`install.sh` bleibt im Repo-Root** als per `curl` gezogener Bootstrap. Verantwortung: Prereqs, OS-Detect, Dev-Source, Tarball ziehen/entpacken, Wizard ausführen, **`/etc/hestia` seeden**, dann `h-install-hestia` aufrufen.
- **Wizard ausgelagert → `func/wizard.sh`** (whiptail + Manifest, schreibt `install.conf`). **Einzeln ausführbar**, um die `install.conf` jederzeit neu zu generieren; danach kann `h-install-hestia` manuell laufen. Gekapselt über `hestia configure` + `hestia install`.
- **`install.sh` legt `/etc/hestia/{hestia.env, hestia.conf (Seed), profile.d/hestia.sh}` selbst an** (nach dem Wizard, via `func/helper.sh`). Dadurch entfällt die „Bootstrap-Falle" (s. u.): `h-install-hestia` ist ein normales h-* Command, das env/conf gefahrlos sourcen kann.
- **Helfer-Bibliothek → `func/helper.sh`** (bewusst **nicht** `func/install.sh`, um Verwechslung mit `install.sh` zu vermeiden; kurzer, einfacher Name; künftige Heimat für allgemeine Helfer). Enthält: `hestia_apt` (Spinner+Log-Split, aus `just/helpers.sh`), `load_os_profile` (OS-Daten, ersetzt `just/*.sh`), `seed_hestia_etc` (env/conf/profile.d).
- **`install.conf`-Vertrag + `conf/manifest.json` + Wizard-Verhalten bleiben unverändert** — nur der *Konsument* wechselt von `just install` → `h-install-hestia`.
- **`func/`-Sourcing-Mechanismus bleibt** (`source $HESTIA/func/main.sh`). Kein Umbau zu einem anderen „include"-System (hoch riskant, null Gewinn, HestiaCP-Kompat hängt daran).
- **Alle vier Ziel-OS als vollwertig:** deb12, ub24 **und** deb13, ub26 — **kein Stub-Fehler**. deb13/ub26 werden direkt mitentwickelt; Logik/Config aus `upstream/hestiacp` reinziehen (deb13 dort gemergt, inkl. Dovecot-2.4-Besonderheiten). ub26 best-effort, Codename noch zu bestätigen (mirror von noble/trixie).
- **Komponenten-Scope:** Stage-Logik zunächst inline nach `h-install-hestia` portieren, bestehende `h-add-sys-*` wiederverwenden; jede wählbare Komponente *danach* schrittweise zu eigenem `h-add-sys-*`/`h-remove-sys-*` extrahieren (Ground Rule „individuell entfernbar").
- **`install/ → conf/` entkoppelt:** `install/` ist ein **Laufzeit-Asset-Baum** (`$HESTIA_INSTALL_DIR`, `$HESTIA_COMMON_DIR`), den ~16 `h-*`-Commands + `func/main.sh` lesen. Installer nutzt diese Pfade vorerst weiter; Verlagerung nach `conf/` ist ein **separates Issue** mit Audit.

## Zielarchitektur (Dateilandkarte)

```
/install.sh             Bootstrap (curl|bash): prereqs, OS-detect, dev-source, Tarball fetch+extract,
                        sourct func/helper.sh + func/wizard.sh -> Wizard -> seed_hestia_etc -> h-install-hestia
/func/wizard.sh         whiptail-Wizard (aus install.sh ausgelagert), einzeln ausführbar -> schreibt install.conf
/func/helper.sh         allgemeine Helfer: hestia_apt (Spinner+Log), load_os_profile (OS-Daten alle 4 OS),
                        seed_hestia_etc (hestia.env/hestia.conf/profile.d)   (ersetzt just/helpers.sh + just/*.sh)
/bin/h-install-hestia   Orchestrator: dünne Validierung von /etc/hestia/* -> sonst Verweis auf install.sh/wizard.sh;
                        liest install.conf, COMPONENT_*-gesteuert; base/panel/configure inline, ruft h-add-sys-*
/bin/h-update-hestia    Distro-Update aus Release-Tarball (+ --check) (ersetzt just update/_do-update/check-updates)
/bin/h-uninstall-hestia konservativer Uninstall (ersetzt just-uninstall-Platzhalter; /home/$user + DBs bleiben)
/bin/h-list-sys-install Status (ersetzt just status; folgt h-list-sys-* Familie)
/bin/hestia             Dachmarke: `hestia install|configure|update|uninstall|status` -> dispatcht h-*
```

`h-*`-Neulinge bekommen **kein v-* Symlink** (Namen existierten nie in HestiaCP). `bin/hestia` ist bewusste Ausnahme von der h-* Konvention (Dachmarke, kein CRUD). Die h-* sind die Workhorses, `hestia <verb>` die schöne UX (der eigentliche, rein menschliche Grund, der zuvor `just` motivierte).

## Bootstrap-Reihenfolge (löst die „Bootstrap-Falle")

`func/main.sh` sourct beim Laden `/etc/hestia/hestia.env` + `hestia.conf`, die beim Erstinstall fehlen. Lösung: **`install.sh` erzeugt sie, bevor irgendein h-* Command läuft:**

```
install.sh:
  prereqs (curl, jq, whiptail, gnupg, ca-certificates) + ERR-Trap   # aus #109/#110 behalten
  OS-Detect -> INSTALL_OS
  [--dev] dev-source
  fetch + extract Tarball -> /usr/local/hestia
  source func/helper.sh ; source func/wizard.sh
  run_wizard            # schreibt /etc/hestia/install.conf
  seed_hestia_etc       # /etc/hestia/hestia.env, profile.d/hestia.sh, Seed-hestia.conf (Defaults + ROOT_USER/PORT aus install.conf)
  exec h-install-hestia

h-install-hestia:
  validate: /etc/hestia/{install.conf,hestia.env,hestia.conf} vorhanden? sonst ERROR -> "bash install.sh" bzw. "wizard.sh"
  source hestia.env ; source func/main.sh ; source func/helper.sh ; source_conf hestia.conf ; source install.conf
  load_os_profile "$INSTALL_OS"
  Stages (s. u.) ; log_event "$OK"
```

Standalone-Flow (System bereits geseedet): `hestia configure` (= `func/wizard.sh`) → `hestia install` (= `h-install-hestia`).

## COMPONENT_*-Verdrahtung (Kern des Mehrwerts)

Ersetzt den heute kaputten `just "_profile-${INSTALL_PROFILE}"`-Dispatch (nur `standard`/`minimal` existieren). `h-install-hestia` verzweigt über `COMPONENT_*`:

| install.conf | wirkt auf | Verhalten |
|---|---|---|
| `COMPONENT_MAIL_BLOCK_PRESENT` | Mail | `true` → Mail-Stack; `false` → überspringen (ersetzt `_profile-*`) |
| `COMPONENT_WEB_SERVER` | Web | `NGINX`/`BOTH`/`APACHE` → Pakete + Reverse-Proxy |
| `COMPONENT_PHP_MODE` / `_PHP_MULTIPHP_VERSIONS` | Web/PHP | Sury an/aus; `for v in $...; do h-add-web-php "$v"; done` |
| `COMPONENT_DB_MARIADB_VERSION` | DB | echte Version (aus `__os__` aufgelöst); Repo nur wenn nötig |
| `COMPONENT_DB_PHPMYADMIN` / `_POSTGRESQL` / `_PGADMIN` / `_REDIS` | DB | bedingt; phpMyAdmin über `h-add-sys-phpmyadmin` |
| `COMPONENT_MAIL_WEBMAILER` | Mail | `h-add-sys-roundcube` vs `h-add-sys-snappymail` vs nichts |
| `COMPONENT_ADDON_*` (rspamd, sieve, proftpd, fail2ban, crowdsec, docker, filemanager, utilities, composer) | div. | bedingt; vorhandene `h-add-sys-*` nutzen, fehlende inline (später extrahieren) |
| `HESTIA_PANEL_PORT` | seed/configure | **heute ignoriert** (hartkodiert 8083) → an gewählten Port binden |

## Umsetzung in reviewbaren Schritten (je ein PR auf `dev`)

1. **`func/helper.sh`** anlegen: `hestia_apt` (aus `just/helpers.sh`), `load_os_profile` (case für **alle vier** OS — deb12/ub24 aus heutigen `just/*.sh`, deb13/ub26 aus `upstream/hestiacp` reinziehen), `seed_hestia_etc` (env/conf/profile.d, aus `just/configure:_bootstrap-hestia-env`). Noch nicht verdrahtet.
2. **`bin/h-install-hestia`** bauen: Stages aus `just/{base,panel,web,db,mail,security,tools,configure}` + `_init-hestia-structure`/`_finalize` portieren; **jedes `exit 0/1` → `return`/`check_result`** (eine Prozessinstanz statt vieler Recipes!); COMPONENT_* verdrahten; `h-add-sys-*` aufrufen; dünne `/etc/hestia/*`-Validierung am Anfang. Parallel zu `just install` testbar.
3. **Wizard auslagern + Cutover:** Wizard-Logik `install.sh` → `func/wizard.sh` (einzeln ausführbar); `install.sh` ruft nach Extraktion Wizard + `seed_hestia_etc` + `h-install-hestia` statt `just install`; `_ensure_just`/`_install_just_binary`/`JUST_*` löschen. **`gnupg`-Prereq + ERR-Trap aus #109/#110 bleiben** (Wizard braucht gpg für Sury; Trap weiter nützlich).
4. **Lifecycle-Commands:** `bin/hestia` (Dispatcher inkl. `configure`→wizard, `install`→h-install-hestia) + `h-update-hestia` (+`--check`) + `h-uninstall-hestia` + `h-list-sys-install` aus `Justfile` portieren. `h-update-hestia` mit `systemctl stop/start hestia` um den `cp -r`.
5. **deb13/ub26 zur Parität bringen:** OS-Profile + benötigte Config-Deltas aus `upstream/hestiacp` (deb13 gemergt; Dovecot 2.4 — vgl. vorhandene Ansätze in `just/mail`); ub26 best-effort + Codename-TODO. Auf deb13-VM testen.
6. **Aufräumen:** `Justfile` + `just/` löschen; `CODEMAP.json` + `CLAUDE.md` (just-Erwähnungen) aktualisieren.

## Was gelöscht wird (Payoff)

- `Justfile`, gesamtes `just/` (11 Dateien, ~490 Zeilen).
- Aus `install.sh`: `_ensure_just`, `_install_just_binary`, `JUST_VER`/`JUST_SHA256_*` — die komplette #109/#110-Pinned-Binary-Maschinerie (PR #110 wird dadurch teilobsolet; gnupg-Prereq + ERR-Trap bleiben).
- Netto: **keine Nicht-Bash-Laufzeitabhängigkeit** für den Install außer den apt-Tools, die jedes Debian/Ubuntu mitbringt.

## Out of Scope (eigene Folge-Issues)

- **`install/ → conf/`-Verlagerung** (Pfadvars in `func/main.sh` + ~16 `h-*`-Commands + Installer). Eigenes Issue mit Audit.
- **Modularisierung** jeder Komponente zu `h-add-sys-*`/`h-remove-sys-*` (nginx, apache, mariadb, exim, dovecot, rspamd, postgresql, redis, proftpd, fail2ban, crowdsec, docker) — schrittweise nach Iteration 1; jede ermöglicht zugleich Add/Remove nach der Installation.

## Risiken & Schlüssel-Mechanik

- **`exit` → `return`:** unter `just` war jede Stage ein eigener Prozess; jetzt eine Instanz. Ein übersehenes `exit 0` in einem `.done.*`-Guard bricht den ganzen Install ab. Jede portierte Datei auditieren.
- **Bootstrap-Falle — gelöst** durch `seed_hestia_etc` in `install.sh` vor jedem h-* Aufruf; `h-install-hestia` validiert nur noch Anwesenheit. (Standalone-Re-Runs setzen ein bereits geseedetes `/etc/hestia` voraus — von der Validierung abgedeckt.)
- **`install.conf`-Vertrag stabil** (Variablennamen), damit der unveränderte Wizard passt.
- **`HESTIA_MPASS` / `.admin_pass.tmp`-Handoff** aus `just/db`→`configure` beibehalten (Resumability).
- **Idempotenz:** `.done.*`-Sentinels + „already installed? return 0"-Checks behalten; `set -euo pipefail` zentral; `|| true`-Stellen auditieren.
- **deb13/ub26 Abhängigkeit von `upstream/hestiacp`:** vorhandene Logik/Config reinziehen statt neu erfinden; ub26-Codename unbestätigt → klar markieren, Verhalten an noble/trixie spiegeln.

## Verifikation (End-to-End)

Auf frischen Test-VMs **Debian 12, Ubuntu 24.04, Debian 13** (Proxmox; ub26 sobald verfügbar):
1. `bash install.sh` → Wizard → `install.conf` → `/etc/hestia` geseedet → `h-install-hestia` läuft durch; Panel auf gewähltem `HESTIA_PANEL_PORT` erreichbar; Admin-Login.
2. **Standalone:** `hestia configure` (Wizard allein) → `install.conf` neu → `hestia install` → erfolgreich.
3. **Preset-Matrix:** `standard`, `nomail`, `mailonly`, `singlephp` → korrekte Komponenten gemäß COMPONENT_*.
4. **Idempotenz:** `hestia install` erneut → fertige `.done.*`-Stages übersprungen, kein Abbruch.
5. **Lifecycle:** `hestia status`; `hestia update --check`; `hestia uninstall` (lässt `/home/$user` + DBs intakt).
6. **Abhängigkeits-Beweis:** auf System ohne `just` läuft alles vollständig (keine `just`-Referenz mehr).
7. `bash -n` + `shellcheck` über alle neuen Skripte.

## Kritische Dateien

- `/home/claude/hestiare/install.sh` (Bootstrap; Wizard raus; seed + `h-install-hestia`; #109/#110-just-Teile löschen)
- `/home/claude/hestiare/func/wizard.sh` (NEU — Wizard, einzeln ausführbar)
- `/home/claude/hestiare/func/helper.sh` (NEU — hestia_apt, load_os_profile [4 OS], seed_hestia_etc)
- `/home/claude/hestiare/bin/{h-install-hestia,h-update-hestia,h-uninstall-hestia,h-list-sys-install,hestia}` (NEU)
- `/home/claude/hestiare/func/main.sh` (Sourcing-/Fehler-/Pfad-Vertrag; Load-Zeit-Sourcing beachten)
- `/home/claude/hestiare/conf/manifest.json` (COMPONENT_*-Vertrag)
- `upstream/hestiacp` (Quelle für deb13/ub26 OS-Profile + Dovecot-2.4-Config)
- `/home/claude/hestiare/Justfile` + `just/*` (Portierungsquelle, dann gelöscht); `CODEMAP.json`, `CLAUDE.md` (just-Referenzen)
