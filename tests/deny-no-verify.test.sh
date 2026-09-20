#!/usr/bin/env bash
# Tests for deny-no-verify.sh. Feeds the hook Bash payloads and records the verdict.
#   tests/deny-no-verify.test.sh
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.claude/hooks" && pwd)/deny-no-verify.sh"

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

verdict() { # command -> allow | block
    local rc
    python3 - "$1" <<'EOF' | python3 "$HOOK" >/dev/null 2>&1
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))
EOF
    rc=${PIPESTATUS[1]}
    [ "$rc" -eq 2 ] && echo block || echo allow
}

check "commit --no-verify"        block "$(verdict 'git commit --no-verify -m "x"')"
check "commit -n"                 block "$(verdict 'git commit -n -m "x"')"
check "commit -nm"                block "$(verdict 'git commit -nm "x"')"
check "push --no-verify"          block "$(verdict 'git push --no-verify origin main')"
check "core.hooksPath override"   block "$(verdict 'git -c core.hooksPath=/dev/null commit -m "x"')"
check "plain commit"              allow "$(verdict 'git commit -m "fix: thing"')"
check "commit -am"                allow "$(verdict 'git commit -am "fix: thing"')"
check "grep for the flag"         allow "$(verdict 'grep -rn no-verify .')"
check "unrelated -n"              allow "$(verdict 'sort -n nums.txt')"
check "commit message says none"  allow "$(verdict 'git commit -m "none of the pools"')"
check "prose naming the flag"    allow "$(verdict 'echo core.hooksPath >notes.md')"
check "git config read"           allow "$(verdict 'git config core.hooksPath')"

# A heredoc body is data the command reads, not a command being run.
doc_case() { printf 'python3 - <<%s\n%s\nEOF\n' "'EOF'" "$1"; }
check "flag inside a heredoc body"   allow "$(verdict "$(doc_case 'print("git push --no-verify")')")"
check "heredoc piped into bash"      block "$(verdict "$(printf 'bash <<%s\ngit commit --no-verify -m x\nEOF\n' "'EOF'")")"
check "flag after a heredoc"         block "$(verdict "$(printf 'cat <<%s >f\nplain text\nEOF\ngit commit --no-verify -m x\n' "'EOF'")")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
