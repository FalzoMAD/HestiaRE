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
- **Layer A** (ban -> 403, nginx-only/both) - our own dependency-free Lua bouncer
  (`lua/hestia_bouncer.lua`, ~70 lines, raw cosocket to the local LAPI, no vendored
  libs), on the OS `libnginx-mod-http-lua`. Per-domain on/off. Init glue:
  `nginx/crowdsec_init.conf` (http block); the apply helper writes the key/config to
  `/etc/crowdsec/bouncers/hestia-nginx.lua` after `cscli bouncers add`.
- **Layer B** (rate-limit 429 + bot policy, all models) - native nginx `limit_req` /
  apache `mod_evasive`/`mod_qos`. Per-domain. Needs no CrowdSec.

## Files

- `collections.list` - curated collections the apply helper installs via `cscli`.
- `acquis.d/hestia-nginx.yaml` - nginx web-log acquisition source.
- `lua/hestia_bouncer.lua` - own dep-free Layer-A bouncer (LuaJIT).
- `nginx/crowdsec_init.conf` - http-block init glue that loads the bouncer.

The per-vhost fragment (Layer-A `access_by_lua` + Layer-B `limit_req`/bot policy) is
rendered per domain from the `web.conf` flags, not stored statically here.
