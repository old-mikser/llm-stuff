# llm-stuff

Personal Claude Code configuration — hooks I reuse across machines.

Everything lives under [`.claude/hooks/`](.claude/hooks/). Three hooks are included:

| Hook | Event | What it does |
|------|-------|--------------|
| [`notify-done.sh`](.claude/hooks/notify-done.sh) | `Stop` | Plays a soft completion chime when Claude finishes a turn — by default staying quiet while background agents are still running. |
| [`notify-ask.sh`](.claude/hooks/notify-ask.sh) | `Notification`, `PreToolUse` (AskUserQuestion) | Plays a two-blip attention chime when Claude is waiting on *you* — a permission prompt or an a) b) c) question. |
| [`no-comment-metadata.sh`](.claude/hooks/no-comment-metadata.sh) | `PreToolUse` (Edit/Write/MultiEdit) | Blocks edits that put metadata in comments or add long comment blocks; asks on ambiguous cases and on oversized comments. |

## Install

```bash
# 1. Copy the hooks into your Claude config
mkdir -p ~/.claude/hooks
cp .claude/hooks/* ~/.claude/hooks/

# 2. Register them in ~/.claude/settings.json
#    (merge the "hooks" block from .claude/settings.example.json)
```

See [`.claude/settings.example.json`](.claude/settings.example.json) for the exact `hooks` block to merge into your **global** `~/.claude/settings.json`. Restart Claude Code (or start a new session) after editing `settings.json` so the hook registration is picked up. The scripts themselves are read fresh on every run, so you can tweak them without restarting.

## Tests

```bash
tests/notify-done.test.sh   # no audio: a fake paplay on PATH records its args
tests/notify-ask.test.sh
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
tool result carrying `isAsync` and an `agentId`; the matching completion arrives
later as a `task-notification` carrying `<task-id>`. Two consequences worth
knowing:

- Only the **Agent** tool writes `isAsync`. A background `Bash` — a dev server
  that's meant to run for hours — is deliberately not counted, or it would hold
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
a `PreToolUse` hook on every `Edit`/`Write`/`MultiEdit`. It reads the hook JSON on
stdin and **blocks the edit before it lands** (exit code 2, with the reason sent
back to Claude) when the change:

- **(a)** puts metadata inside a comment — dates (`YYYY-MM-DD`), plan/phase/wave
  numbers, task IDs, or phrases like `added in` / `fixed by` / `review fix`; or
- **(b)** would leave a run of **4+ consecutive** comment lines — doc comments
  (`///`, `//!`, `/** */`) count too, so long doc blocks are blocked as well.

A third check, **(c)**, only ever *asks*: a 2–3 line comment run sitting on a
single-line statement. See [Sizing a comment to its code](#sizing-a-comment-to-its-code).

### Two confidence tiers

Some metadata can't be told from ordinary code talk by pattern alone. `cleared it
(0010)` is a stamp; `mask (0010) selects the second lane` is a bitmask — same
shape, and only the author's intent separates them. Hard-blocking that shape
would reject correct edits with no way to override, so the hook splits by
confidence:

| Tier | Matches | Verdict |
| --- | --- | --- |
| 1 | keyword-anchored: `plan 0071`, `phase 3` / `wave 2`, ISO dates, `added in` / `fixed by` / `review fix` / `see plan`, `task #12` | **deny** — exit 2, edit blocked, reason fed back to Claude |
| 2 | bare parenthesised 4-digit IDs, changelog voice (`cleared/renamed/bumped it`), spec-version dates | **ask** — `permissionDecision: "ask"` JSON on stdout, you decide |

Tier 2 is a smoke detector, not a lock: a false positive costs one keypress
instead of an argument with the agent. Tier 1 skips dates inside URLs
(`…/specification/2025-06-18/`), which are describing the code, not stamping it.
A tier-1 hit always wins over a tier-2 one on the same edit.

Both tiers only look at the comment portion of a line — the text from the first
comment marker (`//`, `#`, `/*`, …) onward — and string literals are stripped
before that marker search. So a date embedded in a code string, or a quoted date
example inside a comment, never matches either tier.

Measured over ~95k comment lines of real source, tier 2 fires on 0.06% of comment
lines; on a codebase with no metadata convention at all (`llama.cpp`), tier 1
fires 4 times in 11.3k comment lines and tier 2 five times.

### Sizing a comment to its code

Three lines of comment above a function is proportionate; three lines above `let
n = min(n, 255);` usually isn't. Check (c) tries to tell those apart without a
parser: it finds the run's **target** — the next code line, skipping attributes
and decorators like `#[derive(…)]` or `@cache` — and measures that statement's
**extent**, following bracket depth and then indentation. Under 3 lines, the
target is a one-liner and 2–3 comment lines on it prompt an **ask**.

The heuristic is deliberately lopsided. Allowing a comment that could have been
shorter costs two lines; demanding brevity where an explanation was needed costs
the explanation — and the one-liners that most need three lines of prose (a
gnarly regex, a magic constant, a workaround for someone else's bug) are exactly
the ones with the least code to measure. So every ambiguous case gets the larger
budget and is passed silently:

| Situation | Why it's exempt |
| --- | --- |
| Target matches a declaration head (`fn`, `def`, `class`, `impl`, `struct`, `type`, …) | Comment is documenting an interface |
| Blank line between comment and code | It's a section header, not attached to a statement |
| No target — run ends the file or the block | Nothing to measure |
| Run opens with `///`, `//!`, `/**` | Doc comment, attached to a declaration by definition |

And it never blocks. A false positive costs one keypress, and the ask rate is
its own calibration signal: if you're approving nearly all of them, tighten
`BLOCK_EXTENT` or drop the check; if you're rejecting nearly all of them,
promote it to a deny.

For check (b) the hook simulates the edit against the on-disk file. `Edit`/`MultiEdit`
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
4-line budget.

It's comment-syntax aware per file extension (`.rs .js .ts .jsx .tsx .go .php .py
.css .html`). The intent: keep history in git and planning docs, not in code
comments, and discourage over-commenting. Tune `MAX_COMMENT_LINES`, `BLOCK_EXTENT`
and the `meta`
(tier 1) / `suspect` (tier 2) regexes at the top of the script to taste — move a
pattern between them to change whether it blocks or asks.

Evidence lines printed in a block or ask message are capped at 5 per finding,
with a `… N more line(s)` tail summarizing the rest, so a long comment run
doesn't flood the reason text.
