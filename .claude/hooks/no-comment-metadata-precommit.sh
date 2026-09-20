#!/usr/bin/env python3
# Git pre-commit hook: the end-state layer under no-comment-metadata.sh.
# The PreToolUse hook only sees Edit/Write payloads and heredocs redirected into a
# source file, so a script that opens the file itself (python3 - <<PY, sed -i) walks
# past it. This one reads what is actually staged, so it does not care how the text
# arrived — tool, script, subagent, worktree, or a session with no hooks at all.
# For each staged file it replays the staged content against the HEAD version through
# no-comment-metadata.sh as a Write payload, so the added-lines diff, the comment-run
# budget and the metadata patterns all come from that one file. There is no second
# copy of the rules here.
# Ambiguous metadata ("ask" in the tool hook) has no prompt channel at commit time,
# so it prints as a warning and does not block. Exit 1 fails the commit.
# Escape hatch for a human: COMMENT_GUARD_SKIP=1 git commit …
import json, os, subprocess, sys, tempfile

MAX_BYTES = 2_000_000

if os.environ.get("COMMENT_GUARD_SKIP"):
    sys.exit(0)


def hook_path():
    env = os.environ.get("COMMENT_HOOK")
    if env:
        return env
    sibling = os.path.join(os.path.dirname(os.path.abspath(__file__)), "no-comment-metadata.sh")
    if os.path.exists(sibling):
        return sibling
    return os.path.expanduser("~/.claude/hooks/no-comment-metadata.sh")


HOOK = hook_path()
if not os.path.exists(HOOK):
    sys.exit(0)


def git(*args, binary=False):
    r = subprocess.run(["git"] + list(args), capture_output=True)
    if r.returncode != 0:
        return None
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


staged = git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z")
if not staged:
    sys.exit(0)
paths = [p for p in staged.split("\0") if p]

blocked, warned = [], []
with tempfile.TemporaryDirectory() as work:
    for n, path in enumerate(paths):
        new = git("show", f":{path}", binary=True)
        if new is None or len(new) > MAX_BYTES or b"\0" in new[:8192]:
            continue
        old = git("show", f"HEAD:{path}", binary=True) or b""
        d = os.path.join(work, str(n))
        os.mkdir(d)
        tmp = os.path.join(d, os.path.basename(path))
        with open(tmp, "wb") as f:
            f.write(old)
        payload = {"tool_name": "Write",
                   "tool_input": {"file_path": tmp, "content": new.decode("utf-8", "replace")}}
        r = subprocess.run([sys.executable, HOOK], input=json.dumps(payload),
                           capture_output=True, text=True)
        if r.returncode == 2:
            blocked.append((r.stdout + r.stderr).replace(tmp, path))
        elif r.stdout.strip():
            try:
                reason = json.loads(r.stdout)["hookSpecificOutput"]["permissionDecisionReason"]
            except Exception:
                reason = r.stdout.strip()
            warned.append(f"{path}:\n{reason}")

for w in warned:
    print("WARNING: " + w, file=sys.stderr)

if blocked:
    for b in blocked:
        sys.stderr.write(b.replace("The edit was NOT applied. Trim the comments and retry.", "").rstrip() + "\n")
    print("\nCOMMIT REJECTED. Rewrite the comments above, restage, and commit again.", file=sys.stderr)
    print("Nothing was committed. Do not pass --no-verify.", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
