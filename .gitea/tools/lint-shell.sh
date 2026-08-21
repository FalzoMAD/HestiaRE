#!/bin/bash
# HestiaRE shell lint gate (#477). Check-only, never rewrites a file.
#
# Two tiers, because the tree carries ~240 inherited HestiaCP warnings (SC2046/SC2166/SC2164) that
# are a separate cleanup job. A gate that demanded them today would be red forever and get ignored:
#
#   TIER 1  whole tree, severity=error   - must always pass (0 findings as of this commit)
#   TIER 2  changed files, >=warning     - new/edited code must not add warnings
#
# Both tiers read .shellcheckrc, which disables only the verified house idioms. Formatting is
# checked with shfmt against .editorconfig (tabs, spaced redirections, leading `&&`, indented case)
# - the same settings HestiaCP's prettier-plugin-sh uses, so the tree already conforms.
#
# Usage:  .gitea/tools/lint-shell.sh           # tier 1 + tier 2 vs origin/dev (what CI runs)
#         .gitea/tools/lint-shell.sh --all     # tier 2 over the whole tree as well
#         .gitea/tools/lint-shell.sh --base X  # diff against X instead of origin/dev

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

BASE='origin/dev'
ALL=''
while [ $# -gt 0 ]; do
	case "$1" in
		--all) ALL=1 ;;
		--base)
			BASE="${2:-}"
			shift
			;;
		-h | --help)
			sed -n '2,20p' "$0"
			exit 0
			;;
		*)
			echo "unknown argument: $1" >&2
			exit 2
			;;
	esac
	shift
done

for t in shellcheck shfmt; do
	command -v "$t" > /dev/null 2>&1 || {
		echo "ERROR: $t is not installed." >&2
		exit 2
	}
done

# shfmt reads .editorconfig by file PATH, and the shell block is a path glob - a blob on stdin gets
# shfmt's own defaults instead. Pass the settings explicitly, asserted so the two cannot drift.
mapfile -t ec_shell < <(sed -n '/^\[{bin\/h-\*/,/^\[.*\]$/p' .editorconfig)
[ "${#ec_shell[@]}" -gt 1 ] || {
	echo "ERROR: no shell block found in .editorconfig" >&2
	exit 2
}
for k in switch_case_indent space_redirects binary_next_line; do
	printf '%s\n' "${ec_shell[@]}" | grep -q "^$k *= *true" || {
		echo "ERROR: .editorconfig shell block no longer sets $k - update the shfmt flags below" >&2
		exit 2
	}
done
grep -q '^indent_style *= *tab' .editorconfig || {
	echo "ERROR: .editorconfig no longer indents with tabs - update the shfmt flags below" >&2
	exit 2
}
FMT=(-i 0 -ci -sr -bn)

# The shell surface: the CLI, the sourced libraries, the bootstrap, the installer family, the
# scripts we ship. v-* are symlinks (skipped by -f).
is_shell() { [[ "$1" =~ ^(bin/h-|sbin/|include/.*\.sh$|install\.sh$|\.gitea/tools/.*\.sh$|share/.*\.sh$|share/apache2/httpd-prerotate/awstats$|share/bubblewrap/jailbash$|share/security/hestia-jail\.init$|web/locale/.*\.sh$) ]]; }

# A path list goes stale on a move, and silently: func/ -> include/ was carried over, sbin/ was not,
# and the gate then answered a change to the installer with "no changed shell files" - green because
# it had looked at nothing. So the list is measured against a set derived from CONTENT (shebang on
# line 1, or a .sh name), and anything shell that it misses fails the run.
#
# The interpreter set is the one shellcheck has a dialect for (sh, bash, dash, ksh; busybox spells
# itself #!/bin/sh). zsh and csh are deliberately OUT: shellcheck cannot check them at all, so
# pulling one in would paint tier 1 red on a file no tool here can judge. That is the assumption
# this derivation carries - a zsh script would be invisible to both the list and this check, and it
# would need a decision of its own, not a wider regex.
shell_by_content() {
	{
		git ls-files '*.sh'
		git ls-files -z | xargs -0 -r grep -I -H -n -m1 -E '^#!' 2> /dev/null \
			| grep -E ':1:#!.*[ /](env +)?(ba|da|k)?sh([ \t]|$)' | sed 's/:1:#!.*$//'
	} | sort -u | while read -r f; do
		[ -f "$f" ] && [ ! -L "$f" ] && echo "$f"
	done
}

mapfile -t ALL_FILES < <(git ls-files | while read -r f; do
	is_shell "$f" && [ -f "$f" ] && echo "$f"
done)

