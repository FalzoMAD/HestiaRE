# TinyFileManager — attribution

`index.php` is a **maintained fork** of TinyFileManager.

- Upstream: https://github.com/prasathmani/tinyfilemanager
- Baseline version: **2.6**
- License: **GPL-3.0** (upstream ships the full GNU GPL v3 text; HestiaRE is GPL-3.0
  too, so the terms are the repository's own `LICENSE`).
- Copyright: Prasath Mani, CCP Programmers, and TinyFileManager contributors.

The pristine 2.6 baseline is kept on the read-only `upstream/tinyfilemanager` branch
(file at the same path); `git diff upstream/tinyfilemanager..dev -- share/filemanager/fm/index.php`
shows HestiaRE's integration + diet patches (#218/#419). It is a fork, not a
byte-for-byte vendored copy, so no upstream hash is asserted for `index.php`.

The vendored front-end libraries it loads (Bootstrap-CSS, PrismJS) and their licenses
are documented in `assets/LICENSE-vendored.md`.
