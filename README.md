# llm-stuff

Personal Claude Code configuration — hooks I reuse across machines.

Everything lives under [`.claude/hooks/`](.claude/hooks/). Five hooks are included:

| Hook | Event | What it does |
|------|-------|--------------|
| [`notify-done.sh`](.claude/hooks/notify-done.sh) | `Stop` | Plays a soft completion chime when Claude finishes a turn — by default staying quiet while background agents are still running. |
| [`notify-ask.sh`](.claude/hooks/notify-ask.sh) | `Notification`, `PreToolUse` (AskUserQuestion) | Plays a two-blip attention chime when Claude is waiting on *you* — a permission prompt or an a) b) c) question. |
| [`no-comment-metadata.sh`](.claude/hooks/no-comment-metadata.sh) | `PreToolUse` (Edit/Write/MultiEdit/Bash) | Blocks edits that put metadata in comments or add long comment blocks, including heredocs written through Bash; asks on ambiguous metadata. |
| [`no-comment-metadata-precommit.sh`](.claude/hooks/no-comment-metadata-precommit.sh) | git `pre-commit` | Re-runs the same comment checks over what is actually staged, so a change that reached the file by script instead of by tool is still caught. |
| [`deny-no-verify.sh`](.claude/hooks/deny-no-verify.sh) | `PreToolUse` (Bash) | Denies `git commit --no-verify`, `git push --no-verify` and `core.hooksPath` overrides, so the pre-commit layer cannot be waved through. |

## Install

```bash
# 1. Copy the hooks into your Claude config
mkdir -p ~/.claude/hooks
cp .claude/hooks/* ~/.claude/hooks/

# 2. Register them in ~/.claude/settings.json
#    (merge the "hooks" block from .claude/settings.example.json)

# 3. Per repo you want the commit-time layer in:
ln -sf ~/.claude/hooks/no-comment-metadata-precommit.sh \
       /path/to/repo/.git/hooks/pre-commit
```

Step 3 is per repository — a git hook lives in `.git/hooks/` and is never cloned.
A symlink keeps every repo on one copy of the script.

See [`.claude/settings.example.json`](.claude/settings.example.json) for the exact `hooks` block to merge into your **global** `~/.claude/settings.json`. Restart Claude Code (or start a new session) after editing `settings.json` so the hook registration is picked up. The scripts themselves are read fresh on every run, so you can tweak them without restarting.

## Tests

```bash
tests/notify-done.test.sh   # no audio: a fake paplay on PATH records its args
tests/notify-ask.test.sh
tests/no-comment-metadata.test.sh   # builds sample files in a temp dir
tests/no-comment-metadata-precommit.test.sh   # builds throwaway git repos
tests/deny-no-verify.test.sh
```

---

## `notify-done.sh` — completion chime

Plays a gentle marimba (~14% volume) through **WSLg's PulseAudio** — a pure-Linux path, no Windows process launched at playback time.

