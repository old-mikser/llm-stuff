#!/usr/bin/env bash
# Tests for git-hooks-dispatch.sh. Each case builds a throwaway repo, installs the
# dispatcher the way core.hooksPath would, and runs it as git would. Run from
# anywhere:
#   tests/git-hooks-dispatch.test.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.claude/hooks" && pwd)"
export COMMENT_HOOK="$HOOKS/no-comment-metadata.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The global hooks dir core.hooksPath would point at.
GLOBAL="$WORK/global"
mkdir -p "$GLOBAL"
cp "$HOOKS/no-comment-metadata-precommit.sh" "$GLOBAL/"
for n in pre-commit post-commit commit-msg; do
    ln -s "$HOOKS/git-hooks-dispatch.sh" "$GLOBAL/$n"
done

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

new_repo() {
    rm -rf "$WORK/r"
    mkdir -p "$WORK/r"
    git -C "$WORK/r" init -q
    git -C "$WORK/r" config user.email t@t
    git -C "$WORK/r" config user.name t
    printf 'pub fn a() {}\n' >"$WORK/r/t.rs"
    git -C "$WORK/r" add -A
    git -C "$WORK/r" commit -qm base --no-verify
}

# A repo-local hook of its own, which core.hooksPath would otherwise shadow.
local_hook() { # name exit-code
    printf '#!/bin/sh\necho "$@" >"%s/ran-%s"\nexit %s\n' "$WORK" "$1" "$2" \
        >"$WORK/r/.git/hooks/$1"
    chmod +x "$WORK/r/.git/hooks/$1"
}

run() { # hook-name [args…] -> exit code
    local n="$1"
    shift
    (cd "$WORK/r" && "$GLOBAL/$n" "$@" >/dev/null 2>&1)
    echo $?
}

long_comment() {
    printf '// One.\n// Two.\n// Three.\npub fn n() {}\n' >"$WORK/r/new.rs"
    git -C "$WORK/r" add -A
}

# 1. The comment check still runs through the dispatcher.
new_repo
long_comment
check "pre-commit blocks a long comment" 1 "$(run pre-commit)"

# 2. A clean index passes when the repo has no hook of its own.
new_repo
printf 'pub fn b() {}\n' >>"$WORK/r/t.rs"
git -C "$WORK/r" add -A
check "clean change with no local hook" 0 "$(run pre-commit)"

# 3. The repo's own pre-commit still decides, after the global check passes.
new_repo
local_hook pre-commit 3
printf 'pub fn b() {}\n' >>"$WORK/r/t.rs"
git -C "$WORK/r" add -A
check "local pre-commit is chained" 3 "$(run pre-commit)"

# 4. A failed global check never reaches the local hook.
new_repo
local_hook pre-commit 0
rm -f "$WORK/ran-pre-commit"
long_comment
run pre-commit >/dev/null
[ -e "$WORK/ran-pre-commit" ] && got=ran || got=skipped
check "local hook skipped when the check fails" skipped "$got"

# 5. A hook name the global check knows nothing about is pure passthrough.
new_repo
local_hook post-commit 5
check "post-commit chains untouched" 5 "$(run post-commit)"

# 6. Arguments reach the local hook (commit-msg gets the message file).
new_repo
local_hook commit-msg 0
run commit-msg .git/COMMIT_EDITMSG >/dev/null
check "arguments are passed through" ".git/COMMIT_EDITMSG" "$(cat "$WORK/ran-commit-msg")"

# 7. A repo whose local hook is the dispatcher itself must not recurse.
new_repo
ln -sf "$HOOKS/git-hooks-dispatch.sh" "$WORK/r/.git/hooks/pre-commit"
printf 'pub fn b() {}\n' >>"$WORK/r/t.rs"
git -C "$WORK/r" add -A
check "self-symlink does not recurse" 0 "$(run pre-commit)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
