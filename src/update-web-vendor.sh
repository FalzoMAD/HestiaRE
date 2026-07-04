#!/bin/bash
# info: check/fetch vendored web assets and maintain the upstream/* snapshot branches
# options: --check [ASSET] | --fetch ASSET[@VERSION] [--push] | --help
#
# example: ./src/update-web-vendor.sh --check
#          ./src/update-web-vendor.sh --fetch alpinejs
#          ./src/update-web-vendor.sh --fetch fontawesome@7.3.0 --push
#
# Maintains the READ-ONLY snapshot branches (one per vendor project, files in
# HestiaRE target structure + VERSIONS.md), analog to upstream/phpquoteshellarg:
#
#   asset          branch                  files
#   alpinejs       upstream/alpinejs       web/js/vendor/alpinejs*.min.js + LICENSE
#   fontawesome    upstream/fontawesome    web/css/vendor/fontawesome/* + web/webfonts/fa-solid-900.woff2
#   normalize-css  upstream/normalize-css  web/css/vendor/normalize.css + LICENSE
#
# --check is strictly read-only (network: npm registry / GitHub API only).
# --fetch works per asset: downloads exactly one project at the given (or
# latest) version, verifies publisher hashes where available (npm integrity,
# GitHub release digest), applies the FA webfont-path rewrite and commits the
# result to the asset's upstream/* branch — one commit per asset. Adoption
# into dev happens separately via merge/cherry-pick + PR, never here.
#
# Dependencies: bash, git, curl, jq, tar, unzip, sha256sum, sha512sum, base64
# (all covered by the installer's base package set).

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
UA="hestiare-update-web-vendor"
PUSH=no

# ── helpers ────────────────────────────────────────────────

fail() {
	echo "ERROR: $*" >&2
	exit 1
}

api() {
	curl -fsSL -A "$UA" "$1" || fail "request failed: $1"
}

# pinned version of an asset as shipped in dev (source of truth: VENDORED.json)
pinned_version() {
	jq -r --arg n "$1" '.vendored[] | select(.name == $n) | .upstream_version' \
		"$REPO_ROOT/VENDORED.json"
}

latest_version() {
	case "$1" in
		alpinejs) api "https://registry.npmjs.org/alpinejs/latest" | jq -r '.version' ;;
		fontawesome) api "https://api.github.com/repos/FortAwesome/Font-Awesome/releases/latest" | jq -r '.tag_name' ;;
		# no GitHub releases upstream, only tags — highest version wins
		normalize-css) api "https://api.github.com/repos/necolas/normalize.css/tags?per_page=100" \
			| jq -r '.[].name | ltrimstr("v")' | sort -V | tail -1 ;;
		*) fail "unknown asset: $1 (known: alpinejs fontawesome normalize-css)" ;;
	esac
}

# verify a file against an npm "integrity" value (sha512-<base64>)
verify_npm_integrity() {
	local file=$1 integrity=$2 want have
	[[ "$integrity" == sha512-* ]] || fail "unexpected npm integrity format: $integrity"
	want=$(echo "${integrity#sha512-}" | base64 -d | od -A n -t x1 | tr -d ' \n')
	have=$(sha512sum "$file" | cut -d' ' -f1)
	[ "$want" = "$have" ] || fail "npm integrity mismatch for $file"
}

verify_sha256() {
	local file=$1 want=$2 have
	have=$(sha256sum "$file" | cut -d' ' -f1)
	[ "$want" = "$have" ] || fail "sha256 mismatch for $file (want $want, have $have)"
}

file_sha256() {
	sha256sum "$1" | cut -d' ' -f1
}