- Sound file: `claude-chime.wav` (volume is **baked into the file**, because `paplay`/`SoundPlayer` don't reliably honor a separate volume knob).
- 0.6 s of **leading silence** is baked in so a sleeping audio device has time to wake up before the audible part — otherwise the first short chime after an idle period gets swallowed.
- Playback is detached with `setsid` so it never delays the end of a turn.

### Requirements (WSL2 + WSLg)

```bash
sudo apt install -y pulseaudio-utils   # provides paplay
```

WSLg exposes a PulseServer socket at `/mnt/wslg/PulseServer`; the script exports
`PULSE_SERVER` explicitly in case the hook shell didn't inherit it. Sound still
physically exits through Windows (WSL2 has no direct audio hardware), but nothing
Windows-specific is invoked.

### Changing the sound / volume

**Volume, live** — no regeneration needed, add a `--volume` flag (0–65536, 65536 = 100%):

```bash
paplay --volume=32768 "$HOME/.claude/hooks/claude-chime.wav"
```

**Rebuild the WAV** at a different baked volume or from a different source sound
using [`make-chime.py`](.claude/hooks/make-chime.py) — pure Python stdlib, no
external tools. It scales a source WAV down and prepends the silence:

```bash
.claude/hooks/make-chime.py --src some-sound.wav --amp 0.6 \
  --out ~/.claude/hooks/claude-chime.wav
```

`--amp` is a 0..1 multiplier (0.6 ≈ 14% peak). It reports the peak amplitude so
you can check loudness without playing anything. Source must be 16-bit PCM WAV.

`--skip`, `--clip`, `--repeat` and `--gap` shape the sound rather than its
volume: drop seconds off the front, keep only the first N seconds (fading the cut
so it doesn't click), and play it back more than once with silence between. That
is how `claude-ask.wav` is built out of `claude-chime.wav`:

```bash
.claude/hooks/make-chime.py --src .claude/hooks/claude-chime.wav \
  --amp 1.0 --skip 0.6 --clip 0.9 --lead 0.6 --repeat 2 --gap 0.12 \
  --out .claude/hooks/claude-ask.wav
```

### Background agents: what the chime actually means

`Stop` fires whenever Claude hands the turn back, which includes handing it back
while a background agent it launched is still working. One undifferentiated
chime therefore covers two situations — *finished* and *paused mid-work* — and
you can't tell them apart without looking at the terminal.

So the hook checks first, and by default says nothing until the work it would be
announcing is actually over. Three modes, set in `notify-done.conf` (copy
[`notify-done.conf.example`](.claude/hooks/notify-done.conf.example) next to the
hook) or as an environment variable, which wins over the file:

| `NOTIFY_MODE` | While a background agent is running | Otherwise |
| --- | --- | --- |
| `quiet` *(default)* | silent | chime |
| `always` | chime | chime |
| `distinct` | quieter chime (`NOTIFY_PENDING_VOLUME`, default 22000) | chime |

Under `quiet` you still get exactly one chime per piece of work: the agent
finishing wakes Claude up, and the chime lands when *that* follow-up turn ends.

[`pending-agents.py`](.claude/hooks/pending-agents.py) does the counting, reading
the session transcript that the hook payload points at. A launch shows up as a
tool result carrying an `agentId` plus either `isAsync` (the **Agent** tool) or
`background` (a skill forked into the background, such as `/code-review`); the
matching completion arrives later as a `task-notification` carrying `<task-id>`.
Two consequences worth knowing:

- The `agentId` is what separates those from a background `Bash` — a dev server
  that's meant to run for hours is deliberately not counted, or it would hold
  the chime hostage for as long as it lives.
- Killed and failed agents get a notification too, so stopping one releases the
  chime rather than silencing the session for good.

The remaining hole is an agent that dies without notifying at all. `NOTIFY_STALE_MINUTES`
(default 60) bounds it: past that, a launch stops being counted. And any error in
the counter is treated as "nothing pending", so a broken detector goes back to
chiming instead of going silent.

### Non-WSL machines

Swap the player in `notify-done.sh` and `notify-ask.sh`: on native Linux use
`paplay`/`aplay` directly against your normal PulseAudio/PipeWire; on macOS use
`afplay claude-chime.wav`.

---

## `notify-ask.sh` — attention chime

`Stop` announces that Claude *stopped*. It says nothing when Claude is stuck
waiting on you mid-turn, which is exactly the moment worth hearing about: you've
walked away, and the work is now blocked on a keystroke.

Sound is `claude-ask.wav` — the same marimba struck **twice**, so "needs you" and
"finished" are distinguishable without looking at the terminal. Everything else
(WSLg PulseAudio, baked-in volume, leading silence, detached playback) works the
same way as the completion chime above.

### Two events, because no single one covers it

| Event | Covers |
| --- | --- |
| `Notification` | permission prompts, including switching to auto-accept, and background agents asking for input |
| `PreToolUse` matched to `AskUserQuestion` | the a) b) c) option picker |

The second is not redundant. `AskUserQuestion` emits **no notification of any
kind**, and the turn hasn't ended so `Stop` doesn't fire either — a question
sitting on screen is otherwise completely silent. Matching it in `PreToolUse`
fires the chime just before the picker renders.

Permission prompts, by contrast, arrive through `Notification` — but on a **6
second delay**, and only if you haven't already answered. Answer promptly and
you never hear it; that's deliberate on Claude Code's side, not something this
hook can tighten.

### Which moments chime

`Notification` payloads carry a `notification_type`, and that is what the hook
filters on — set `NOTIFY_ASK_EVENTS` in `notify-done.conf` (or as an environment
variable, which wins over the file) to a space-separated list:

| Kind | Default | Meaning |
| --- | --- | --- |
| `question` | ✅ | the a) b) c) picker (synthetic — `PreToolUse`, not a real notification type) |
| `permission_prompt` | ✅ | a tool Claude may not run unattended |
| `worker_permission_prompt` | ✅ | the same, from a background worker |
| `agent_needs_input` | ✅ | a background agent is stuck on a question |
| `idle_prompt` | — | "Claude is waiting for your input", ~60s after a turn ends |
| `agent_completed` | — | a background agent finished |

`idle_prompt` is off because it re-announces a moment the `Stop` chime already
announced, a minute later. Turn it on if you want the second nudge. Anything not
in the list — auth, computer-use, MCP elicitation — is silent.

`NOTIFY_ASK_MODE=off` disables the hook outright; `NOTIFY_ASK_CHIME=/path.wav`
swaps the sound.

### Where this deliberately stops

