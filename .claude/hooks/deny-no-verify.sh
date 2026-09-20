#!/usr/bin/env python3
# PreToolUse hook (Bash): denies a command that would skip the repo's git hooks.
# The pre-commit layer is only worth having if it cannot be waved through, and
# --no-verify is one keystroke away once a commit gets rejected.
# Covers --no-verify / -n on commit, --no-verify on push, and git -c core.hooksPath=…
# Each pattern needs the command to run git, not merely to name a flag: writing the
# flag into a file or grepping for it is not a bypass.
# A human can still bypass it in their own terminal; this only binds the agent.
import json, re, sys

HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
SHELL = re.compile(r"\b(?:ba|z|k|da)?sh\b\s*(?:-\S+\s*)*$")


def strip_heredocs(cmd):
    """Command text with every heredoc body removed. A body is data the command
    reads, not a command being run, so a flag named inside one is not a bypass.
    A body piped into a shell is left in place, since that one does run."""
    out, lines = [], cmd.split("\n")
    i = 0
    while i < len(lines):
        m = HEREDOC.search(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        out.append(lines[i])
        runs = bool(SHELL.search(lines[i][:m.start()]))
        delim, j = m.group(2), i + 1
        while j < len(lines) and lines[j].strip() != delim:
            if runs:
                out.append(lines[j])
            j += 1
        i = j + 1
    return "\n".join(out)


try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if (payload.get("tool_name") or "") != "Bash":
    sys.exit(0)
cmd = (payload.get("tool_input") or {}).get("command") or ""
cmd = strip_heredocs(cmd)

PATTERNS = [
    (re.compile(r"\bgit\b[^|;&\n]*\bcommit\b[^|;&\n]*(?:--no-verify|\s-[a-z]*n[a-z]*(?=\s|$))"),
     "git commit --no-verify / -n"),
    (re.compile(r"\bgit\b[^|;&\n]*\bpush\b[^|;&\n]*--no-verify"), "git push --no-verify"),
    (re.compile(r"\bgit\b[^|;&\n]*-c\s*core\.hooksPath\s*="), "git -c core.hooksPath= override"),
]

for rx, what in PATTERNS:
    if rx.search(cmd):
        print(f"BLOCKED: {what} skips the repo's git hooks.", file=sys.stderr)
        print("The pre-commit comment check is not advisory. Fix what it reported and commit normally.", file=sys.stderr)
        print("If the check is wrong, say so and fix the hook — do not bypass it.", file=sys.stderr)
        sys.exit(2)
sys.exit(0)
