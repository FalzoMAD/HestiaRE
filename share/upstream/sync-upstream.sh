#!/bin/bash
# sync-upstream.sh – update upstream/* snapshots and show changes
# Run as: falzo user on hestiare host
set -euo pipefail

HESTIACP_DIR="$HOME/hestiacp"
HESTIARE_DIR="$HOME/hestiare"
PHPQUOTESHELLARG_DIR="$HOME/phpquoteshellarg"

# ════════════════════════════════════════════════════════════════════════════
# PART 1 — HestiaCP (full mirror, branch-based, frequent changes expected)
# ════════════════════════════════════════════════════════════════════════════

# ── 1.1 Pull hestiacp mirror ─────────────────────────────────────────────────
echo "==> Updating hestiacp mirror..."
cd "$HESTIACP_DIR"
BEFORE=$(git rev-parse HEAD)
git pull
AFTER=$(git rev-parse HEAD)

# ── 1.2 Update upstream/hestiacp snapshot ────────────────────────────────────
echo "==> Updating upstream/hestiacp snapshot..."
cd "$HESTIARE_DIR"
git checkout upstream/hestiacp
git rm -rf .
git archive --remote="$HESTIACP_DIR" HEAD | tar -x
git add -A
git commit -m "upstream: HestiaCP snapshot $(date +%Y-%m-%d)" --allow-empty
git push origin upstream/hestiacp
git checkout dev

# ── 1.3 Show changes since last snapshot ─────────────────────────────────────
echo ""
echo "==> Changes in hestiacp since last sync:"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "    No new commits in hestiacp mirror."
else
  echo ""
  git -C "$HESTIACP_DIR" log --oneline "${BEFORE}..${AFTER}"
  echo ""
  echo "==> Changed files:"
  git -C "$HESTIACP_DIR" diff --name-only "$BEFORE" "$AFTER"
fi

# ════════════════════════════════════════════════════════════════════════════
# PART 2 — phpquoteshellarg (single vendored file, tag-based, rare changes)
# ════════════════════════════════════════════════════════════════════════════
#
# Unlike HestiaCP, phpquoteshellarg is a tiny, near-frozen upstream project.
# We don't pull every commit on its default branch — we track tagged
# releases only, since that's what's actually vendored into
# web/inc/lib/quoteshellarg.php. A "no new tag" result is the expected,
# healthy outcome most of the time.

echo ""
echo "==> Checking phpquoteshellarg upstream for new tags..."
cd "$PHPQUOTESHELLARG_DIR"
git fetch --tags --quiet

# Tag currently vendored in HestiaRE — read directly from the file header
# of web/inc/lib/quoteshellarg.php, so there's a single source of truth
# instead of maintaining the version number in two places. The header in
# that file must contain a line like:
#   # Vendored from: https://github.com/hestiacp/phpquoteshellarg
#   # Upstream version: v1.1.0
VENDORED_FILE="$HESTIARE_DIR/web/inc/lib/quoteshellarg.php"

if [ ! -f "$VENDORED_FILE" ]; then
  echo "    ERROR: $VENDORED_FILE not found — check HESTIARE_DIR or file path."
  exit 1
fi

CURRENT_VENDORED_TAG=$(grep -oP 'Upstream version:\s*\K\S+' "$VENDORED_FILE" || true)

if [ -z "$CURRENT_VENDORED_TAG" ]; then
  echo "    ERROR: could not find 'Upstream version:' line in $VENDORED_FILE"
  echo "    Add a header comment like: // Upstream version: v1.1.0"
  exit 1
fi

echo "    Currently vendored version (read from file header): $CURRENT_VENDORED_TAG"

# Latest tag available upstream, sorted by version
LATEST_UPSTREAM_TAG=$(git tag --sort=-v:refname | head -n1)

if [ "$LATEST_UPSTREAM_TAG" = "$CURRENT_VENDORED_TAG" ]; then
  echo "    No new release. Vendored version ($CURRENT_VENDORED_TAG) is current."
else
  echo "    NEW RELEASE AVAILABLE: $LATEST_UPSTREAM_TAG (vendored: $CURRENT_VENDORED_TAG)"
  echo ""
  echo "==> Changes between $CURRENT_VENDORED_TAG and $LATEST_UPSTREAM_TAG:"
  git log --oneline "${CURRENT_VENDORED_TAG}..${LATEST_UPSTREAM_TAG}"
  echo ""
  echo "==> Changed files:"
  git diff --name-only "$CURRENT_VENDORED_TAG" "$LATEST_UPSTREAM_TAG"
  echo ""
  echo "    ACTION NEEDED: review the diff above, then if it's safe to take:"
  echo "    1. Update web/inc/lib/quoteshellarg.php with the new version"
  echo "    2. Update the 'Upstream version:' line in that file's header to $LATEST_UPSTREAM_TAG"
  echo "       (this script reads the version from there — no separate value to maintain)"
  echo "    3. Update upstream/phpquoteshellarg snapshot branch (see below)"
fi

# ── 2.1 Update upstream/phpquoteshellarg snapshot branch ────────────────────
# Mirrors the exact tagged tree into HestiaRE for reference/diffing, same
# pattern as upstream/hestiacp — but only re-synced when a new tag exists,
# not on every run, to avoid noisy empty commits for a project that barely
# changes.

if [ "$LATEST_UPSTREAM_TAG" != "$CURRENT_VENDORED_TAG" ]; then
  echo ""
  echo "==> Updating upstream/phpquoteshellarg snapshot to $LATEST_UPSTREAM_TAG..."
  cd "$HESTIARE_DIR"
  git checkout upstream/phpquoteshellarg
  git rm -rf .
  git archive --remote="$PHPQUOTESHELLARG_DIR" "$LATEST_UPSTREAM_TAG" | tar -x
  git add -A
  git commit -m "upstream: phpquoteshellarg snapshot $LATEST_UPSTREAM_TAG ($(date +%Y-%m-%d))"
  git push origin upstream/phpquoteshellarg
  git checkout dev
  echo "    Snapshot updated. Manual review and integration into"
  echo "    web/inc/lib/quoteshellarg.php is still required (not automatic)."
fi

# ════════════════════════════════════════════════════════════════════════════
# PART 3 — keep local dev checkout current (nine is a sync-only host, but
# pulling here is free and avoids working against a stale dev by accident)
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "==> Pulling latest dev..."
cd "$HESTIARE_DIR"
git checkout dev
git pull origin dev

# ════════════════════════════════════════════════════════════════════════════
# PART 4 — vendored web assets (alpinejs, fontawesome, normalize.css)
# ════════════════════════════════════════════════════════════════════════════
#
# Version check via update-web-vendor.sh --check: compares the pins in
# VENDORED.json against npm registry / GitHub API. Runs after the dev pull
# on purpose, so the pins and the script itself are always current.
# Strictly read-only — on a new release, rebuild the snapshot branch with:
#   share/upstream/update-web-vendor.sh --fetch <asset>[@version] --push
# Adoption into dev happens separately via merge/cherry-pick + PR.

echo ""
echo "==> Checking vendored web assets (VENDORED.json vs upstream)..."
if ! "$HESTIARE_DIR/share/upstream/update-web-vendor.sh" --check; then
  echo "    WARNING: web-vendor check failed (network/API?) — re-run manually:"
  echo "    $HESTIARE_DIR/share/upstream/update-web-vendor.sh --check"
fi