A question typed as prose isn't a tool call, so it gets no two-blip chime — it
ends the turn like anything else and the `Stop` chime covers it. And if a
background agent is still running, `quiet` mode swallows even that, leaving a
pending prose question silent.

Both are intended. The work isn't finished while an agent is still going, so the
answer can wait for the chime that lands when it reports back; and a chime only
has to fetch you, not tell you in advance what's waiting. The two-blip sound is
reserved for the moments Claude genuinely cannot move without you.

So: no heuristics here for guessing whether prose was a question. A hook that
sometimes chimes at rhetorical questions and stays quiet at "let me know which
you prefer" is worse than one whose silence you can rely on.

---

## `no-comment-metadata.sh` — comment policy enforcement

A Python hook (despite the `.sh` name — it's invoked as `python3 …`) that runs as
a `PreToolUse` hook on every `Edit`/`Write`/`MultiEdit`/`Bash`. It reads the hook
JSON on stdin and **blocks the edit before it lands** (exit code 2, with the
reason sent back to Claude) when the change:

- **(a)** puts metadata inside a comment — dates (`YYYY-MM-DD`), plan/phase/wave
  numbers, task or step IDs, or phrases like `added in` / `fixed by` / `review fix`; or
- **(b)** would leave a run of **3+ consecutive** comment lines — doc comments
  (`///`, `/** */`) count too, so long doc blocks are blocked as well. The one
  exemption is a `//!` module header at the top of the file. See
  [The two-line budget](#the-two-line-budget).
- **(c)** puts a full comment run on a single-line statement. Dormant while (b)
  is the tighter of the two; it applies again if you raise `MAX_COMMENT_LINES`.

### Why Bash is covered

A hook matched only on `Edit|Write|MultiEdit` is bypassed entirely by `cat > f
<<'EOF'`, `tee`, or a heredoc inside a script — and an agent told to prefer shell
tooling will reach for exactly that. The hook scans a `Bash` command for
heredocs redirected into a file with a known source extension and re-checks each
body as if it were a `Write`. A command that writes nothing, or writes somewhere
we don't check, costs one process spawn (~24 ms) and exits silently.

### Two confidence tiers

Some metadata can't be told from ordinary code talk by pattern alone. `cleared it
(0010)` is a stamp; `mask (0010) selects the second lane` is a bitmask — same
shape, and only the author's intent separates them. Hard-blocking that shape
would reject correct edits with no way to override, so the hook splits by
confidence:

| Tier | Matches | Verdict |
| --- | --- | --- |
| 1 | keyword-anchored: `plan 0071`, `phase 3` / `wave 2`, ISO dates, `added in` / `fixed by` / `review fix` / `see plan`, `task #12`, `step 4` | **deny** — exit 2, edit blocked, reason fed back to Claude |
| 2 | bare parenthesised 4-digit IDs, changelog voice (`cleared/renamed/bumped it`), spec-version dates | **ask** — `permissionDecision: "ask"` JSON on stdout, you decide |

Tier 2 is a smoke detector, not a lock: a false positive costs one keypress
instead of an argument with the agent. Tier 1 skips dates inside URLs
(`…/specification/2025-06-18/`), which are describing the code, not stamping it.

It also skips `ADR-0023` and `(#144)`. A reference to a numbered decision record
or issue points at a document that outlives the change and tells a later reader
where the constraint came from; `plan 143 Step 4` only records when the line was
written, and resolves to nothing once the plan is archived. Pointer stays, stamp
goes.
A tier-1 hit always wins over a tier-2 one on the same edit.

Both tiers only look at the comment portion of a line — the text from the first
comment marker (`//`, `#`, `/*`, …) onward — and string literals are stripped
before that marker search. So a date embedded in a code string, or a quoted date
example inside a comment, never matches either tier.

Measured over ~95k comment lines of real source, tier 2 fires on 0.06% of comment
lines; on a codebase with no metadata convention at all (`llama.cpp`), tier 1
fires 4 times in 11.3k comment lines and tier 2 five times.

### The two-line budget

Two lines is the budget: enough for a why and the consequence that follows from
it, not enough for a paragraph. A one-liner that genuinely needs explaining — a
gnarly regex, a magic constant, a workaround for someone else's bug — gets its
two lines and passes silently. The third line is what marks prose that outgrew
its code, and it is blocked wherever it appears: above a `fn`, behind a blank
line, or as `///`.

That uniformity is deliberate. An earlier version gave declarations and doc
comments a larger budget, which just moved the essays into `///` — if one
comment marker is cheaper than another, that is the one agents write. The single
exemption is a `//!` module header, and only with nothing above it but blank
lines and inner attributes (`#![allow(…)]`). It is the first thing an agent
reads when it opens a file and it saves reading the whole file to orient, so
it earns its tokens; anchoring it to the top of the file is what stops `//!`
becoming the next escape hatch.

Check (c) sized a comment run against its target statement — finding the next
code line, skipping attributes, and measuring the statement's extent by bracket
depth and indentation. With the budget at two lines, check (b) blocks a
three-line run before (c) can weigh in, so (c) sits dormant behind
`ONELINER_RUN`. Raise `MAX_COMMENT_LINES` above 2 and it starts firing again,
with these exemptions:

| Situation | Why it's exempt |
| --- | --- |
| Target matches a declaration head (`fn`, `def`, `class`, `impl`, `struct`, `type`, …) | Comment is documenting an interface |
| Blank line between comment and code | It's a section header, not attached to a statement |
| No target — run ends the file or the block | Nothing to measure |
| Run opens with `///`, `//!`, `/**` | Doc comment, attached to a declaration by definition |

Tune it with `BLOCK_EXTENT` (how many lines of code count as a one-liner),
`ONELINER_RUN` (the run length (c) rejects) and `MAX_COMMENT_LINES` (the run
limit in (b)).

For checks (b) and (c) the hook simulates the edit against the on-disk file. `Edit`/`MultiEdit`
splice `new_string` over `old_string` (including `replace_all` and sequential
edits); a `Write` is instead diffed against the on-disk file with `difflib`, so
only lines the write actually adds count — a pre-existing comment run the
rewrite didn't touch no longer blocks it. Either way, a short comment added next
to existing comment lines is counted as one run, and only runs the edit
actually touches are flagged — pre-existing long comments elsewhere in the file
never block an unrelated edit. If the file can't be read (e.g. a new file), it
falls back to checking the added text in isolation.

A first line starting with `#!` (a shebang) is never counted toward a comment
run in hash-comment languages, so a script's shebang line doesn't eat into the
budget.

It's comment-syntax aware per file extension (`.rs .js .ts .jsx .tsx .go .php .py
.css .html`). The intent: keep history in git and planning docs, not in code
comments, and discourage over-commenting. Tune `MAX_COMMENT_LINES`, `BLOCK_EXTENT`
and the `meta`
(tier 1) / `suspect` (tier 2) regexes at the top of the script to taste — move a
pattern between them to change whether it blocks or asks.

Evidence lines printed in a block or ask message are capped at 5 per finding,
with a `… N more line(s)` tail summarizing the rest, so a long comment run
doesn't flood the reason text.

---

## `no-comment-metadata-precommit.sh` — the commit-time layer

A git `pre-commit` hook. It answers the hole the `PreToolUse` layer cannot close:
that hook only sees `Edit`/`Write` payloads and heredocs redirected into a source
file, so a script that opens the file itself walks straight past it — the target
path is the interpreter's stdin, not a file, so no redirect is there to match:

```bash
python3 - <<'EOF'
s = open('src/thing.rs').read()
s = s.replace(old_doc, new_doc)     # six new /// lines
open('src/thing.rs', 'w').write(s)
EOF
```

An agent told to prefer shell tooling reaches for that shape often. This hook
reads what is **staged**, so it does not care how the text arrived — tool, script,
subagent, worktree, or a session running with no hooks at all.

### One copy of the rules

It does not restate a single pattern. For each staged file it writes the `HEAD`
version to a temp file with the same extension, then feeds
`no-comment-metadata.sh` a `Write` payload whose `content` is the staged version.
That is exactly the shape that hook's `Write` path already handles: it diffs the
two with `difflib`, counts only added lines, and applies the run budget and both
metadata tiers. The temp path is swapped back to the real path in the message.

Raising `MAX_COMMENT_LINES` or editing a regex therefore changes both layers at
once, and the two can never drift apart.

### What it costs

It fires late. The commit fails after the build and the tests have already run.
That is the price of judging the end state instead of the intent — and the end
state is the only thing a script cannot route around.

Ambiguous (tier 2) metadata has no prompt channel at commit time, so it prints as
a `WARNING` and does not block. Binary files, files over 2 MB, and extensions the
comment hook does not police are skipped.

`COMMENT_GUARD_SKIP=1 git commit …` bypasses it. That is for you, at a terminal;
`deny-no-verify.sh` is what keeps the agent from reaching for the same idea.

---

## `deny-no-verify.sh` — no waving the commit layer through

A `PreToolUse` hook on `Bash`. A commit-time check is only worth having if the
thing it blocks cannot skip it, and `--no-verify` is one keystroke away from a
rejected commit.

Denied: `git commit --no-verify` and its `-n` short form (including bundled flags
like `-nm`), `git push --no-verify`, and a `core.hooksPath` override.

Allowed: anything that only mentions the flag without running it — a `grep` for
it, a commit message containing the word, `sort -n`. The `-n` match is anchored
to a `git … commit` on the same command segment.

This binds the agent, not you. Your own shell has no hook in front of it.
