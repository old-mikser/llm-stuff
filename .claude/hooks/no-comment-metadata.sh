#!/usr/bin/env python3
# PreToolUse hook: blocks Edit/Write/MultiEdit to source files when the change
#   (a) puts metadata inside a comment, or
#   (b) would leave a run of 4+ consecutive comment lines. Doc comments count too.
# The edit is simulated against the on-disk file, so added lines landing next to
# existing comment lines are counted together; only runs the edit touches are
# flagged, never pre-existing ones elsewhere in the file.
# Language-aware comment syntax. Reads hook JSON on stdin; exit 2 + stderr => fed back to Claude.
import bisect, json, os, re, sys

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


def apply_edit(text, old, new, replace_all, spans):
    """Splice new over old in text. Returns (text, spans) where spans are
    (start, end) char ranges of added text, remapped through this edit."""
    if not old:
        return text, spans
    hits = []
    i = text.find(old)
    while i >= 0:
        hits.append(i)
        if not replace_all:
            break
        i = text.find(old, i + len(old))
    if not hits:
        return text, spans
    parts, result_spans, prev, shift = [], [], 0, 0
    for h in hits:
        parts.append(text[prev:h])
        result_spans.append((h + shift, h + shift + len(new)))
        parts.append(new)
        prev = h + len(old)
        shift += len(new) - len(old)
    parts.append(text[prev:])
    remapped = []
    for s, e in spans:
        d, dead = 0, False
        for h in hits:
            he = h + len(old)
            if he <= s:
                d += len(new) - len(old)
            elif h >= e:
                pass
            else:
                dead = True  # span overlaps a replaced region; result_spans covers it
                break
        if not dead:
            remapped.append((s + d, e + d))
    return "".join(parts), remapped + result_spans


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

if "content" in ti:  # Write: content is the whole resulting file
    added_texts = [ti.get("content") or ""]
    text = added_texts[0]
    spans = [(0, len(text))]
else:  # Edit / MultiEdit
    edits = ti.get("edits") or ([ti] if ti.get("old_string") or ti.get("new_string") else [])
    added_texts = [e.get("new_string") or "" for e in edits]
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        spans = []
        for e in edits:
            text, spans = apply_edit(
                text, e.get("old_string") or "", e.get("new_string") or "",
                bool(e.get("replace_all")), spans,
            )
    except OSError:  # new file or unreadable: check the added text in isolation
        text = "\n".join(added_texts)
        spans = [(0, len(text))]

if not text.strip():
    sys.exit(0)

# --- Check (a): metadata inside any added comment line ---
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
meta_hits = [
    ln for t in added_texts for ln in t.splitlines()
    if marker.search(ln) and meta.search(ln)
]

# --- Check (b): run of 4+ consecutive comment lines touching the edit ---
lines = text.split("\n")
starts, off = [], 0
for ln in lines:
    starts.append(off)
    off += len(ln) + 1

added_lines = set()
for s, e in spans:
    a = bisect.bisect_right(starts, s) - 1
    b = bisect.bisect_right(starts, max(s, e - 1)) - 1
    added_lines.update(range(a, b + 1))

line_prefixes, block = STYLES[style]
b_open, b_close = block if block else (None, None)
in_block = False
run = 0
run_start = 0
long_runs = []

def flush(i):
    global run
    if run >= MAX_COMMENT_LINES + 1 and any(j in added_lines for j in range(run_start, i)):
        long_runs.append((run_start + 1, lines[run_start:i]))
    run = 0

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
            if b_close not in ln[ln.find(b_open) + len(b_open):]:
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
    print(f"BLOCKED: this edit would leave a comment run over {MAX_COMMENT_LINES} lines in {path} (AGENTS.md § Code comments policy: write fewer comments).", file=sys.stderr)
    print("Counting adjacent existing comment lines too. Cut it down. Doc comments are not exempt.", file=sys.stderr)
    for start, blk in long_runs:
        print(f"  lines {start}-{start + len(blk) - 1} ({len(blk)} comment lines):", file=sys.stderr)
        for ln in blk:
            print("    " + ln.strip(), file=sys.stderr)

print("The edit was NOT applied. Trim the comments and retry.", file=sys.stderr)
sys.exit(2)
