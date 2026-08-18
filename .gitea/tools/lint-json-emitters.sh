#!/bin/bash
# HestiaRE JSON emitter check (#704). Read-only; rewrites nothing.
#
# The h-* commands build their JSON output by string concatenation - a value is spliced straight
# into a string literal. A value carrying a " or a backslash then produces a document the panel
# cannot json_decode. Same class as upstream #5585 at the certificate listers. So every spliced
# value must first pass through json_escape (include/main.sh), one call per emitting function,
# naming what that function splices.
#
# That name list is exactly the thing that goes stale: add a field to a lister, forget the name,
# and the guard stays green while covering less. So this check derives BOTH sides from the source
# - the spliced names from the emitted text, the covered names from the json_escape calls - and
# reports the difference. Nothing is hard-coded per file.
#
# An empty reference set FAILS: finding no emitter at all means the detection broke, not that the
# tree is clean.
#
# It looks at three splice shapes, because the tree uses all three and the first version of this
# check saw only the first - a guard that covers a third of the problem while reading as whole:
#   A   "'$VAR'"  /  "'"$VAR"'"      value spliced into a single-quoted JSON block
#   B   \"$VAR\"                     value spliced into a double-quoted echo -e line
#   C   printf '..."%s"...' "$var"   value passed as a %s argument inside a JSON literal
#
# Two things it has to do to keep that reach, both learned the hard way here: join backslash
# continuations (printf arguments live on the next line), and report a command substitution under
# a name no json_escape call can cover, because there is nothing to escape in place - it has to be
# assigned to a variable first.
#
# LOCAL / MANUAL, not a CI gate - it needs python3, and the Gitea runner host is kept to
# git + shellcheck + shfmt with no language runtime (same reason as lint-codemap.sh). Run it when
# you touch an h-list-* emitter.
#
# WHAT IT DOES NOT COVER, deliberately:
#   - JSON assembled into a variable instead of printed (the ACME payloads in h-add-letsencrypt-*).
#     Those carry protocol values, not record values, and never reach the panel decoder.
#   - Whether json_escape itself is correct. That is a unit question, not a coverage one.
#   - The panel's own JSON output (web/): PHP has json_encode and uses it.
#   - A value escaped into a differently named copy is credited to the copy, not to the original -
#     that is the intended shape when the raw value is still needed afterwards.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

if ! command -v python3 > /dev/null 2>&1; then
	echo "[ FAIL ] python3 required (this check is local/manual, like lint-codemap.sh)"
	exit 2
fi

exec python3 - "$@" << 'PY'
import glob
import re
import sys

# An emitting region: a json_list() body, or a top-level block that prints a JSON object itself.
FUNC = re.compile(r"^(json_list|json_list_[a-z_]+)\(\)\s*\{")
ESCAPE = re.compile(r"^\s*json_escape\s+(.+?)\s*$")
STMT = re.compile(r"^\s*(echo|printf)(\s|$)")
NAME = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")

# A  region: "'...'"  - the emitted quote, then shell-quoted splice, then the emitted quote.
REGION_A = re.compile(r"\"'[^']*'\"")

# A command substitution cannot be escaped in place, so it has to be named first. Reported under
# this pseudo-name, which no json_escape call can ever cover - that is the point.
SUBST = "<command substitution>"


def splices_a(line):
    out = []
    for m in REGION_A.finditer(line):
        if "$(" in m.group(0):
            out.append(SUBST)
        for n in NAME.finditer(m.group(0)):
            out.append(n.group(1))
    return out


def splices_b(line):
    """Expansions sitting at an odd count of \\" - i.e. inside an emitted string literal."""
    out = []
    depth = 0
    i = 0
    while i < len(line):
        if line.startswith('\\"', i):
            depth += 1
            i += 2
            continue
        if line.startswith("$(", i) and depth % 2 == 1:
            out.append(SUBST)
            i += 2
            continue
        if line[i] == "$" and depth % 2 == 1:
            m = NAME.match(line, i)
            if m:
                out.append(m.group(1))
                i = m.end()
                continue
        i += 1
    return out


PRINTF = re.compile(r"""^\s*printf\s+(?:'([^']*)'|"((?:[^"\\\\]|\\\\.)*)")(.*)$""")


