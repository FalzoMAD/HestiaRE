# Vendored front-end assets (File Manager)

These files are third-party libraries served locally by the File Manager (no CDN).

- **css/bootstrap.min.css** — Bootstrap v5.2.3, MIT License.
  https://getbootstrap.com/ — Copyright The Bootstrap Authors.
- **js/prism.js** — PrismJS v1.29.0, MIT License. A combined build (core +
  the languages the FM highlights + the line-numbers plugin), assembled via the
  jsDelivr `combine` endpoint. https://prismjs.com/ — Copyright Lea Verou.
- **css/prism-light.css** (theme "prism"), **css/prism-dark.css** (theme
  "tomorrow"), **css/prism-linenumbers.css** — PrismJS v1.29.0, MIT License.

HestiaRE-authored assets (not third-party): `js/fm-editor.js`, `css/fm-editor.css`,
`css/fm.css`.

FontAwesome and (where used) AlpineJS are NOT duplicated here — the FM references
the panel's own copies by absolute path (same origin), see `web/css/vendor/`.
