# Vendored artifact — Bootstrap CSS (twbs/bootstrap)

Branch `upstream/bootstrap-css`: READ ONLY snapshot of the published dist CSS,
laid out in HestiaRE target structure for direct merge/cherry-pick into dev.
Update via share/upstream/update-web-vendor.sh (--fetch bootstrap-css[@version]).

Source: https://registry.npmjs.org/bootstrap/-/bootstrap-5.3.8.tgz (dist/css/bootstrap.min.css)

| File | Version | Modification | sha256 (as vendored) |
|---|---|---|---|
| bootstrap.min.css | 5.3.8 | none (byte-identical to the npm dist CSS) | d85327d99c7a3ee1f9b5d0500d1370acea3ad2db39c163c2f51f232baedbdede |

License: MIT (LICENSE-bootstrap.txt). Only the CSS is shipped — the Bootstrap JS
bundle is intentionally NOT vendored (the FM replaces it with vanilla JS + a shim).
