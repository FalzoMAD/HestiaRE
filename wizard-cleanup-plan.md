# Plan: Wizard- & Cleanup-Cluster (#132, #103, #61, #128)

## Context

Der Installer ist erstmals vollständig durchgelaufen (`install.sh` → `func/wizard.sh`
→ `bin/h-install-hestia`) — ein Meilenstein. Das resultierende System ist aber noch
**nicht nutzbar**: zwei Blocker (`#137` Bundled-PHP-CLI, `#138` `hestia.service`) verhindern
ein funktionierendes Panel. Ein Audit der Install-Strecke bestätigt: **kein Eisberg** —
die Breakages clustern sauber in `#137`, `#138`, `#128` plus etwas kosmetischer Dead-Code.

Entscheidung des Autors (abgestimmt): als nächstes der **Wizard/Cleanup-Cluster**, nicht der
„grüne Install". **Hinweis bleibt:** `#137` + `#138` sind die eigentlichen Blocker zu einem
benutzbaren Panel und sollten der Meilenstein *unmittelbar nach* diesem Cluster sein.

**Scope dieses Plans:** `#132` (Wizard Englisch + Politur), `#103` + `#61` (foundational
Issues im Cleanup auflösen, *bevor* die Per-Komponente-Modularisierung #120–#123 startet),
`#128` (Legacy-Update-Subsystem entfernen).

**Ausgegliedert:** `#133` (data/firewall + data/ips → /etc/hestia) ist **nicht** Teil dieses
Plans. Der echte Move ist groß und wird im **Gesamtblick auf alle `data/`-Inhalte** gesondert
betrachtet → eigenes Dokument **`data-dir-elimination-plan.md`**.

Getrennte Branches/PRs auf `dev` (Autor reviewt/merged je einzeln). Empfohlene Reihenfolge:
**#132 → #103/#61 (Foundation) → #128** — #132 zuerst (sofort im Test sichtbar), Foundation
vor der späteren Modularisierung, #128 zuletzt (berührt Panel-UI).

---

## Teil A — #132: Wizard vollständig auf Englisch + Label/Description-Politur

**Branch:** `feature/132-wizard-english`

### A1 — Übersetzung (Kernarbeit, `share/manifest.json`)
Alle **nutzersichtbaren** Strings ins Englische. `note`/`$comment`/`$parser` sind interne
Doku und bleiben unangetastet. Konkrete Felder (per `jq` verifiziert):
- `presets[].label` (7 Stück, z. B. „Standard (volles Hosting …)" → „Standard (full hosting …)")
- `pre_questions[].question` (Hostname/Panel-Port/Admin-Benutzername/Admin-E-Mail) — Hinweis: `func/wizard.sh` stellt die Pre-Fragen aktuell mit *eigenen* englischen Strings (`fn_ask_pre_questions`, Z. ~207). Einheitlich auf eine Quelle ziehen, damit Manifest und Wizard nicht divergieren.
- `group_questions.db` / `.addons`
- `components[].question` (WEB_SERVER, WEB_REPO_SOURCE, PHP_MODE, PHP_MULTIPHP_VERSIONS, DB_*, MAIL_BLOCK_PRESENT, MAIL_WEBMAILER)
- `components[].description` (die in #134/#135 ergänzten DB/Addon-Beschreibungen sind noch deutsch; + implicit-Beschreibungen WEB_REPO_SOURCE/PHP_MODE/MAIL_BLOCK_PRESENT)
- `tools.selection.question`
- `DB_MARIADB_VERSION.options[].label_template` („{version} (OS-Version)" → „{version} (OS default)")

### A2 — `func/wizard.sh` Reststrings
- `fn_manifest_load`: deutsche ERROR-Texte („ist unvollstaendig oder hat eine falsche Struktur", „fehlt", „falscher Typ") → Englisch.
- Fallback `"Auswahl: " + $g` (Z. ~527) → `"Select: "`.
- Restliche `echo`/ERROR sind bereits englisch — kurz gegenchecken.

### A3 — Label/Description für radio & version_select (Politur, wie zuvor zugesagt)
Heute zeigt `_ask_radio` den rohen Enum-Wert doppelt (Tag = Item, z. B. `NGINX  NGINX`) —
dasselbe Muster, das wir für die Gruppen-Checkboxen in #134 schon gelöst haben.
- **Manifest-Schema:** `options` darf neben dem String-Array auch die Objektform
  `{ "value", "label", "description" }` annehmen (version_select nutzt schon Objekt-Optionen).
- **Wizard:** `_ask_radio` (und konsistent `_ask_version_select`) so erweitern, dass bei
  Objekt-Optionen `label` als Tag und `description` als zweite Spalte gerendert wird, der
  ausgewählte Tag aber weiterhin auf `value` zurückgemappt wird; reine String-Optionen
  bleiben unverändert (hält den dynamischen `PHP_MULTIPHP_VERSIONS`-Pfad simpel).
- **Betroffen:** WEB_SERVER (apache/nginx/both), MAIL_WEBMAILER (roundcube/snappymail/none),
  und die `custom`-only impliziten (WEB_REPO_SOURCE, PHP_MODE, MAIL_BLOCK_PRESENT).

**Kritische Dateien:** `share/manifest.json`, `func/wizard.sh` (`_ask_radio`, `_ask_version_select`, `fn_manifest_load`, `fn_ask_pre_questions`).

---

## Teil B — Foundational Issues im Cleanup auflösen (#103, #61)

Beide lassen sich **jetzt** abschließen — bevor die Per-Komponente-Modularisierung
(#120–#123) beginnt — statt sie als Altlast mitzuschleppen.

### #103 — Interactive Wizard + install.conf als System-State
**Branch:** `feature/103-install-conf-state`
- **Wizard: erledigt.** `func/wizard.sh` (manifest-getrieben) übertrifft die Issue-Skizze
  deutlich. Veralteter Bezug „Issue #102 (make→just) zuerst" entfällt (wir sind bei Bash, #112).
- **install.conf als Live-State** (von `h-add-*`/`h-remove-*` gepflegt): noch offen und
  konzeptionell Teil der Modularisierung. **Im Cleanup machbar = die Foundation:** ein
  gemeinsamer Mechanismus, der einen `COMPONENT_*`-Key in `/etc/hestia/install.conf` setzt
  (kleiner Helper, analog zum vorhandenen `h-change-sys-config-value`), und `h-install-hestia`
  schreibt den finalen Komponentenstand. Danach rufen #120–#123 nur noch diesen Helper.
- **Empfehlung:** Foundation jetzt bauen → **#103 schließen**; die per-Komponente-Verdrahtung
  bleibt Akzeptanzkriterium in #120–#123 (dort bereits als „install.conf-COMPONENT_*
  aktualisieren" referenziert). Leichtere Alternative: nur den Wizard-Teil als erledigt
  schließen und den Live-State komplett an #120–#123 delegieren.

### #61 — Fehlerbehandlung / Recovery-Strategie
**Branch:** `feature/61-installer-recovery`
- Der Bash-Installer liefert den **technischen Teil bereits**: `set -eo pipefail`, ERR-Trap mit
  Log-Auszug (`_on_error`, `h-install-hestia:21–27`) und `.done.*`-Sentinels pro Stage →
  ein erneuter Lauf **resumed** automatisch (fertige Stages werden übersprungen).
- **Entscheidung (genau das fordert das Issue): Option 3** — sauberer Stop + verständliche
  Fehlermeldung + dokumentierte manuelle Recovery; **kein** automatischer Paket-/Service-/DB-
  Rollback (für ein internes Tool mit ~30 Kunden der richtige Zuschnitt). Resume ist über die
  bestehenden Sentinels schon gegeben.
- **Deliverable:** kurze `TROUBLESHOOTING.md` („Stage X fehlgeschlagen → `/var/log/hestia/install.log`
  prüfen, Ursache beheben, `h-install-hestia` erneut ausführen — überspringt fertige Stages");
  optional dünnes `hestia install --resume`/Status als Komfort. Danach **#61 schließen**.
  Veraltete `make install`-Bezüge im Body entfallen.

---

## Teil C — #128: Legacy-Paket-Update-Subsystem entfernen

**Branch:** `feature/128-remove-legacy-update`
Vollständig inventarisiert. **De-Wiring zuerst, dann löschen** (keine toten Links/Crons).

### C1 — De-Wiring (zuerst)
- `web/templates/pages/list_services.php` (Z. 11): „Updates"-Button (Link `/list/updates/`) entfernen — sonst toter Menüpunkt.
- `func/syshealth.sh`: Default-Autoupdate-Cron (Z. 547) entfernen; Config-Keys `RELEASE_BRANCH`/`UPGRADE_SEND_EMAIL`/`UPGRADE_SEND_EMAIL_LOG` aus `known_keys` (Z. 169) + Health-Repair (Z. 196–271).
- `func/helper.sh` `seed_hestia_etc`: `_wcv`-Zeilen für dieselben drei Keys entfernen.
- `bin/h-update-sys-hestia-git` / `func/upgrade.sh` (Z. ~322): `h-add-cron-hestia-autoupdate git`-Hook entfernen.
- `web/locale/hst_scan_i18n.sh` (Z. 18–22): `h-list-sys-hestia-updates`-Scan entfernen.
- **Verify-Gate:** vor dem Entfernen der `UPGRADE_*`-Keys prüfen, ob unser *echter* Update-Pfad (`bin/h-update-hestia`) sie liest. Falls ja → behalten/umwidmen statt löschen.

### C2 — Löschen (nach De-Wiring)
- 7 Commands: `h-update-sys-hestia`, `-all`, `-git`, `h-list-sys-hestia-updates`, `h-list-sys-hestia-autoupdate`, `h-add-cron-hestia-autoupdate`, `h-delete-cron-hestia-autoupdate`.
- 7 zugehörige `v-*`-Symlinks (Policy: keine Orphans).
- Panel: `web/list/updates/`, `web/templates/pages/list_updates.php`, `web/add/cron/autoupdate/`, `web/delete/cron/autoupdate/`, `web/update/hestia/`.

### C3 — Panel-„Updates"-Seite: bewusst NICHT neu bauen (keine Priorität)
Der Autor hat den Neubau auf `h-update-hestia` als „keine Priorität" markiert. → In #128
nur entfernen/de-wiren; **separates Folge-Issue** anlegen: „Panel: Updates-Seite auf
`h-update-hestia --check` neu bauen" (low prio).

**Kritische Dateien:** `web/templates/pages/list_services.php`, `func/syshealth.sh`, `func/helper.sh`, `func/upgrade.sh`, `web/locale/hst_scan_i18n.sh`, die 7 `bin/h-*` + `bin/v-*`, die 5 `web/`-Verzeichnisse/Templates.

---

## Issue-Housekeeping (begleitend, nicht blockierend)
- `#137`/`#138` mit den im Audit neu gefundenen Fundstellen erweitern: #137 += Shebangs in `bin/h-generate-password-hash`, `bin/h-quick-install-app` und Direktaufrufe in `bin/h-add-sys-filemanager:66,86`; #138 += `bin/h-change-sys-hestia-ssl:69` (`/run/hestia-nginx.pid` → Caddy-Reload).
- Epic `#112` (just→bash, gemerged) erledigt — Status aktualisieren/schließen.
- `#57` referenziert noch `make/configure.mk` (vor-Bash-Migration) — Body auf den Bash-Installer aktualisieren (analog dem #61-Cleanup in Teil B).
- Kosmetik (eigenes kleines Issue oder Beifang): `bind9`/`named`-Branch in `bin/h-restart-service`, `vsftpd`-Pfade in `func/upgrade.sh`.

---

## Verifikation
- **#132:** `jq empty share/manifest.json`; `bash -n func/wizard.sh`; keine deutschen nutzersichtbaren Strings mehr (`jq`-Scan wie in der Recherche). Round-trip-Simulation von `_ask_radio` mit Objekt-Optionen (Label→value-Mapping) wie bei der Gruppen-Checkliste in #134; auf Debian-12-VM Wizard interaktiv durchklicken.
- **#103:** Helper setzt `COMPONENT_*` in `/etc/hestia/install.conf` idempotent; nach Frischinstall spiegelt install.conf den tatsächlichen Komponentenstand; ein vorhandenes `h-add-sys-*` aktualisiert den passenden Key.
- **#61:** `TROUBLESHOOTING.md` vorhanden; absichtlich abgebrochener Install (z. B. fehlerhafte Stage) → klare Meldung + Log-Verweis; erneuter `h-install-hestia`-Lauf überspringt fertige `.done.*`-Stages.
- **#128:** `grep -r` zeigt keine Referenzen mehr auf die 7 Commands/Endpunkte; Panel-„Server"-Seite lädt ohne toten Updates-Link; Frischinstall legt keinen Autoupdate-Cron mehr an; `hestia update`/`h-update-hestia` weiterhin funktionsfähig.
- Je Issue eigener PR auf `dev` (CLAUDE.md-Workflow), Autor reviewt/merged.
