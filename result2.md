# Fix-Bericht: install.sh Interactive Wizard (PR #107 / Issue #106)

**Branch der Fixes:** `feature/106-interactive-install-wizard`
**Fix-Commit:** `869227a` — `[#106] fix: manifest-faithful wizard (PHP discovery, __os__, fasttrack, custom, jq false, schema)`
**Geänderte Dateien:** `install.sh` (+205/−43), `conf/manifest.json`
**PR-Kommentar:** https://git.hestiare.com/Admin/HestiaRE/pulls/107#issuecomment-401

Dieser Bericht dokumentiert die Umsetzung der zehn Punkte aus der vorangegangenen Code-Review (siehe `result.md`). Leitprinzip: **install.sh wird in sich konsistent und manifest-treu gemacht — nicht rückwärts an die heute noch unfertigen just-Module angepasst.**

---

## Umgesetzte Fixes

### 1 — PHP-Versionsermittlung (`fn_discover_php_versions`)
**Vorher:** `apt-cache madison php` (nur das Metapaket → eine Kandidatenversion) + am Zeilenanfang verankerte Regex `^[0-9]+\.[0-9]+`, die an Surys Epoch-Präfix (`2:8.3`) scheitert → in der Praxis immer leer → stiller Hardcode-Fallback.
**Nachher:** Enumeriert die tatsächlich vorhandenen Pakete via `apt-cache pkgnames php`, filtert auf `^php[0-9]+\.[0-9]+-(common|fpm)$` und extrahiert die Version **unverankert** aus dem Paketnamen, dann `sort -Vr | uniq`.
```bash
apt-cache pkgnames php 2>/dev/null \
  | grep -E '^php[0-9]+\.[0-9]+-(common|fpm)$' \
  | grep -oE '[0-9]+\.[0-9]+' \
  | sort -Vr | uniq | tr '\n' ' ' | sed 's/ $//'
```
**Verifiziert:** Fixture `php8.3-fpm/php8.3-common/php8.2-common/php7.4-common/php8.4-fpm/php5.6-common` → `8.4 8.3 8.2 7.4 5.6`. Live-`apt-cache` im Sandbox liefert ebenfalls eine Version (`8.4`).

### 2 — `__os__`-Platzhalter im Fasttrack (`fn_resolve_version_value`)
**Vorher:** Fasttrack speicherte bei `singlephp`/`mailonly` buchstäblich `__os__` in install.conf statt der echten OS-MariaDB-Version (interaktiver Pfad löste korrekt auf).
**Nachher:** Auflösung in eine gemeinsame Hilfsfunktion gezogen, die in **beiden** Pfaden aufgerufen wird:
```bash
fn_resolve_version_value() {
    local val="$1"
    if [ "$val" = "__os__" ]; then
        [ -n "$OS_MARIADB_VERSION" ] || fn_discover_mariadb_version
        printf '%s' "$OS_MARIADB_VERSION"
    else printf '%s' "$val"; fi
}
```
**Verifiziert:** Fasttrack `mailonly`/`singlephp` → `DB_MARIADB_VERSION=11.11` (kein `__os__` mehr).

### 3 — Fasttrack-Defaults (`fn_fasttrack_value`)
**Vorher:** Fasttrack dumpte nur `fn_component_default` pro Komponente; Tools-Folgeseite und PHP-Vorauswahl wurden komplett übersprungen → `TOOLS_SELECTION` leer, `PHP_MULTIPHP_VERSIONS` leer.
**Nachher:** Neue `fn_fasttrack_value` spiegelt die interaktive Default-Logik ohne Prompt: respektiert `visible_if`/`dependent_on`, wendet `default_rule` auf die PHP-Liste an, löst `__os__` auf und befüllt `TOOLS_SELECTION` aus `tools.selection.default[preset]`, sobald `ADDON_UTILITIES` aktiv ist.
**Verifiziert (Fasttrack-Simulation):**
| Preset | PHP-Versionen | DB_MARIADB | TOOLS_SELECTION |
|--------|---------------|-----------|-----------------|
| standard | `8.3 8.2 8.1` | `11.4` | `rsync net-tools vnstat parted telnet` |
| singlephp | (leer, os_single) | `11.11` | befüllt |
| mailonly | (leer) | `11.11` | befüllt |
| nomail | `8.3 8.2 8.1` | `11.4` | befüllt |

