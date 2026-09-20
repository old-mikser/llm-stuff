#!/usr/bin/env bash
# Tests for no-comment-metadata-precommit.sh. Each case builds a throwaway git repo,
# stages a change, runs the hook as git would, and records the verdict. Run from
# anywhere:
#   tests/no-comment-metadata-precommit.test.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.claude/hooks" && pwd)"
HOOK="$HOOKS/no-comment-metadata-precommit.sh"
export COMMENT_HOOK="$HOOKS/no-comment-metadata.sh"
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

# A repo whose HEAD holds t.rs with a long doc comment already in it: the pre-existing
# run must never be what fails a later commit.
new_repo() {
    rm -rf "$WORK/r"
    mkdir -p "$WORK/r"
    git -C "$WORK/r" init -q
    git -C "$WORK/r" config user.email t@t
    git -C "$WORK/r" config user.name t
    cat >"$WORK/r/t.rs" <<'EOF'
/// One.
/// Two.
/// Three.
/// Four.
pub fn kept() -> u32 {
    let a = 1;
    a
}

pub fn prune(n: u32) -> u32 {
    n
}
EOF
    git -C "$WORK/r" add -A
    git -C "$WORK/r" commit -qm base --no-verify
}

verdict() { # -> allow | block
    local rc
    (cd "$WORK/r" && python3 "$HOOK" >/dev/null 2>&1)
    rc=$?
    [ "$rc" -eq 0 ] && echo allow || echo block
}

stage() { git -C "$WORK/r" add -A; }

# 1. The live case: a six-line doc comment authored by a script, not by Edit.
new_repo
python3 - "$WORK/r/t.rs" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("pub fn prune(n: u32) -> u32 {", """/// Split in two so the writer never pays for the search: a reader connection
/// walks `ix_competitor_txs_block` for up to [`PRUNE_SCAN_ROWS`] expired
/// hashes, then the writer deletes them [`PRUNE_CHUNK_ROWS`] at a time as
/// primary-key seeks, released between batches. Running the scan inside the
/// delete instead cost a fixed ~2 s per writer acquisition on the live DB,
/// which no batch size can bring under the other writers' `busy_timeout`.
pub fn prune(n: u32) -> u32 {""")
open(p, "w").write(s)
EOF
stage
check "six-line doc comment added by a script" block "$(verdict)"

# 2. A mechanical sweep past the same pre-existing long comment.
new_repo
sed -i 's/\bkept\b/retained/g' "$WORK/r/t.rs"
stage
check "rename sweep beside an existing long comment" allow "$(verdict)"

# 3. Two added comment lines are within budget.
new_repo
printf '\n// Fine.\n// Still fine.\npub fn ok() {}\n' >>"$WORK/r/t.rs"
stage
check "two added comment lines" allow "$(verdict)"

# 4. A brand new file: every line is new, so the run counts.
new_repo
printf '// One.\n// Two.\n// Three.\npub fn n() {}\n' >"$WORK/r/new.rs"
stage
check "three comment lines in a new file" block "$(verdict)"

# 5. Metadata in an added comment, short enough to clear the run budget.
new_repo
printf '\n// See plan 0293 for why.\npub fn m() {}\n' >>"$WORK/r/t.rs"
stage
check "metadata stamp in an added comment" block "$(verdict)"

# 6. A file type the hook does not police.
new_repo
printf '# One\n# Two\n# Three\n# Four\n' >"$WORK/r/notes.md"
stage
check "markdown is not policed" allow "$(verdict)"

# 7. The human escape hatch.
new_repo
printf '// One.\n// Two.\n// Three.\npub fn n() {}\n' >"$WORK/r/new.rs"
stage
rc_out="$(cd "$WORK/r" && COMMENT_GUARD_SKIP=1 python3 "$HOOK" >/dev/null 2>&1; echo $?)"
check "COMMENT_GUARD_SKIP bypasses" 0 "$rc_out"

# 8. Nothing staged at all.
new_repo
check "empty index" allow "$(verdict)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
