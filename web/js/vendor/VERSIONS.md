# Vendored artifacts - Alpine.js project (alpinejs/alpine monorepo)

Branch `upstream/alpinejs`: READ ONLY snapshot of the published build artifacts,
laid out in HestiaRE target structure for direct merge/cherry-pick into dev.
Update via src/update-web-vendor.sh (--fetch alpinejs[@version]).

| File | Package | Version | Source | sha256 |
|---|---|---|---|---|
| alpinejs.min.js | alpinejs | 3.16.1 | https://registry.npmjs.org/alpinejs/-/alpinejs-3.16.1.tgz (dist/cdn.min.js) | 04656d770039b55ac7a37aeecb92191de2c7775f61f2d0183331cc16c13f3f1e |
| alpinejs-collapse.min.js | @alpinejs/collapse | 3.16.1 | https://registry.npmjs.org/@alpinejs/collapse/-/collapse-3.16.1.tgz (dist/cdn.min.js) | c7661d4e2cf0465e3cd693190debb5f592ac72dcc4cfe650581273767558b27b |

License: MIT (LICENSE-alpinejs.md, from https://github.com/alpinejs/alpine v3.16.1).
Note: the GitHub repo commits no dist files and attaches no release assets -
the npm registry tarball is the project's official publish artifact.
