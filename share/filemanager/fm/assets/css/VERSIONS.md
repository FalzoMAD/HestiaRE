# Vendored artifact — Bootstrap CSS (twbs/bootstrap)

Branch `upstream/bootstrap-css`: READ ONLY snapshot of the published dist CSS,
laid out in HestiaRE target structure for direct merge/cherry-pick into dev.
Update via share/upstream/update-web-vendor.sh (--fetch bootstrap-css[@version]).

Source: https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css

| File | Version | Modification | sha256 (as vendored) |
|---|---|---|---|
| bootstrap.min.css | 5.2.3 | none (byte-identical to the npm dist CSS) | c0bcf7898fdc3b87babca678cd19a8e3ef570e931c80a3afbffcc453738c951a |

License: MIT. Only the CSS is shipped — the Bootstrap JS bundle is intentionally
NOT vendored (the FM replaces it with vanilla JS + a shim).

NOTE: initial pre-fill from the shipped artifact; LICENSE-bootstrap.txt + publisher
hash are added when refreshed on the sync host (--fetch bootstrap-css@5.2.3 --push).
