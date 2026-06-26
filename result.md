# Code-Review: install.sh — Interactive Install Wizard (PR #107 / Issue #106)

**Branch:** `feature/106-interactive-install-wizard`
**Commits unter Review:** `b13f7c6` (rewrite install.sh as interactive wizard) + `d18c9d4` (fix: GitHub constants, whiptail, deb13/ubuntu26)
**Geprüfte Dateien:** `install.sh` (819 Z.), `conf/manifest.json`, Konsumseite `Justfile` + `just/*`
**Status:** Reine Prüfung — es wurden **keine** Codeänderungen vorgenommen.

---

## Kriterium 1 — Architektur & Trennung der Verantwortlichkeiten → **teilweise**

- ✅ install.sh delegiert das rein Mechanische korrekt: Verzeichnisanlage und initiale `hestia.conf` liegen in `just` (`_init-hestia-structure`, `_bootstrap-hestia-env`, `just/configure:43-106`), **nicht** in install.sh. Saubere Trennung.
- ✅ `just install` prüft `install.conf` zu Beginn mit klarer, auf install.sh verweisender Meldung (`Justfile:49-55`; zusätzlich `_collect-params`, `just/configure:22-25`).
- ❌ **Funktionaler Bruch:** `Justfile:71` ruft `just "_profile-${INSTALL_PROFILE}"`, aber es existieren nur `_profile-standard` und `_profile-minimal` (`Justfile:77,80`). install.sh schreibt jedoch einen der 7 Manifest-Presets (`standard/compact/latest/singlephp/nomail/mailonly/custom`). Damit läuft **nur `standard`** durch; alle anderen brechen mit „recipe `_profile-…` not found" ab. Der Justfile-Diff hat lediglich die Variablenquelle umgestellt, das 2-Profil-Modell aber nicht mit dem neuen 7-Preset-Modell versöhnt.
- ❌ **Architekturlücke:** Die in install.conf gesammelten `COMPONENT_*`-Werte werden downstream fast nicht gelesen. `MARIADB_VER` (`Justfile:27`) und `MULTIPHP_VER` (`Justfile:29`) sind **hartkodiert**, Webmailer ist fix `roundcube` (`just/mail:65`), der gewählte **Panel-Port wird ignoriert** (`just/configure:60,232` hardcoden 8083). Nur `COMPONENT_ADDON_UTILITIES`, `COMPONENT_ADDON_COMPOSER`, `TOOLS_SELECTION` werden tatsächlich ausgewertet (`just/tools:11-17`). D.h. der Wizard erhebt Entscheidungen (Webserver, PHP-Versionen, MariaDB-Version, Webmailer, Postgres/Redis/rspamd/sieve/docker/filemanager, Port), die der Installer aktuell verwirft — selbst bei `standard`. *(Wahrscheinlich für ein Folge-Issue gedacht — das Manifest deklariert sich selbst als „Soll-Zustand, nicht heutiger Stand" — muss aber genannt werden, sonst ist der Wizard kosmetisch.)*
- ⚠️ `fn_discover_php_versions` (`install.sh:378-401`) trägt das Sury-Repo dauerhaft ein und macht `apt-get update` — eine persistente Systemmutation im „interaktiven" Skript. Für die Versionsabfrage nötig und damit vertretbar, aber eine Nebenwirkung außerhalb reiner Nutzerinteraktion.

## Kriterium 2 — Abhängigkeiten & Voraussetzungen → **erfüllt**

- ✅ `jq` wird in `fn_prerequisites` (`install.sh:104`) installiert, **vor** der ersten Manifest-Nutzung (`_fetch_release:160ff`, `fn_manifest_load:790`).
- ✅ **Kein python3** — Grep über install.sh/Justfile/just: keine Treffer.
- ✅ whiptail-Verfügbarkeit korrekt geprüft inkl. TTY/TERM-Bedingungen (`install.sh:109-114`); Bash-Fallback (`_wt_inputbox/_wt_menu/_wt_radiolist/_wt_checklist`) führt inhaltlich zum gleichen install.conf-Ergebnis (mit einer Formatierungs-Inkonsistenz, siehe Kriterium 5).

## Kriterium 3 — Manifest-Treue → **teilweise** (wichtigster Block)

- ✅ `type fixed` → immer `true`, keine Frage (`install.sh:657-660`).
- ✅ `type implicit` → Preset-Default, keine Frage (`663-666`).
- ✅ `fixed_no_prompt`: WEB_SERVER@mailonly→NGINX (`675-681`), PHP_MODE@mailonly→os_single (über `fn_component_default`, das `fixed_no_prompt` zuerst prüft, `470-481`). Beides ohne Abfrage.
- ✅ `visible_if`: ADDON_RSPAMD/ADDON_SIEVE/MAIL_WEBMAILER bei `MAIL_BLOCK_PRESENT=false` (nomail) ausgeblendet; PHP_MULTIPHP_VERSIONS nur bei `PHP_MODE==sury_multi` (`684-693`, `fn_eval_condition:484-509`). Reihenfolge stimmt, da `keys_unsorted` die Manifest-Ordnung beibehält und Abhängigkeiten dort vor den Abhängigen stehen.
- ✅ `dependent_on`: DB_PHPMYADMIN nur bei gewählter MariaDB, DB_PGADMIN nur bei PostgreSQL=true (`696-705`).
- ✅ `opens_followup`: ADDON_UTILITIES öffnet Tools-Folgeseite **im interaktiven Pfad** (`726-730`).
- ❌ **Fasttrack überspringt die Tools-Folgeseite:** Der Fasttrack-`continue` (`669-672`) greift **vor** dem `opens_followup`-Block (`726`). Damit bleibt `TOOLS_SELECTION` leer, obwohl `ADDON_UTILITIES=true` und das Manifest pro Preset Tool-Defaults vorgibt.
- ⚠️ `tools.always_installed` (htop/iftop/sysstat/iotop/mc/mtr-tiny/screen) wird **nicht** aus dem Manifest gelesen — es ist in `just/tools:10` **dupliziert hartkodiert**. Sie werden installiert (Anforderung „nie Frage, immer installiert" faktisch erfüllt), aber nicht manifestgetrieben → Drift bei Manifest-Änderungen.
- ⚠️ **jq `// empty`-Gotcha** (empirisch bestätigt): In `fn_component_default` (`476`) liefert `.default[$preset] // empty` bei boolean `false` **leeren String statt `"false"`** — denn jqs `//` behandelt auch `false` als „leer". Betrifft ADDON_SIEVE/DOCKER/FILEMANAGER (alle false) und ADDON_COMPOSER@mailonly. Funktional derzeit harmlos (Konsumenten prüfen auf `= "true"`), aber „explizit false" und „fehlt" werden ununterscheidbar → inkonsistente install.conf.

## Kriterium 4 — Dynamische Versions-Ermittlung → **teilweise / nicht erfüllt**

**PHP (`fn_discover_php_versions:378-401`):**
- ✅ Sury-Repo wird vor der Abfrage eingetragen inkl. `apt-get update` (`379-386`).
- ❌ **Die Abfrage funktioniert nicht.** Zwei Probleme, das erste empirisch bestätigt:
  1. Sury-Versionen tragen ein Epoch (`2:8.3+95…`). Die Regex `^[0-9]+\.[0-9]+` (`391`) ist am Zeilenanfang verankert und matcht `2:8.3…` nicht → Ergebnis leer.
  2. `apt-cache madison php` fragt das **Metapaket** ab und liefert i.d.R. nur **eine** Kandidatenversion, nicht die Liste 5.6–8.4.
  - → In der Praxis greift **immer** der hartkodierte Fallback (`398`). Genau das, wovor das Manifest warnt („statt feste Versionsnummern hartzukodieren"). Test:
    ```
    'php | 2:8.3+95… | …' | awk '{print $3}' | grep -oE '^[0-9]+\.[0-9]+'  →  (leer)
    ```
- ✅ `default_rule`-Anwendung ist korrekt (getestet): `standard skip_newest:1,take:3`→`8.3 8.2 8.1`; `compact skip_newest:1,take:2`→`8.3 8.2` (2.-/3.-neueste gemäß Manifest-Regel); `latest take_newest:2`→`8.4 8.3` (2 neueste). Logik in `fn_apply_default_rule:443-461` stimmt — sie operiert nur auf einer falsch ermittelten Liste.

**MariaDB (`fn_discover_mariadb_version:403-421`):**
- ✅ Laufzeit-Ermittlung via `apt-cache policy/madison mariadb-server`, Fallback `10.11`.
- ✅ Im interaktiven Pfad ersetzt `_ask_version_select` (`596-617`) `__os__` korrekt: Label via `label_template`, und der **gespeicherte Wert ist die echte Versionsnummer**, nicht der Platzhalter.
- ❌ **Im Fasttrack** wird `fn_component_default` direkt gespeichert (`669-671`) → für `singlephp`/`mailonly` landet **literal `"__os__"`** in install.conf statt der echten Version. (Derzeit maskiert, weil downstream `MARIADB_VER` ohnehin hartkodiert ist — latent aber falsch.)

## Kriterium 5 — Datenstruktur von install.conf → **teilweise**

- ✅ Jede Komponente landet als `COMPONENT_<id>`-Schlüssel (`fn_write_install_conf:758-760`), auch nie-gefragte. Plus `TOOLS_SELECTION`, `ALWAYS_INSTALLED_PACKAGES`.
- ✅ **Kein Admin-Passwort** irgendwo: install.conf enthält keins, kein interaktiver Passwort-Prompt, nichts wird an `just` durchgereicht. Generierung in `_configure-hestia:113` (`openssl rand`), Übergabe via temporärer 600-Datei. Manifest-konform.
- ⚠️ **Checklist-Format inkonsistent:** whiptail-Checklist liefert **gequotete** Tags (`"8.4" "8.3"`), der Bash-Fallback **ungequotet** (`8.4 8.3`). Geschrieben wird `COMPONENT_PHP_MULTIPHP_VERSIONS=""8.4" "8.3""` — round-trippt beim `source` zwar zufällig zu `8.4 8.3` (Quote-Konkatenation), ist aber fragil und kein „konsistentes, leicht weiterverarbeitbares" Format. Empfehlung: `whiptail --separate-output` oder Quotes vereinheitlichen.

## Kriterium 6 — Schneller Pfad über Preset-Argument → **teilweise**

- ✅ `bash install.sh <preset>` stellt weiterhin die 4 Basisfragen (`fn_ask_pre_questions:791`) und füllt Komponenten still mit Preset-Defaults (`669-672`).
- ✅ Kein Argument → voller interaktiver Pfad (Menü, `fn_ask_preset:365-371`).
- ❌ **`custom` als Argument** wird mit Fehler **abgewiesen** (`356-360`) statt — wie in Kriterium 6 erwartet — den vollen interaktiven Pfad auszulösen. (Manifest sagt „custom nicht fasttrackbar" → leichter Konflikt; sauber wäre: `custom`-Arg = Preset vorwählen + interaktiv laufen.)
- ❌ Fasttrack-Defekte: leere `TOOLS_SELECTION` (s. K3), literal `__os__` (s. K4), DB_PHPMYADMIN leer (s. K7/B4).

## Kriterium 7 — Preset `custom` allgemein → **teilweise / nicht erfüllt**

- ✅ Keine Vorbelegung außer `fixed`: radio/checkbox bekommen bei `custom` (Default `null`) keinen `ON`-Zustand; fixed-Komponenten bleiben fest `true`.
- ❌ **Implicit-Komponenten brechen custom:** PHP_MODE, MAIL_BLOCK_PRESENT, WEB_REPO_SOURCE haben `custom: null` und werden als `implicit` **nie gefragt** → `COMP_VALUES` leer. Folge: `PHP_MULTIPHP_VERSIONS` (`visible_if PHP_MODE==sury_multi`), `MAIL_WEBMAILER`, `ADDON_RSPAMD`, `ADDON_SIEVE` (`visible_if MAIL_BLOCK_PRESENT==true`) werden **alle ausgeblendet**. Der Nutzer kann bei `custom` also weder PHP-Modus/-Versionen noch den Mail-Block wählen → unvollständige Konfiguration. (Teils Manifest-Ambiguität: „implicit" + `custom:null` ist widersprüchlich.)

## Kriterium 8 — Code-Qualität & Robustheit → **teilweise**

- ✅ `set -euo pipefail` vorhanden (`25`), gezielte `|| true` an den richtigen Stellen.
- ✅ JSON-Syntax wird validiert (`fn_manifest_load:196-198`).
- ⚠️ **Keine Schema-Validierung:** Fehlt ein erwarteter Key, liefert `jq … // empty` stillschweigend `""` (Exit 0) — keine verständliche Fehlermeldung, sondern leerer Wert. Kriterium 8 hier nur teilweise erfüllt.
- ✅ `--dev` (`116-118`) und `--profile=` (`55`) funktionieren und widersprechen sich nicht (`--dev standard` setzt beides). ⚠️ Namens-Überladung: `--profile` meint jetzt „Manifest-Preset", nicht mehr standard/minimal.

---

## Priorisierte Zusammenfassung

### A — Funktionale Fehler (Installation bricht / Wahl wirkungslos)

- **A1 — `_profile-${INSTALL_PROFILE}`-Dispatch** (`Justfile:71` vs. nur `77/80`): 6 von 7 Presets brechen ab.
  *Fix:* Nicht nach Preset-Namen dispatchen, sondern nach `COMPONENT_MAIL_BLOCK_PRESENT` (Mail an/aus), `mailonly` separat behandeln; alternativ `_profile-*`-Rezepte für alle Presets ergänzen.
- **A2 — PHP-Versionsermittlung defekt** (`install.sh:388-399`): Epoch-Regex + Metapaket → immer Hardcode-Fallback.
  *Fix:* Pakete enumerieren, z.B. `apt-cache search --names-only '^php[0-9]+\.[0-9]+-common$'` bzw. `apt-cache pkgnames | grep -oE '^php[0-9]+\.[0-9]+'`; beim madison-Weg Epoch mit **nicht-verankertem** `grep -oE '[0-9]+\.[0-9]+'` strippen; dann `sort -Vr | uniq`.
- **A3 — Fasttrack `__os__` literal** (`install.sh:669-671`): MariaDB-Platzhalter statt echter Version.
  *Fix:* `__os__→OS_MARIADB_VERSION`-Übersetzung in einen Helper ziehen, den Fasttrack **und** interaktiv nutzen.
- **A4 — install.conf wird downstream kaum konsumiert** (Webserver, PHP-Versionen, MariaDB-Version, Webmailer, Panel-Port, die meisten Addons): hartkodierte `MARIADB_VER`/`MULTIPHP_VER` in `Justfile`, fixer Webmailer, ignorierter Port.
  *Fix (vermutlich Folge-Issue):* `COMPONENT_*` in `just/web|db|mail|configure` einlesen statt hartkodierter Werte. Mindestens jetzt dokumentieren, dass der Wizard-Output noch nicht vollständig wirkt.
- **A5 — Fasttrack überspringt Tools-Folgeseite** (`install.sh:669-672` vor `726`): `TOOLS_SELECTION` bleibt leer trotz `ADDON_UTILITIES=true`.
  *Fix:* `opens_followup`/Tools-Default auch im Fasttrack-Zweig setzen (z.B. `tools.selection.default[preset]` direkt übernehmen).

### B — Manifest-Abweichungen (falsches, aber nicht hart abbrechendes Verhalten)

- **B1 — `custom` + implicit-Komponenten** (`install.sh:663-666` + manifest `custom:null`): PHP-Modus/-Versionen und Mail-Block bei `custom` nicht wählbar → unvollständige Konfiguration.
  *Fix:* Für `custom` PHP_MODE/MAIL_BLOCK_PRESENT/WEB_REPO_SOURCE explizit abfragen (echte Frage statt implicit) oder definierte Defaults setzen; Manifest-Widerspruch auflösen.
- **B2 — `custom`-Argument abgewiesen** statt interaktiv (`install.sh:356-360`): Abweichung von Kriterium 6.
  *Fix:* `custom`-Arg → INSTALL_PROFILE=custom + voller interaktiver Pfad (nicht Fasttrack).
- **B3 — `tools.always_installed` nicht manifestgetrieben** (Hardcode in `just/tools:10`).
  *Fix:* Liste aus dem Manifest in install.conf schreiben und in `just/tools` daraus lesen.
- **B4 — DB_PHPMYADMIN-Default inkonsistent** zwischen interaktiv (`install.sh:711-716` → „true") und Fasttrack (leer, da kein Manifest-Default). Manifest definiert für DB_PHPMYADMIN/DB_PGADMIN gar keinen Default.
  *Fix:* Default im Manifest ergänzen oder Fallback in beiden Pfaden identisch anwenden.

### C — Stil / Robustheit

- **C1 — jq `// empty`-Gotcha** mit boolean `false` (`install.sh:476`): „false" wird zu leerem String. *Fix:* `.default[$preset]` per `has`/`if … == null` prüfen statt `//`.
- **C2 — Checklist-Quoting inkonsistent** zwischen whiptail und Bash-Fallback (`install.sh:284-321`, `593`). *Fix:* `whiptail --separate-output` oder Quotes normalisieren.
- **C3 — Keine Schema-Validierung des Manifests** (nur JSON-Syntax, `fn_manifest_load:196-198`): fehlende Keys → stilles `""`. *Fix:* Pflichtfelder prüfen und verständlich abbrechen.
- **C4 — Komponenten-Reihenfolge implizit abhängig** von Manifest-Ordnung (`keys_unsorted`), da `visible_if`/`dependent_on` nur funktionieren, wenn die referenzierte Komponente vorher ausgewertet wurde. Aktuell korrekt, aber fragil bei Umsortierung. *Fix:* optional dokumentieren oder topologisch sortieren.
- **C5 — `--profile`-Namensüberladung** (`install.sh:55`): meint jetzt Manifest-Preset, nicht mehr standard/minimal. *Fix:* nur Doku/Klarstellung.

---

## Empfehlung

Bevor PR #107 gemerged wird, sollten mindestens **A1, A2, A3, A5** behoben werden (sonst funktioniert end-to-end nur Preset `standard`, und auch dort nur mit Fallback-PHP-Versionen). **A4** ist die größte Architekturfrage: ohne Konsum der `COMPONENT_*`-Werte ist der Wizard weitgehend wirkungslos — falls bewusst als Folge-Issue geplant, klar so dokumentieren. **B1/B2** betreffen die Korrektheit des `custom`-Pfads. Die C-Punkte sind Härtung.

Es wurden noch **keine** Änderungen am Code vorgenommen — Rückmeldung erbeten, welche Punkte angegangen werden sollen.