# npm tarball: download + integrity-verify + extract one file from package/
npm_fetch_file() {
	local pkg=$1 version=$2 inner=$3 out=$4 meta tarball integrity
	meta=$(api "https://registry.npmjs.org/$pkg/$version")
	tarball=$(echo "$meta" | jq -r '.dist.tarball')
	integrity=$(echo "$meta" | jq -r '.dist.integrity')
	curl -fsSL -A "$UA" -o "$TMP/pkg.tgz" "$tarball"
	verify_npm_integrity "$TMP/pkg.tgz" "$integrity"
	tar -xzf "$TMP/pkg.tgz" -C "$TMP" "package/$inner"
	install -D -m 644 "$TMP/package/$inner" "$out"
	rm -rf "$TMP/pkg.tgz" "$TMP/package"
	echo "$tarball"
}

# temp worktree on the asset's upstream/* branch (created orphan if missing)
open_worktree() {
	local branch=$1
	WT=$(mktemp -d)
	git -C "$REPO_ROOT" fetch origin "$branch" 2> /dev/null || true
	if git -C "$REPO_ROOT" show-ref --verify -q "refs/heads/$branch" \
		|| git -C "$REPO_ROOT" show-ref --verify -q "refs/remotes/origin/$branch"; then
		git -C "$REPO_ROOT" worktree add "$WT" -B "$branch" \
			"$(git -C "$REPO_ROOT" show-ref --verify -q "refs/remotes/origin/$branch" && echo "origin/$branch" || echo "$branch")" -q
	else
		git -C "$REPO_ROOT" worktree add "$WT" --detach -q
		git -C "$WT" checkout --orphan "$branch" -q
		git -C "$WT" rm -rfq . 2> /dev/null || true
	fi
}

close_worktree() {
	[ -n "${WT:-}" ] || return 0
	git -C "$REPO_ROOT" worktree remove --force "$WT" 2> /dev/null || rm -rf "$WT"
	WT=""
}

# commit the prepared worktree; skips cleanly when nothing changed
commit_snapshot() {
	local asset=$1 version=$2 branch=$3
	git -C "$WT" add -A
	if git -C "$WT" diff --cached --quiet; then
		echo "$asset $version: snapshot identical to $branch — nothing to commit."
		return 0
	fi
	git -C "$WT" commit -qm "upstream: $asset artifacts snapshot $version"
	echo "$asset $version: committed to $branch ($(git -C "$WT" rev-parse --short HEAD))"
	if [ "$PUSH" = "yes" ]; then
		git -C "$WT" push origin "$branch"
		echo "$asset $version: pushed origin/$branch"
	else
		echo "  push with: git push origin $branch"
	fi
	echo "  adopt into dev via merge/cherry-pick from $branch + PR (update VENDORED.json there)."
}

# ── per-asset fetch ────────────────────────────────────────