# Changed files only: an untracked/renamed path may be gone, so filter to what still exists.
changed=()
if git rev-parse --verify --quiet "$BASE" > /dev/null; then
	mapfile -t changed < <(git diff --name-only --diff-filter=d "$BASE"...HEAD 2> /dev/null | while read -r f; do
		is_shell "$f" && [ -f "$f" ] && echo "$f"
	done)
else
	echo "note: base '$BASE' not found - tier 2 falls back to the whole tree" >&2
	ALL=1
fi
[ -n "$ALL" ] && changed=("${ALL_FILES[@]}")

# A moved file's baseline lives at its OLD path. Looking it up by the new path finds nothing, both
# comparisons below then read an empty base, and every inherited finding is rated as introduced by
# this change - the func/ -> include/ rename lit up six libraries nobody had edited. Map new -> old
# from git's own rename detection so the gate keeps judging regressions, not moves.
# Fails safe: if git does not detect a rename (heavy edit alongside the move), the file falls back to
# its own path and its findings read as new - a false red, never a false green.
declare -A BASE_PATH
if git rev-parse --verify --quiet "$BASE" > /dev/null; then
	while IFS=$'\t' read -r _ old new; do
		[ -n "${new:-}" ] && BASE_PATH["$new"]="$old"
	done < <(git diff --find-renames --diff-filter=R --name-status "$BASE"...HEAD 2> /dev/null)
fi
base_of() { echo "${BASE_PATH[$1]:-$1}"; }

rc=0
echo "== coverage: every shell file is inside is_shell() =="
uncovered=()
seen_content=0
while read -r f; do
	seen_content=$((seen_content + 1))
	is_shell "$f" || uncovered+=("$f")
done < <(shell_by_content)
if [ "$seen_content" -eq 0 ]; then
	# Zero uncovered files is the expected result, so a sweep that read nothing looks exactly like a
	# clean one. It has to fail instead.
	echo "   FAILED - the content sweep found no shell file at all, so it proves nothing."
	rc=1
elif [ "${#uncovered[@]}" -gt 0 ]; then
	printf '   %s\n' "${uncovered[@]}"
	echo "   FAILED - ${#uncovered[@]} shell file(s) outside is_shell(). Extend the pattern above."
	rc=1
else
	echo "   OK - $seen_content of $seen_content, and ${#ALL_FILES[@]} selected by path"
fi

# .editorconfig is a SECOND hand-kept list of the same surface, and only is_shell() is measured
# against the tree. Drift means an editor writes one form while CI demands another, and that only
# surfaces as a red run later. shfmt is its own oracle here: with no flags it resolves settings by
# PATH from .editorconfig, so on a tree that is house-formatted throughout, a bare run must agree -
# where it does not, the path is outside the block.
#
# What it cannot see: a file that happens to format the same under both settings. Such a file is not
# at risk either, but it also cannot reveal a gap - hence the probe below, which MUST come out
# different, or the check is inert and says so instead of passing.
echo "== .editorconfig: same surface as is_shell() =="
ec_probe=$(mktemp -t shfmt-ec-XXXXXX.sh)
printf 'case "$1" in\n\ta) echo x 2> /dev/null ;;\nesac\n' > "$ec_probe"
if shfmt -d "$ec_probe" > /dev/null 2>&1; then
	echo "   FAILED - the probe cannot tell house settings from shfmt defaults, so this proves nothing."
	rc=1
else
	ec_drift=()
	for f in "${ALL_FILES[@]}"; do
		# A file that is unformatted anyway is reported by the debt check; it cannot answer this one.
		shfmt "${FMT[@]}" -d "$f" > /dev/null 2>&1 || continue
		shfmt -d "$f" > /dev/null 2>&1 || ec_drift+=("$f")
	done
	if [ "${#ec_drift[@]}" -gt 0 ]; then
		printf '   %s\n' "${ec_drift[@]}"
		echo "   FAILED - .editorconfig misses ${#ec_drift[@]} file(s) the gate checks. Extend its shell block."
		rc=1
	else
		echo "   OK - ${#ALL_FILES[@]} files, editor and CI agree on every one"
	fi
fi
rm -f "$ec_probe"

echo "== tier 1: shellcheck (severity=error), ${#ALL_FILES[@]} files =="
if out=$(shellcheck -S error -f gcc "${ALL_FILES[@]}" 2> /dev/null) && [ -z "$out" ]; then
	echo "   OK"
else
	echo "$out"
	echo "   FAILED - an error-severity finding is a bug, not style."
	rc=1
fi

