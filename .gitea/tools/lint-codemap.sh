#!/bin/bash
# HestiaRE CODEMAP consistency check (#513). Read-only; never rewrites CODEMAP.json.
#
# LOCAL / MANUAL, not a CI gate. It needs python3 to parse JSON robustly, and the Gitea runner host is kept
# to git + shellcheck + shfmt with no language runtime (see .gitea/workflows/lint.yml) - the same reason the
# PHP linters are sandbox-only. Run it by hand when you touch CODEMAP.json, and as part of the pre-PR sweep
# on any change that renames or removes a file CODEMAP references. Pure-bash JSON parsing was rejected: a
# fragile parser that false-positives is worse than no check, because a guard that cries wolf gets muted.
#
# CODEMAP.json is built (#481, Stage 0) so nobody has to re-derive a subsystem from the code - but within a
# handful of PRs it had already drifted: an entry still pointed at install/common/firewall/ipset/blacklist.sh
# after the install/ tree was dissolved (#119), and the firewall entry gave FIREWALL_SYSTEM its pre-#495
# value. A wrong path or a wrong literal is worse than stale prose, because the next person greps for it.
#
# WHAT THIS CHECKS (mechanical, zero false positives by design - a guard that cries wolf gets muted):
#   1. CODEMAP.json is valid JSON.
#   2. Every path in the STRUCTURED fields exists: entry_points, key_files, commands, commands_native,
#      directories. Globs must match at least one file; directories must be directories. This is the class
#      that caught the dead blacklist.sh reference.
#
# WHAT THIS DELIBERATELY DOES NOT CHECK (see #513):
#   - Prose accuracy: no check can tell whether a paragraph still describes reality.
#   - Config-VALUE literals quoted in prose (FIREWALL_SYSTEM=nftables etc.): the highest-value check, but
#     not robustly parseable from free text without false positives. Left to review + the blast-radius step.
#   - Closed-issue references in BROKEN:/hazards: keys: needs the Gitea API and a token; out of scope for a
#     no-network lint gate.
#   - Command coverage: CODEMAP curates components, not all ~510 h-* commands, so "every command is mapped"
#     is not this map's contract.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

MAP='CODEMAP.json'
fail=0
note() { echo "  $1"; }

# 1. valid JSON
if ! python3 -m json.tool "$MAP" > /dev/null 2>&1; then
	echo "[ FAIL ] $MAP is not valid JSON"
	python3 -m json.tool "$MAP" 2>&1 | head -n1 | sed 's/^/  /'
	exit 1
fi
echo "[ OK ] $MAP is valid JSON"

# 2. structured-field paths must resolve. A glob resolves if it matches >=1 entry; a plain path if it
# exists; a directory field entry must be a directory. Repo-root files (install.sh, VERSION) have no slash
# and are handled the same way. One allowance: CLAUDE.local.md is intentionally untracked (personal host
# details kept off the public mirror), so a fresh CI clone will not have it - skip that single reference.
missing=''
while IFS=$'\t' read -r field path; do
	[ -n "$path" ] || continue
	[ "$path" = 'CLAUDE.local.md' ] && continue
	if [[ "$path" == *'*'* ]]; then
		compgen -G "$path" > /dev/null 2>&1 || missing="$missing\n  $field: $path (glob matches nothing)"
	elif [ "$field" = 'directories' ]; then
		[ -d "$path" ] || missing="$missing\n  $field: $path (not a directory)"
	else
		[ -e "$path" ] || missing="$missing\n  $field: $path (does not exist)"
	fi
done < <(
	python3 - "$MAP" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
FIELDS = {"entry_points", "key_files", "commands", "commands_native", "directories"}
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in FIELDS and isinstance(v, list):
                for x in v:
                    if isinstance(x, str) and x:
                        print(f"{k}\t{x}")
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
walk(d)
PY
)

if [ -n "$missing" ]; then
	echo "[ FAIL ] CODEMAP references a path that no longer exists:"
	echo -e "$missing"
	fail=1
else
	echo "[ OK ] every structured CODEMAP path resolves"
fi

exit $fail
