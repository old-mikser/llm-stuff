#!/usr/bin/env python3
# Blocks Edit/Write/MultiEdit to source files when added text either:
#   (a) puts metadata inside a comment, or
#   (b) has a run of 4+ consecutive comment lines. Doc comments count too.
# Language-aware comment syntax. Reads hook JSON on stdin; exit 2 + stderr => fed back to Claude.
import json, re, sys, os

MAX_COMMENT_LINES = 3  # 4+ in a row is blocked

# style: line-comment prefixes, block (open, close)
STYLES = {
    "c":      (["///", "//!", "//"],      ("/*", "*/")),
    "c_hash": (["///", "//!", "//", "#"], ("/*", "*/")),
    "hash":   (["#"],                     None),
    "block":  ([],                        ("/*", "*/")),
    "html":   ([],                        ("<!--", "-->")),
}
EXT_STYLE = {
    ".rs": "c", ".js": "c", ".ts": "c", ".jsx": "c", ".tsx": "c", ".go": "c",
    ".php": "c_hash", ".py": "hash", ".css": "block", ".html": "html",
}
MARKERS = {
    "c":      r"(//|/\*|\*/|^\s*\*)",
    "c_hash": r"(//|/\*|\*/|^\s*\*|#)",
    "hash":   r"#",
    "block":  r"(/\*|\*/|^\s*\*)",
    "html":   r"(<!--|-->)",
}

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

ti = payload.get("tool_input") or {}
path = ti.get("file_path") or ""
ext = os.path.splitext(path)[1].lower()
style = EXT_STYLE.get(ext)
if style is None:
    sys.exit(0)

added = []
if ti.get("new_string"):
    added.append(ti["new_string"])
for e in ti.get("edits") or []:
    if e.get("new_string"):
        added.append(e["new_string"])
if ti.get("content"):
    added.append(ti["content"])
text = "\n".join(added)
if not text.strip():
    sys.exit(0)

lines = text.splitlines()
line_prefixes, block = STYLES[style]

# --- Check (a): metadata inside any comment line ---
marker = re.compile(MARKERS[style])
meta = re.compile(
    r"plan\s*#?\s*[0-9]{3,4}"
    r"|phase\s+[0-9]+"
    r"|wave\s+[0-9]+"
    r"|added in\b"
    r"|fixed (by|in)\b"
    r"|review fix"
    r"|see plan"
    r"|task\s*#?\s*[0-9]+"
    r"|[0-9]{4}-[0-9]{2}-[0-9]{2}",
    re.IGNORECASE,
)
meta_hits = [ln for ln in lines if marker.search(ln) and meta.search(ln)]

# --- Check (b): run of 4+ consecutive comment lines ---
in_block = False
run = 0
run_start = 0
long_runs = []

def flush(i):
    global run, run_start
    if run >= MAX_COMMENT_LINES + 1:
        long_runs.append((run_start + 1, lines[run_start:i]))
    run = 0

b_open = b_close = None
if block:
    b_open, b_close = block

for i, ln in enumerate(lines):
    s = ln.lstrip()
    is_comment = False
    if in_block:
        is_comment = True
        if b_close and b_close in ln:
            in_block = False
    else:
        if any(s.startswith(p) for p in line_prefixes):
            is_comment = True
        elif b_open and s.startswith(b_open):
            if b_close not in ln:
                in_block = True
            is_comment = True
    if is_comment:
        if run == 0:
            run_start = i
        run += 1
    else:
        flush(i)
flush(len(lines))

if not meta_hits and not long_runs:
    sys.exit(0)

if meta_hits:
    print(f"BLOCKED: comment metadata in {path} (AGENTS.md § Code comments policy).", file=sys.stderr)
    print("No dates, plan/phase/wave numbers, task IDs, or 'added in / fixed by / review fix' in code comments.", file=sys.stderr)
    for ln in meta_hits:
        print("  " + ln.strip(), file=sys.stderr)

if long_runs:
    print(f"BLOCKED: comment block over {MAX_COMMENT_LINES} lines in {path} (AGENTS.md § Code comments policy: write fewer comments).", file=sys.stderr)
    print("Cut it down. Doc comments are not exempt.", file=sys.stderr)
    for start, blk in long_runs:
        print(f"  lines {start}-{start + len(blk) - 1} ({len(blk)} comment lines):", file=sys.stderr)
        for ln in blk:
            print("    " + ln.strip(), file=sys.stderr)

print("Fix and redo the edit. History belongs in git and docs/plans/.", file=sys.stderr)
sys.exit(2)