### 4 — `custom` + implicit-Komponenten
**Vorher:** `PHP_MODE`, `MAIL_BLOCK_PRESENT`, `WEB_REPO_SOURCE` sind `implicit` mit `custom: null` → bei `custom` unsichtbar und unbelegt → alle davon abhängigen Fragen (PHP-Versionen, Webmailer, Mail-Addons) konnten nie sichtbar werden.
**Nachher:** Bei `custom` werden diese drei als echte Fragen ohne Vorbelegung gestellt. Das Manifest erhielt dafür `question` (alle drei) und `options` (`WEB_REPO_SOURCE`: os_package/upstream_repo; `MAIL_BLOCK_PRESENT`: true/false; `PHP_MODE` hatte options bereits). `fixed`-Komponenten bleiben unberührt fest.
```bash
if [ "$type" = "implicit" ]; then
    idefault=$(fn_component_default "$id" "$INSTALL_PROFILE")
    if [ "$INSTALL_PROFILE" = "custom" ] && [ -z "$idefault" ] \
       && [ "$(mq --arg id "$id" '.components[$id] | has("options") | tostring')" = "true" ]; then
        _ask_radio "$id" "$(mq --arg id "$id" '.components[$id].question // $id')" ""
    else
        COMP_VALUES["$id"]="$idefault"
    fi
    continue
fi
```
**Verifiziert:** Für `custom` werden alle drei als „ask=YES" erkannt; checkbox/radio-Komponenten liefern leeren Default (keine Vorbelegung).

### 5 — `custom` als Argument
**Vorher:** `bash install.sh custom` brach mit Fehler ab.
**Nachher:** Setzt `INSTALL_PROFILE=custom`, leert `FASTTRACK_PRESET` und läuft den vollen interaktiven Pfad (ohne Preset-Menü, da custom bereits feststeht).

### 6 — Manifest-Defaults für `DB_PHPMYADMIN` / `DB_PGADMIN`
**Vorher:** Kein `default`-Feld → interaktiver Pfad nahm hartkodiert `true` an, Fasttrack las leer → Divergenz.
**Nachher:** Beide Komponenten erhielten explizite Per-Preset-Defaults (`DB_PHPMYADMIN`: alle Hosting-Presets `true`, `mailonly` `false`; `DB_PGADMIN`: überall `false`, da PostgreSQL standardmäßig aus). Der interaktiv-only Hardcode-Fallback in install.sh wurde entfernt → beide Pfade identisch.

### 7 — jq `// empty` verschluckte `false`
**Vorher:** `fn_component_default` nutzte `.default[$preset] // empty`; jq behandelt `false` wie „leer" → `ADDON_SIEVE/DOCKER/FILEMANAGER` etc. lieferten `""` statt `"false"`.
**Nachher:** Explizite Unterscheidung via `has()` + `!= null`:
```jq
elif ($c.default | type) == "object" then
  (if ($c.default | has($preset)) and ($c.default[$preset] != null)
   then $c.default[$preset] | tostring else "" end)
```
`fn_pre_discovery` läuft jetzt ebenfalls über `fn_component_default` (statt eigener `// empty`-Abfragen).
**Verifiziert:** `ADDON_SIEVE/standard = false`, `ADDON_COMPOSER/mailonly = false`, `DB_POSTGRESQL/standard = false` (scalar) — keine leeren Werte mehr.

