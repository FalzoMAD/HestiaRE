# Vendored artifacts — Font Awesome Free (FortAwesome/Font-Awesome)

Branch `upstream/fontawesome`: READ ONLY snapshot of the official release
artifact contents, laid out in HestiaRE target structure for direct
merge/cherry-pick into dev.
Update via src/update-web-vendor.sh (--fetch fontawesome[@version]).

Release artifact: fontawesome-free-7.3.0-web.zip
Source: https://github.com/FortAwesome/Font-Awesome/releases/download/7.3.0/fontawesome-free-7.3.0-web.zip
Artifact sha256: 791f5f4dbbcf7ad16e3727e54969df2691b53a9b8da127f19fdace190471d446

| File | Version | Modification | sha256 (as vendored) |
|---|---|---|---|
| fontawesome.css | 7.3.0 | none (byte-identical to css/fontawesome.css) | 74ea77cd04ec7de48c598073a59297566b77b9fdf8b90200774ca1730b6c8d9a |
| solid.css | 7.3.0 | ../webfonts/ -> /webfonts/ | 6800766a322bcc2032dea527aeb2be0967283076cffd5d3a741462d7b3fbc01c |
| fa-solid-900.woff2 | 7.3.0 | none (byte-identical to webfonts/fa-solid-900.woff2) | 47b1a018f969189c59b87e9d23f9304db54dc9bdcecf00b216c23515f86826e4 |

License: CC BY 4.0 (icons) / SIL OFL 1.1 (fonts) / MIT (CSS code) — LICENSE.txt
from the same artifact.
Scope: Solid style only. The panel uses .fas exclusively (grep-verified);
regular/brands CSS and webfonts are intentionally not vendored (YAGNI).