if [ ${#changed[@]} -eq 0 ]; then
	echo "== tier 2: no changed shell files vs $BASE =="
else
	# Same "do not make it worse" rule as the formatter below: a legacy file carries findings that are
	# not this change's business, and demanding them would bury the actual change (touch h-install-hestia
	# for one line, inherit its SC2044). Findings are compared against the base version of the same file
	# by SIGNATURE - code plus message, without the line number, which shifts on every edit.
	echo "== tier 2: shellcheck (severity>=warning), ${#changed[@]} changed files =="
	sc_sig() { sed 's/^[^:]*:[0-9]*:[0-9]*: //' | sort -u; }
	sc_new=0
	sc_debt=0
	for f in "${changed[@]}"; do
		now=$(shellcheck -S warning -f gcc "$f" 2> /dev/null | sc_sig)
		[ -z "$now" ] && continue
		base=$(git show "$BASE:$(base_of "$f")" 2> /dev/null | shellcheck -S warning -f gcc - 2> /dev/null | sc_sig)
		added=$(comm -23 <(echo "$now") <(echo "$base"))
		if [ -n "$added" ]; then
			echo "--- $f"
			echo "$added" | sed 's/^/   /'
			sc_new=$((sc_new + 1))
		else
			sc_debt=$((sc_debt + $(echo "$now" | grep -c .)))
		fi
	done
	if [ "$sc_new" -gt 0 ]; then
		echo "   FAILED - new finding(s) in $sc_new file(s)."
		echo "   Silence a deliberate one per line: '# shellcheck disable=SCxxxx  # why'."
		rc=1
	else
		echo "   OK${sc_debt:+ ($sc_debt pre-existing, not blocking)}"
	fi

	# Formatting is judged as "do not make it worse", not "clean up on sight". 26 inherited files
	# still deviate, several of them the installer and include/main.sh; demanding a reformat from whoever
	# next edits one would bury their change - exactly what a mass reformat does, only piecemeal.
	# So: a file that was clean in the base must stay clean, and a new file must start clean; a file
	# that was already dirty is reported and left alone.
	echo "== shfmt (check-only), ${#changed[@]} changed files =="
	fmt_fail=0
	fmt_debt=0
	for f in "${changed[@]}"; do
		shfmt "${FMT[@]}" -d "$f" > /dev/null 2>&1 && continue
		if git show "$BASE:$(base_of "$f")" 2> /dev/null | shfmt "${FMT[@]}" -d - > /dev/null 2>&1; then
			# clean before, dirty now (or newly added) -> a regression this change introduced
			echo "--- $f"
			shfmt "${FMT[@]}" -d "$f" 2>&1 | sed 's/^/   /'
			fmt_fail=$((fmt_fail + 1))
		else
			fmt_debt=$((fmt_debt + 1))
			echo "   note: $f was already unformatted before this change - left alone"
		fi
	done
	if [ "$fmt_fail" -gt 0 ]; then
		echo "   FAILED - $fmt_fail file(s) regressed. Apply with: shfmt -w <file>"
		rc=1
	else
		echo "   OK${fmt_debt:+ ($fmt_debt pre-existing, not blocking)}"
	fi

	# The exemption above hides the set it skips, so judge it by size: shrink yes, grow no. Says
	# nothing about formatting inside an exempt file. Both sides also report how many files they
	# looked at, because a side that read nothing counts 0 debt - and zero debt is the expected
	# result here, so the degenerate run would be indistinguishable from the good one.
	debt_now=0
	for f in "${ALL_FILES[@]}"; do
		shfmt "${FMT[@]}" -d "$f" > /dev/null 2>&1 || debt_now=$((debt_now + 1))
	done
	debt_base=0
	seen_base=0
	while read -r f; do
		is_shell "$f" || continue
		seen_base=$((seen_base + 1))
		git show "$BASE:$f" 2> /dev/null | shfmt "${FMT[@]}" -d - > /dev/null 2>&1 || debt_base=$((debt_base + 1))
	done < <(git ls-tree -r --name-only "$BASE" 2> /dev/null)

	echo "== shfmt debt (whole tree): $debt_now of ${#ALL_FILES[@]}, base $debt_base of $seen_base =="
	if [ "${#ALL_FILES[@]}" -eq 0 ] || [ "$seen_base" -eq 0 ]; then
		echo "   FAILED - a side measured no files at all, so its count carries no verdict."
		rc=1
	elif [ "$debt_now" -gt "$debt_base" ]; then
		echo "   FAILED - the exempt set grew by $((debt_now - debt_base)). Apply with: shfmt -w <file>"
		rc=1
	elif [ "$debt_now" -eq 0 ]; then
		echo "   OK - nothing exempt, every file is checked"
	else
		echo "   OK - not growing. These files are exempt from the check above:"
		for f in "${ALL_FILES[@]}"; do
			shfmt "${FMT[@]}" -d "$f" > /dev/null 2>&1 || echo "      $f"
		done
	fi
fi

exit "$rc"
