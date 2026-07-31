# share/crowdsec

Source assets for the CrowdSec integration (#186), applied at install/reconfigure
time by the CrowdSec apply helper. Nothing here is live config; the helper renders
and installs these into `/etc/crowdsec/` and the webserver.

CrowdSec is an **nginx-only** addon (offered for the `nginx-only` and `both` web
models). `apache-only` never runs CrowdSec; it gets only the native Layer-B
rate-limit. See `crowdsec-186-plan.md` on the `docs` branch for the full design.

## Layers

- **Detection** - `collections.list` + `acquis.d/` point the engine at the nginx web
  logs so scenarios fire. This is the always-on half; enforcement is separate.
- **Layer A** (ban -> 403, nginx-only/both) - a vendored Lua bouncer (see
  `VENDORED.json`); runs on the OS `libnginx-mod-http-lua`. Per-domain on/off.
- **Layer B** (rate-limit 429 + bot policy, all models) - native nginx `limit_req` /
  apache `mod_evasive`/`mod_qos`. Per-domain. Needs no CrowdSec.

## Files

- `collections.list` - curated collections the apply helper installs via `cscli`.
- `acquis.d/hestia-nginx.yaml` - nginx web-log acquisition source.

Vendored Lua bouncer assets and the per-vhost fragment/config templates land here as
Layers A and B are built.
