#!/bin/bash
# HestiaRE panel tempfile check (#703). Read-only; rewrites nothing.
#
# The panel used to take `exec("mktemp")` and read `$output[0]` without checking it. On a failure
# that index is unset, so the path is empty: `fopen()` returns false and `fwrite()` on it is a
# TypeError - the save route dies with a fatal and the certificate or service config it was about
# to hand the CLI never exists. It was thirty save routes, all the same shape, and none of them was
# wrong in an interesting way - which is exactly why the next one will look reasonable too.
#
# So: no route calls mktemp itself. `private_tmpdir()`, `private_tmpfile()` and `secret_tmpfile()`
# (web/inc/helpers.php) return `false` and set error_msg, which forces the caller to branch.
#
# THE ALLOWED LIST IS EMPTY, deliberately. A guard with exceptions drifts into a guard that is all
# exceptions; the helpers live in helpers.php and that file is the only place a mktemp belongs.
#
# LOCAL / MANUAL, like lint-codemap.sh and lint-json-emitters.sh - the Gitea runner host is kept to
# git + shellcheck + shfmt. Run it when you touch a panel save route.
#
# WHAT IT DOES NOT COVER: whether the caller's branch is CORRECT. It sees that the helper is used,
# not that the block is skipped on false - that is a reading job, and the route-level proof is a
# run with an unwritable /tmp (see tests/panel/ on the docs branch).

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

# The file that owns the helpers may create tempfiles; nothing else may.
OWNER='web/inc/helpers.php'

hits=$(grep -rn --include='*.php' -E '\b(exec|shell_exec|system|passthru|popen|proc_open)\s*\(\s*.{0,10}mktemp' web/ \
	| grep -v "^${OWNER}:" || true)

scanned=$(grep -rl --include='*.php' -E 'private_tmpdir|private_tmpfile|secret_tmpfile' web/ | wc -l)

if [ "$scanned" -eq 0 ]; then
	echo "[ FAIL ] no file in web/ uses a tempfile helper - the detection is broken, not the tree"
	echo "  (the helpers are defined in $OWNER; if they were renamed, rename them here too)"
	exit 2
fi

if [ -n "$hits" ]; then
	echo "$hits" | sed 's/^/  /'
	echo "[ FAIL ] $(echo "$hits" | wc -l) panel route(s) call mktemp directly"
	echo "  Use private_tmpdir() / private_tmpfile() / secret_tmpfile() from $OWNER and branch on false."
	exit 1
fi

echo "[ OK ] no panel route calls mktemp directly; $scanned file(s) use the helpers"
