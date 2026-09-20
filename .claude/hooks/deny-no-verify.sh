#!/usr/bin/env python3
# PreToolUse hook (Bash): denies a command that would skip the repo's git hooks.
# The pre-commit layer is only worth having if it cannot be waved through, and
# --no-verify is one keystroke away once a commit gets rejected.
# Covers --no-verify / -n on commit, --no-verify on push, and -c core.hooksPath=…
# A human can still bypass it in their own terminal; this only binds the agent.
import json, re, sys

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if (payload.get("tool_name") or "") != "Bash":
    sys.exit(0)
cmd = (payload.get("tool_input") or {}).get("command") or ""

PATTERNS = [
    (re.compile(r"\bgit\b[^|;&\n]*\bcommit\b[^|;&\n]*(?:--no-verify|\s-[a-z]*n[a-z]*(?=\s|$))"),
     "git commit --no-verify / -n"),
    (re.compile(r"\bgit\b[^|;&\n]*\bpush\b[^|;&\n]*--no-verify"), "git push --no-verify"),
    (re.compile(r"core\.hooksPath"), "core.hooksPath override"),
]

for rx, what in PATTERNS:
    if rx.search(cmd):
        print(f"BLOCKED: {what} skips the repo's git hooks.", file=sys.stderr)
        print("The pre-commit comment check is not advisory. Fix what it reported and commit normally.", file=sys.stderr)
        print("If the check is wrong, say so and fix the hook — do not bypass it.", file=sys.stderr)
        sys.exit(2)
sys.exit(0)