fetch_alpinejs() {
	local version=$1 branch="upstream/alpinejs" dir tb1 tb2 sha1 sha2
	open_worktree "$branch"
	dir="$WT/web/js/vendor"
	tb1=$(npm_fetch_file "alpinejs" "$version" "dist/cdn.min.js" "$dir/alpinejs.min.js")
	tb2=$(npm_fetch_file "@alpinejs/collapse" "$version" "dist/cdn.min.js" "$dir/alpinejs-collapse.min.js")
	curl -fsSL -A "$UA" -o "$dir/LICENSE-alpinejs.md" \
		"https://raw.githubusercontent.com/alpinejs/alpine/v$version/LICENSE.md"
	sha1=$(file_sha256 "$dir/alpinejs.min.js")
	sha2=$(file_sha256 "$dir/alpinejs-collapse.min.js")
	cat > "$dir/VERSIONS.md" << EOF
# Vendored artifacts — Alpine.js project (alpinejs/alpine monorepo)

Branch \`$branch\`: READ ONLY snapshot of the published build artifacts,
laid out in HestiaRE target structure for direct merge/cherry-pick into dev.
Update via src/update-web-vendor.sh (--fetch alpinejs[@version]).

| File | Package | Version | Source | sha256 |
|---|---|---|---|---|
| alpinejs.min.js | alpinejs | $version | $tb1 (dist/cdn.min.js) | $sha1 |
| alpinejs-collapse.min.js | @alpinejs/collapse | $version | $tb2 (dist/cdn.min.js) | $sha2 |

License: MIT (LICENSE-alpinejs.md, from https://github.com/alpinejs/alpine v$version).
Note: the GitHub repo commits no dist files and attaches no release assets —
the npm registry tarball is the project's official publish artifact.
EOF
	commit_snapshot "alpinejs" "$version" "$branch"
	close_worktree
}

fetch_normalize() {
	local version=$1 branch="upstream/normalize-css" dir sha raw
	raw="https://raw.githubusercontent.com/necolas/normalize.css/$version"
	open_worktree "$branch"
	dir="$WT/web/css/vendor"
	mkdir -p "$dir"
	curl -fsSL -A "$UA" -o "$dir/normalize.css" "$raw/normalize.css"
	curl -fsSL -A "$UA" -o "$dir/LICENSE-normalize.md" "$raw/LICENSE.md"
	grep -q "normalize.css v$version" "$dir/normalize.css" \
		|| fail "downloaded normalize.css does not carry version banner v$version"
	sha=$(file_sha256 "$dir/normalize.css")
	cat > "$dir/VERSIONS.md" << EOF
# Vendored artifacts — normalize.css (necolas/normalize.css)

Branch \`$branch\`: READ ONLY snapshot of the upstream file,
laid out in HestiaRE target structure for direct merge/cherry-pick into dev.
Update via src/update-web-vendor.sh (--fetch normalize-css[@version]).

| File | Version | Source | sha256 |
|---|---|---|---|
| normalize.css | $version | $raw/normalize.css | $sha |

License: MIT (LICENSE-normalize.md, from the same tag).
Note: upstream is finished software — last release 2018; expect no updates.
EOF
	commit_snapshot "normalize-css" "$version" "$branch"
	close_worktree
}

fetch_fontawesome() {
	local version=$1 branch="upstream/fontawesome" dir release digest url zipname
	zipname="fontawesome-free-$version-web.zip"
	release=$(api "https://api.github.com/repos/FortAwesome/Font-Awesome/releases/tags/$version")
	url=$(echo "$release" | jq -r --arg n "$zipname" '.assets[] | select(.name == $n) | .browser_download_url')
	digest=$(echo "$release" | jq -r --arg n "$zipname" '.assets[] | select(.name == $n) | .digest | ltrimstr("sha256:")')
	[ -n "$url" ] || fail "release $version has no asset $zipname"
	curl -fsSL -A "$UA" -o "$TMP/fa.zip" "$url"
	[ -n "$digest" ] && [ "$digest" != "null" ] && verify_sha256 "$TMP/fa.zip" "$digest"
	unzip -oq "$TMP/fa.zip" -d "$TMP/fa" \
		"fontawesome-free-$version-web/css/fontawesome.css" \
		"fontawesome-free-$version-web/css/solid.css" \
		"fontawesome-free-$version-web/webfonts/fa-solid-900.woff2" \
		"fontawesome-free-$version-web/LICENSE.txt"

	open_worktree "$branch"
	dir="$WT/web/css/vendor/fontawesome"
	mkdir -p "$dir" "$WT/web/webfonts"
	cp "$TMP/fa/fontawesome-free-$version-web/css/fontawesome.css" "$dir/fontawesome.css"
	# panel serves webfonts from the web root, not relative to the CSS
	sed 's|\.\./webfonts/|/webfonts/|g' \
		"$TMP/fa/fontawesome-free-$version-web/css/solid.css" > "$dir/solid.css"
	cp "$TMP/fa/fontawesome-free-$version-web/LICENSE.txt" "$dir/LICENSE.txt"
	cp "$TMP/fa/fontawesome-free-$version-web/webfonts/fa-solid-900.woff2" "$WT/web/webfonts/fa-solid-900.woff2"
	cat > "$dir/VERSIONS.md" << EOF
# Vendored artifacts — Font Awesome Free (FortAwesome/Font-Awesome)

Branch \`$branch\`: READ ONLY snapshot of the official release
artifact contents, laid out in HestiaRE target structure for direct
merge/cherry-pick into dev.
Update via src/update-web-vendor.sh (--fetch fontawesome[@version]).

Release artifact: $zipname
Source: $url
Artifact sha256: ${digest:-"(no digest published for this release)"}

| File | Version | Modification | sha256 (as vendored) |
|---|---|---|---|
| fontawesome.css | $version | none (byte-identical to css/fontawesome.css) | $(file_sha256 "$dir/fontawesome.css") |
| solid.css | $version | ../webfonts/ -> /webfonts/ | $(file_sha256 "$dir/solid.css") |
| fa-solid-900.woff2 | $version | none (byte-identical to webfonts/fa-solid-900.woff2) | $(file_sha256 "$WT/web/webfonts/fa-solid-900.woff2") |

License: CC BY 4.0 (icons) / SIL OFL 1.1 (fonts) / MIT (CSS code) — LICENSE.txt
from the same artifact.
Scope: Solid style only. The panel uses .fas exclusively (grep-verified);
regular/brands CSS and webfonts are intentionally not vendored (YAGNI).
EOF
	commit_snapshot "fontawesome" "$version" "$branch"
	close_worktree
}

# ── modes ──────────────────────────────────────────────────

do_check() {
	local assets=$1 a pinned latest mark
	[ "$assets" = "all" ] && assets="alpinejs fontawesome normalize-css"
	printf '%-15s %-10s %-10s %s\n' "ASSET" "PINNED" "LATEST" "STATUS"
	for a in $assets; do
		case "$a" in
			alpinejs) pinned=$(pinned_version alpinejs) ;;
			fontawesome) pinned=$(pinned_version fontawesome-free) ;;
			normalize-css) pinned=$(pinned_version normalize.css) ;;
			*) fail "unknown asset: $a (known: alpinejs fontawesome normalize-css)" ;;
		esac
		latest=$(latest_version "$a")
		mark="up to date"
		[ "$pinned" != "$latest" ] && mark="UPDATE AVAILABLE (--fetch $a@$latest)"
		printf '%-15s %-10s %-10s %s\n' "$a" "${pinned:-?}" "${latest:-?}" "$mark"
	done
}

do_fetch() {
	local spec=$1 asset version
	asset=${spec%%@*}
	version=""
	[[ "$spec" == *@* ]] && version=${spec#*@}
	[ -n "$version" ] || version=$(latest_version "$asset")
	echo "fetching $asset $version ..."
	case "$asset" in
		alpinejs) fetch_alpinejs "$version" ;;
		fontawesome) fetch_fontawesome "$version" ;;
		normalize-css) fetch_normalize "$version" ;;
		*) fail "unknown asset: $asset (known: alpinejs fontawesome normalize-css)" ;;
	esac
}

usage() {
	sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
}

# ── main ───────────────────────────────────────────────────

TMP=$(mktemp -d)
WT=""
trap 'close_worktree; rm -rf "$TMP"' EXIT

MODE="" ARG=""
while [ $# -gt 0 ]; do
	case "$1" in
		--check)
			MODE=check
			ARG="all"
			[ $# -gt 1 ] && [[ "$2" != --* ]] && {
				ARG=$2
				shift
			}
			;;
		--fetch)
			MODE=fetch
			[ $# -gt 1 ] || fail "--fetch needs ASSET[@VERSION]"
			ARG=$2
			shift
			;;
		--push) PUSH=yes ;;
		--help | -h)
			usage
			exit 0
			;;
		*) fail "unknown option: $1 (see --help)" ;;
	esac
	shift
done

case "$MODE" in
	check) do_check "$ARG" ;;
	fetch) do_fetch "$ARG" ;;
	*)
		usage
		exit 1
		;;
esac
