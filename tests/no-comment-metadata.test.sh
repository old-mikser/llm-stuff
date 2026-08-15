#!/usr/bin/env bash
# Tests for no-comment-metadata.sh. Each case builds a small file on disk, feeds
# the hook an Edit/Write payload against it, and records the verdict. Run from
# anywhere:
#   tests/no-comment-metadata.test.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.claude/hooks" && pwd)"
HOOK="$HOOKS/no-comment-metadata.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

check() {
    local name="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
        pass=$((pass + 1))
        printf 'ok   %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL %s\n       want: %s\n       got:  %s\n' "$name" "$want" "$got"
    fi
}

# The file every edit is applied to, unless a case overwrites it.
reset_file() {
    printf 'fn main() {\n    let a = 1;\n}\n' >"$WORK/t.rs"
}

verdict() { # payload-json -> allow | ask | block
    local out rc
    out="$(printf '%s' "$1" | python3 "$HOOK" 2>/dev/null)"
    rc=$?
    if [ "$rc" -eq 2 ]; then
        echo block
    elif [ -n "$out" ]; then
        echo ask
    else
        echo allow
    fi
}

edit() { # new_string [old_string] [path] -> verdict
    python3 - "$1" "${2:-    let a = 1;}" "${3:-$WORK/t.rs}" <<'PY' | { read -r payload; verdict "$payload"; }
import json, sys
print(json.dumps({"tool_input": {
    "file_path": sys.argv[3], "old_string": sys.argv[2], "new_string": sys.argv[1],
}}))
PY
}

write() { # content [path] -> verdict
    python3 - "$1" "${2:-$WORK/t.rs}" <<'PY' | { read -r payload; verdict "$payload"; }
import json, sys
print(json.dumps({"tool_input": {"file_path": sys.argv[2], "content": sys.argv[1]}}))
PY
}

reset_file

# --- check (c): comment budget on a one-liner -------------------------------
# 3 lines on a plain short statement is the whole rule. 1-2 lines stay allowed,
# and the exemptions below are what keep it from firing on ordinary code.

check "1 comment line on a one-liner" "allow" "$(edit '    // recompute the offset
    let a = 1;')"
check "2 comment lines on a one-liner" "allow" "$(edit '    // recompute the offset
    // because the header moved
    let a = 1;')"
check "3 comment lines on a one-liner" "block" "$(edit '    // recompute the offset
    // because the header moved
    // and the caller assumes it
    let a = 1;')"
check "3 lines on a declaration" "allow" "$(edit '    // recompute the offset
    // because the header moved
    // and the caller assumes it
    fn helper() {}')"
check "3 lines on a pub async declaration" "allow" "$(edit '    // recompute the offset
    // because the header moved
    // and the caller assumes it
    pub async fn helper() {}')"
check "3 lines with a blank gap is a section header" "allow" "$(edit '    // recompute the offset
    // because the header moved
    // and the caller assumes it

    let a = 1;')"
check "3 doc lines are exempt" "allow" "$(edit '    /// recompute the offset
    /// because the header moved
    /// and the caller assumes it
    let a = 1;')"
check "3 lines through an attribute onto a declaration" "allow" "$(edit '    // recompute the offset
    // because the header moved
    // and the caller assumes it
    #[inline]
    fn helper() {}')"
check "3 lines on a statement with a real body" "allow" "$(edit '    // recompute the offset
    // because the header moved
    // and the caller assumes it
    if a > 0 {
        println!("hi");
        return;
    }')"
check "3 lines commenting nothing at end of file" "allow" "$(edit '    let a = 1;
}
// recompute the offset
// because the header moved
// and the caller assumes it' '    let a = 1;
}')"

# --- check (b): runs over the budget ----------------------------------------

check "4 comment lines anywhere" "block" "$(edit '    // one
    // two
    // three
    // four
    let a = 1;')"
check "4 doc lines are not exempt" "block" "$(edit '    /// one
    /// two
    /// three
    /// four
    let a = 1;')"

# Adjacency counts: two added lines landing on an existing pair make a run of 4.
printf 'fn main() {\n    // existing one\n    // existing two\n    let a = 1;\n}\n' >"$WORK/adj.rs"
check "added lines merge with an existing comment run" "block" \
    "$(edit '    // added three
    // added four
    let a = 1;' '    let a = 1;' "$WORK/adj.rs")"

# --- check (a): metadata in a comment ---------------------------------------

check "a date stamp" "block" "$(edit '    // 2026-08-15 rewrite
    let a = 1;')"
check "a phase number" "block" "$(edit '    // phase 2 cleanup
    let a = 1;')"
check "added in" "block" "$(edit '    // added in the refactor
    let a = 1;')"
check "a date inside a URL describes the code" "allow" \
    "$(edit '    // see https://example.com/posts/2026-08-15/parser
    let a = 1;')"
check "a date inside a string literal is not a comment" "allow" \
    "$(edit '    let a = "2026-08-15";')"
check "a spec version only asks" "ask" "$(edit '    // matches spec 2026-08-15
    let a = 1;')"
check "changelog voice only asks" "ask" "$(edit '    // cleared it because the header moved
    let a = 1;')"
check "a block beats an ask when both fire" "block" "$(edit '    // phase 2 cleanup
    // cleared it because the header moved
    let a = 1;')"

# --- scope ------------------------------------------------------------------

check "an unknown extension is ignored" "allow" \
    "$(edit '    // phase 2 cleanup
    let a = 1;' '    let a = 1;' "$WORK/t.txt")"
check "python uses hash comments" "block" \
    "$(printf 'def main():\n    a = 1\n' >"$WORK/t.py"; edit '    # phase 2 cleanup
    a = 1' '    a = 1' "$WORK/t.py")"

# A Write is diffed against what is on disk, so untouched lines do not count.
printf 'fn main() {\n    // phase 2 cleanup\n    let a = 1;\n}\n' >"$WORK/pre.rs"
check "Write leaves pre-existing metadata alone" "allow" \
    "$(write 'fn main() {
    // phase 2 cleanup
    let a = 1;
    let b = 2;
}' "$WORK/pre.rs")"
check "Write catches newly added metadata" "block" \
    "$(write 'fn main() {
    // phase 2 cleanup
    let a = 1;
    // phase 3 cleanup
    let b = 2;
}' "$WORK/pre.rs")"

# --- malformed input --------------------------------------------------------

check "garbage on stdin is allowed" "allow" "$(verdict 'not json at all')"
check "an empty payload is allowed" "allow" "$(verdict '{}')"
check "an empty edit is allowed" "allow" "$(edit '' '    let a = 1;')"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
