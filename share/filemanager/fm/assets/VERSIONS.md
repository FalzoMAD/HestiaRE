# Vendored artifact — PrismJS (PrismJS/prism), combined build

Branch `upstream/prismjs`: READ ONLY snapshot, laid out in HestiaRE target structure.
Update via share/upstream/update-web-vendor.sh (--fetch prismjs[@version]).

prism.js is core + these languages + the line-numbers plugin, in this order,
concatenated by jsDelivr /combine (sourceMappingURL comment stripped):
core markup css clike javascript markup-templating php python c cpp rust yaml batch go markdown handlebars csharp powershell apacheconf json bash sql ini nginx docker perl ruby java typescript line-numbers
Themes: prism.min.css -> prism-light.css, prism-tomorrow.min.css -> prism-dark.css,
line-numbers plugin css -> prism-linenumbers.css (all byte-identical to upstream).

prism.js sha256 (as vendored): 2ef73c7de0f13c3f73bb3b470a2e73825f2f228fa1fa445fc135fb5e99265eb8

License: MIT (LICENSE-prism.txt). No publisher hash exists for a combined build;
the combine is deterministic for pinned component versions.
