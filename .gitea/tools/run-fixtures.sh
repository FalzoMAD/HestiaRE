#!/bin/bash
# Behaviour fixtures: each builds a throwaway CONF_DIR, pulls the function under test out of the
# checkout and asserts. No box, no install, no network - so the gate can run them on every PR.
# A defect that needs two colliding domains or two customers is otherwise only ever found by hand.
set -u
cd "$(dirname "$0")/fixtures" || exit 1
rc=0
for t in *.sh; do
	if out=$(bash "./$t" 2>&1); then
		printf '   PASS  %s\n' "$t"
	else
		printf '   FAIL  %s\n' "$t"
		printf '%s\n' "$out" | sed 's/^/         /'
		rc=1
	fi
done
exit "$rc"
