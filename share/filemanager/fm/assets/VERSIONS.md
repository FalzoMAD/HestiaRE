# Vendored artifact — PrismJS (PrismJS/prism), combined build

Branch `upstream/prismjs`: READ ONLY snapshot, laid out in HestiaRE target structure.
Update via share/upstream/update-web-vendor.sh (--fetch prismjs[@version]).

prism.js is core + the FM's languages + the line-numbers plugin, concatenated by
jsDelivr /combine (sourceMappingURL comment stripped). Component list + exact
combine URL: see share/upstream/update-web-vendor.sh (fetch_prismjs) and VENDORED.json.
Themes: prism.min.css -> prism-light.css, prism-tomorrow.min.css -> prism-dark.css,
line-numbers plugin css -> prism-linenumbers.css (byte-identical to upstream).

prism.js sha256 (as vendored): b4e93d86fad989e9a2417fa1590c0b86e5a5d78535e47a03771838cedf3160dc

License: MIT. NOTE: initial pre-fill from the shipped artifacts; LICENSE-prism.txt is
added when refreshed on the sync host (--fetch prismjs@1.29.0 --push).
