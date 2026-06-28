# Plan: `data/` auflösen — Gesamtblick (#133 als erster Schritt)

> Ausgegliedert aus `wizard-cleanup-plan.md`. Bewusst **gesondert** betrachtet, weil ein
> echter Move groß ist und nur im Gesamtblick auf *alle* `data/`-Inhalte sauber entschieden
> werden sollte — nicht stückweise unter Zeitdruck im Cleanup-Cluster.

## Context / Ziel

Mittelfristiges Ziel: das Verzeichnis `/usr/local/hestia/data/` **ganz entfernen**.
Instanz-/Laufzeitzustand soll nach `/etc/hestia/` (teils flacher) wandern — Fortsetzung von
#129 (conf → `/etc/hestia/conf`). Anders als #129 hier **kein Symlink-Bridge**, sondern ein
**echter Referenz-Move** (Pfade umstellen + Inhalt verschieben), damit `data/` am Ende
wirklich verschwindet. Trade-off bewusst akzeptiert: mehr berührte Dateien, dafür kein
Alt-Pfad-Ballast.

Voraussetzung für eine Gesamt-Entscheidung: pro `data/`-Unterbaum klären, **wohin** er gehört
(oder ob er bleibt) und **wie** umgestellt wird — denn die Inhalte sind sehr unterschiedlich
(Config vs. Backup-Format vs. Named Pipes vs. Templates).

---

## Bestandsaufnahme `data/`-Inhalte

### §5a — entschieden, bereit für echten Move
| Quelle | Ziel | Vorkommen (gemessen) | Charakter |
|---|---|---|---|
| `data/firewall` | `/etc/hestia/firewall` | **88** (77× `$HESTIA/data/firewall`, **14× relativ `../../../data/firewall/ipset`**, 1× `web/add/web/index.php`) | Rules/Chains/Banlist/ipset-Config |
| `data/ips` | `/etc/hestia/ips` | **64** (alle `$HESTIA/data/ips`) | IP-Einträge |
| `hooks` (`/etc/hestiacp/hooks`) | `/etc/hestia/hooks` | — | Lifecycle-Hooks; **liegt faktisch schon** unter `/etc/hestia/hooks` (`h-add-letsencrypt-domain`). Nur `seed_hestia_etc` muss das Verzeichnis anlegen. |

→ **Das ist der Scope von Issue #133** (erster konkreter Move). Details unten.

### §5b — noch zu entscheiden (Risiko, eigener Durchgang je Unterbaum)
| Quelle | Frage |
|---|---|
| `data/users` | **Backup-Format-Kompatibilität** (HestiaCP bidirektional, permanent!) — Move nur, wenn Backup-Restore unberührt bleibt. Höchstes Risiko. |
| `data/queue` | **Named Pipes** — bleibt vermutlich; verschieben kann FIFO-/Reader-Logik brechen. Default: belassen, begründen. |
| `data/packages` | Hosting-Pakete (Plan-Definitionen) — Config-artig, Move wahrscheinlich ok; Referenzen prüfen. |
| `data/templates` | Web/Mail/DNS-Templates — viele Referenzen (`WEBTPL`/`MAILTPL`/`DNSTPL` in `func/main.sh`); Move ok, aber breit. |
| `data/sessions` u. a. | Rest inventarisieren (`ls data/`), je Unterbaum zuordnen. |

**Offene Grundsatzfrage:** Wenn `data/users`/`data/queue` bleiben *müssen*, ist „data/ ganz
weg" evtl. nicht 100% erreichbar → dann Ziel als „data/ minimal halten" reformulieren.
Diese Entscheidung gehört in den Gesamtblick, nicht in #133.

---

## #133 — erster Schritt: data/firewall + data/ips → /etc/hestia (ECHTER Move)

**Branch:** `feature/133-paths-etc-hestia`

**Vorgehen:**
- Zielpfade als **Literale** `/etc/hestia/firewall` und `/etc/hestia/ips` (konsistent mit dem
  bereits literalen `/etc/hestia/hooks`). Optional Komfort-Var `HESTIA_CONF="/etc/hestia"`
  in `func/main.sh` — web/PHP + relative Refs brauchen aber ohnehin Literale.
- Die 77 + 64 `$HESTIA/data/...`-Vorkommen mechanisch umstellen (sed je Datei + Review).
- **Sorgfalts-Teil (eigentlicher Refactor, kein sed):** die **14 relativen**
  `*_hstobject='../../../data/firewall/ipset'` in 10 Firewall-Commands (h-add/-delete/-change/
  -move/-list/-suspend/-unsuspend-firewall-rule, h-add/-delete/-update-firewall-ipset). Zuerst
  verstehen, wie `*_hstobject` aufgelöst/konsumiert wird (HestiaCP-Objekt-Mechanik, relativ zu
  welchem cwd/Basis), dann korrekt auf absolut umstellen. **Hier liegt das Risiko.**
- `web/add/web/index.php`: die 1 Referenz mitziehen.
- `seed_hestia_etc` (`func/helper.sh`): Zielverzeichnisse unter `/etc/hestia` anlegen; bei
  Upgrade vorhandenen Inhalt **einmalig `mv`**, **kein** Symlink zurücklassen.
- `data/firewall` + `data/ips` aus dem Laufzeit-/Asset-Baum entfernen; `PATHS.md` §5a auf
  DONE, `CODEMAP.json` nachziehen.

**Kritische Dateien:** ~10 `bin/h-*firewall*` (relative `*_hstobject`-Refs — Risiko),
weitere ~25 `bin/`+`func/` mit `$HESTIA/data/{firewall,ips}`, `web/add/web/index.php`,
`func/helper.sh` (`seed_hestia_etc`-Migration), `PATHS.md`, `CODEMAP.json`.

**Verifikation:**
- `grep -r` zeigt **keine** `data/firewall`/`data/ips`-Referenzen mehr (auch keine relativen).
- `bash -n` aller geänderten Skripte.
- Frischinstall auf VM → `/etc/hestia/{firewall,ips,hooks}` existieren und werden direkt
  beschrieben (kein `$HESTIA/data/{firewall,ips}` mehr).
- `h-update-firewall`, `h-add-firewall-ipset` und eine schreibende Rule-Operation
  (`h-change-sys-port`, `h-add/-delete-firewall-rule`) laufen fehlerfrei; ipset-`*_hstobject`
  löst korrekt auf.
- Upgrade-Pfad: bestehende `data/{firewall,ips}`-Inhalte wurden nach `/etc/hestia` verschoben.

---

## Nächste Schritte (für die Gesamt-Entscheidung)
1. `ls /usr/local/hestia/data/` auf einem Realsystem → vollständige Unterbaum-Liste.
2. Je Unterbaum: Referenzen zählen, Schreibmechanik (sed -i / Objekt-Refs / Pipes), Backup-
   Format-Berührung → Ziel + Methode festlegen.
3. Entscheiden, ob „data/ vollständig weg" realistisch ist oder „data/ minimal" das Ziel wird.
4. #133 (firewall/ips) als ersten Move umsetzen; danach §5b-Unterbäume einzeln.