def splices_c(line):
    """printf whose format carries "%s": every argument lands inside a JSON string literal.

    Every argument is reported, not only the ones a quoted %s consumes - mapping positions to
    conversions exactly would be a second parser, and escaping an argument that did not need it
    is a no-op. A command substitution among them is reported as such: it has no name to escape.
    """
    m = PRINTF.match(line)
    if not m:
        return []
    fmt = m.group(1) if m.group(1) is not None else m.group(2)
    args = m.group(3)
    if '"%s"' not in fmt and '\\"%s\\"' not in fmt:
        return []
    out = [SUBST] if "$(" in args else []
    out += [x.group(1) for x in NAME.finditer(args)]
    return out


findings = []
emitters = 0

for path in sorted(glob.glob("bin/h-*")):
    try:
        lines = open(path).read().split("\n")
    except (OSError, UnicodeDecodeError):
        continue
    # Regions to inspect: every json_list-ish function body, by brace depth.
    regions = []
    i = 0
    while i < len(lines):
        if FUNC.match(lines[i]):
            depth = 0
            j = i
            while j < len(lines):
                depth += lines[j].count("{") - lines[j].count("}")
                if depth <= 0 and j > i:
                    break
                j += 1
            regions.append((i, j))
            i = j
        i += 1
    # Plus top-level statements that splice shape A - the two commands that print JSON without a
    # json_list wrapper would otherwise be invisible here.
    covered_file = set()
    for n, line in enumerate(lines):
        m = ESCAPE.match(line)
        if m:
            covered_file.update(m.group(1).split())
    extra = []
    for n, line in enumerate(lines):
        if not splices_a(line) or any(a <= n <= b for a, b in regions):
            continue
        # Only a splice that belongs to an echo/printf statement counts. Walking back to the
        # statement start separates the two: an assignment builds a string (the ACME payloads
        # in h-add-letsencrypt-*, which never reach the panel decoder), an echo prints JSON.
        m = n
        while m >= 0 and not STMT.match(lines[m]):
            if re.match(r"^\s*[A-Za-z_][A-Za-z0-9_]*\+?=", lines[m]):
                m = -1
                break
            m -= 1
        if m >= 0:
            extra.append((m, n))
    top_level = set()
    for a, b in extra:
        top_level.add(len(regions))
        regions.append((a, b))

    for ri, (a, b) in enumerate(regions):
        emitters += 1
        # A top-level emitter has no function to hold its json_escape call, so the whole file's
        # calls count for it.
        covered = set(covered_file) if ri in top_level else set()
        spliced = {}
        stmt = None
        for n in range(max(a, 0), min(b + 1, len(lines))):
            line = lines[n]
            # A backslash-continued statement is one logical line: printf arguments often sit on
            # the next one, and reading only the first would hide every value it splices.
            k = n
            while line.rstrip().endswith("\\") and k + 1 < len(lines):
                k += 1
                line = line.rstrip()[:-1] + " " + lines[k].strip()
            m = ESCAPE.match(line)
            if m:
                covered.update(m.group(1).split())
                continue
            if STMT.match(line):
                stmt = n
            if stmt is None:
                continue
            for name in splices_a(line) + splices_b(line) + splices_c(line):
                spliced.setdefault(name, n + 1)
        for name, ln in sorted(spliced.items(), key=lambda kv: kv[1]):
            if name == SUBST:
                findings.append(f"{path}:{ln}: a command substitution is spliced into JSON - assign it to a variable and escape that")
            elif name not in covered:
                findings.append(f"{path}:{ln}: {name} is spliced into JSON but never passed to json_escape")

seen = set()
findings = [f for f in findings if not (f in seen or seen.add(f))]
for f in findings:
    print(f)

if emitters == 0:
    print("[ FAIL ] no JSON emitter found in bin/ - the detection is broken, not the tree")
    sys.exit(2)
if findings:
    print(f"[ FAIL ] {len(findings)} unescaped splice(s) across {emitters} JSON emitter(s) in bin/")
    print("  Add the name to the json_escape call inside the emitting function.")
    sys.exit(1)
print(f"[ OK ] {emitters} JSON emitter(s) in bin/, every spliced value escaped")
PY