### 8 — Einheitliches Checklisten-Format (`fn_normalize_list`)
**Vorher:** whiptail lieferte gequotete Tags (`"8.4" "8.3"`), der Bash-Fallback ungequotete (`8.4 8.3`) → zwei nur zufällig kompatible Formate in install.conf.
**Nachher:** `fn_normalize_list` vereinheitlicht beide Quellen zu **unquotiert, leerzeichengetrennt, dedupliziert, Reihenfolge erhalten** — verlässlich per Word-Split rücklesbar. Angewendet auf `PHP_MULTIPHP_VERSIONS` und `TOOLS_SELECTION` in interaktivem und Fasttrack-Pfad.
**Verifiziert:** `"8.4" "8.3" "8.2"` → `8.4 8.3 8.2`; `8.4 8.3 8.2` → `8.4 8.3 8.2`; Dupes/Leerzeichen bereinigt.

> **Format-Entscheidung:** Im Review-Prompt war „kommagetrennt" als *Beispiel* genannt. Gewählt wurde **leerzeichengetrennt**, weil das alle harten Anforderungen erfüllt (identisch in beiden Pfaden, keine Per-Wert-Quotes, verlässlich reparsebar), der Array-Schreibweise des Manifests entspricht und den einzigen heute funktionierenden Konsumenten (`just/tools`, `install $TOOLS_SELECTION` per Word-Split) nicht bricht. Bei Bedarf trivial auf Komma umstellbar.

### 9 — Manifest-Schema-Validierung (`fn_manifest_load`)
**Vorher:** Nur JSON-Syntax-Check; fehlende Felder → stille leere Werte.
**Nachher:** Nach dem Syntax-Check werden Vorhandensein und Typ der Top-Level-Felder `presets`, `components`, `tools` (object) sowie `pre_questions`, `always_installed_packages` (array) geprüft; bei Fehlern Abbruch mit klarer, menschenlesbarer Meldung.
**Verifiziert:** Valides Manifest → keine Meldung; defektes Manifest → `presets: falscher Typ (erwartet object); tools: fehlt; …`.

---

## Abgrenzung (bewusst NICHT Teil dieser Korrektur)

Die **tatsächliche Auswertung der `COMPONENT_*`-Werte durch die just-Module** — `just/web`, `just/db`, `just/mail`, der `_profile-${INSTALL_PROFILE}`-Dispatch im `Justfile` (heute nur `_profile-standard`/`_profile-minimal`), der ignorierte Panel-Port, die hartkodierten `MARIADB_VER`/`MULTIPHP_VER` — bleibt ein **eigenständiger, späterer Arbeitsschritt**. Dieser PR stellt nur sicher, dass install.sh eine korrekte, vollständige und sauber strukturierte install.conf erzeugt, die ein späterer just-Refactor verlässlich konsumieren kann.

> Das entspricht der ursprünglichen Review-Empfehlung A1/A4 (`result.md`): A1 ist kein „install.sh an Justfile anpassen"-Fix, sondern der Hinweis, dass die install.conf-Schnittstelle sauber sein muss; die Dispatch-Logik selbst gehört in den späteren Refactor.

---

## Verifikationsmethodik

- `bash -n install.sh` sauber; `jq empty conf/manifest.json` valide.
- Funktionen via Strip-`main`-Source einzeln getestet: `fn_component_default`, `fn_normalize_list`, `fn_resolve_version_value`, `fn_apply_default_rule`, `fn_tools_default_for_preset`.
- Vollständige Fasttrack-Simulation (Komponenten-Reihenfolge wie in `fn_ask_components`) für `standard`/`singlephp`/`mailonly`/`nomail`.
- `custom`-Entscheidungslogik und interaktive Default-Parität geprüft.

**Nicht testbar in der Sandbox:** Die whiptail-Dialoge selbst (kein TTY) — verifiziert ist die zugrunde liegende Werteableitung, nicht das visuelle Rendering. Ebenso die echte Sury-Live-Abfrage (kein Sury-Repo/Root/Netz) — verifiziert ist die Parsing-Pipeline gegen repräsentative Paketnamen-Ausgabe.
