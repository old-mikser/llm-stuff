#!/usr/bin/env python3
# PreToolUse hook: blocks Edit/Write/MultiEdit to source files when the change
#   (a) puts metadata inside a comment, or
#   (b) would leave a run of 4+ consecutive comment lines. Doc comments count too.
# Two softer signals only ask: ambiguous metadata (bare IDs, changelog voice) can't
# be told from real code talk by pattern alone, and a 2-3 line comment sitting on a
# one-line statement may still be earning its keep.
# The edit is simulated against the on-disk file, so added lines landing next to
# existing comment lines are counted together; only runs the edit touches are
# flagged, never pre-existing ones elsewhere in the file.
# Language-aware comment syntax. Reads hook JSON on stdin; exit 2 + stderr => fed back to Claude.
import bisect, json, os, re, sys

MAX_COMMENT_LINES = 3  # 4+ in a row is blocked
BLOCK_EXTENT = 3  # code shorter than this is a one-liner: 1 comment line is enough

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
# Tier 1: keyword-anchored, unambiguous => hard block.
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
# Tier 2: could equally be a bitmask, an opcode or plain prose => ask, never block.
suspect = re.compile(
    r"\(\s*#?\s*[0-9]{4}\s*\)"  # bare parenthesised ID: "cleared it (0010)"
    r"|\b(?:clear|remov|renam|bump|drop|mov|switch|replac|updat|delet|revert|split)ed"
    r"\s+(?:it|this|that|these|those|them)\b",
    re.IGNORECASE,
)
# A date in a URL or a spec version is describing the code, not stamping it.
url = re.compile(r"\S+://\S+|\b\w+\.(?:io|com|org|net|dev)/\S*")
spec_date = re.compile(r"\b(?:spec|version|rev|rfc|standard)\w*\s+[0-9]{4}-[0-9]{2}-[0-9]{2}", re.I)


def scrub(ln):
    return spec_date.sub("", url.sub("", ln))


added_comment_lines = [
    ln for t in added_texts for ln in t.splitlines() if marker.search(ln)
]
meta_hits = [ln for ln in added_comment_lines if meta.search(scrub(ln))]
suspect_hits = [
    ln for ln in added_comment_lines
    if ln not in meta_hits and (suspect.search(ln) or spec_date.search(ln))
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
touched_runs = []

def flush(i):
    global run
    if run and any(j in added_lines for j in range(run_start, i)):
        touched_runs.append((run_start, i))
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

long_runs = [(s + 1, lines[s:e]) for s, e in touched_runs if e - s > MAX_COMMENT_LINES]

# --- Check (c): multi-line comment on a one-liner ---
# Heuristic, so it only ever asks. Every ambiguous case gets the larger budget:
# a declaration, a blank-line gap (section header), a doc comment or no target
# at all is left alone, and only a run sitting on a short statement is queried.
DECL = re.compile(
    r"^(?:(?:pub|pub\(\w+\)|export|default|async|static|final|abstract|public|private"
    r"|protected|const|unsafe|extern|inline|virtual|override)\s+)*"
    r"(?:fn|def|class|impl|trait|struct|enum|interface|type|func|function|module"
    r"|namespace|record|union|macro_rules!)\b"
)
ATTR = re.compile(r"^(?:#!?\[|@\w|[)\]}])")
DOC = ("///", "//!", "/**")


def strip_noise(ln):
    ln = re.sub(r"'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\"", "", ln)
    for p in line_prefixes:
        k = ln.find(p)
        if k >= 0:
            ln = ln[:k]
    return ln


def indent_of(ln):
    return len(ln) - len(ln.lstrip())


def find_target(end):
    """First code line the run introduces, and whether a blank line separates them."""
    gap = False
    for i in range(end, len(lines)):
        s = lines[i].strip()
        if not s:
            gap = True
        elif ATTR.match(s):
            continue
        else:
            return i, gap
    return None, gap


def extent(i):
    """Non-blank lines spanned by the statement starting at line i."""
    base = indent_of(lines[i])
    depth = sum(strip_noise(lines[i]).count(c) for c in "([{")
    depth -= sum(strip_noise(lines[i]).count(c) for c in ")]}")
    n, j = 1, i + 1
    while j < len(lines):
        s = lines[j].strip()
        if not s:
            if depth <= 0:
                break
        elif depth > 0:
            n += 1
            depth += sum(strip_noise(lines[j]).count(c) for c in "([{")
            depth -= sum(strip_noise(lines[j]).count(c) for c in ")]}")
        elif indent_of(lines[j]) > base:
            n += 1
        else:
            break
        j += 1
    return n


oversized = []
for s, e in touched_runs:
    if not 2 <= e - s <= MAX_COMMENT_LINES:
        continue
    if lines[s].lstrip().startswith(DOC):
        continue
    t, gap = find_target(e)
    if t is None or gap or DECL.match(lines[t].lstrip()):
        continue
    if extent(t) < BLOCK_EXTENT:
        oversized.append((s + 1, lines[s:e], t + 1, lines[t].strip()))

if not meta_hits and not long_runs:
    reasons = []
    if suspect_hits:
        r = "Possible metadata stamp in a comment (AGENTS.md § Code comments policy):\n"
        r += "\n".join("  " + ln.strip() for ln in suspect_hits)
        r += "\nAllow if the comment describes the code; reject if it records the change."
        reasons.append(r)
    for start, blk, tline, target in oversized:
        r = f"{len(blk)} comment lines on what looks like a one-liner "
        r += "(AGENTS.md § Code comments policy: write fewer comments).\n"
        r += "\n".join("  " + ln.strip() for ln in blk)
        r += f"\n  line {tline}: {target}\n"
        r += "Allow if the code is genuinely subtle; reject and cut it to one line if not."
        reasons.append(r)
    if reasons:
        json.dump({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": "\n\n".join(reasons),
        }}, sys.stdout)
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
