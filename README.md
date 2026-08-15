# llm-stuff

Personal Claude Code configuration — hooks I reuse across machines.

Everything lives under [`.claude/hooks/`](.claude/hooks/). Two hooks are included:

| Hook | Event | What it does |
|------|-------|--------------|
| [`notify-done.sh`](.claude/hooks/notify-done.sh) | `Stop` | Plays a soft completion chime when Claude finishes a turn. |
| [`no-comment-metadata.sh`](.claude/hooks/no-comment-metadata.sh) | `PreToolUse` (Edit/Write/MultiEdit) | Blocks edits that put metadata in comments or add long comment blocks; asks on ambiguous cases. |

## Install

```bash
# 1. Copy the hooks into your Claude config
mkdir -p ~/.claude/hooks
cp .claude/hooks/* ~/.claude/hooks/

# 2. Register them in ~/.claude/settings.json
#    (merge the "hooks" block from .claude/settings.example.json)
```

See [`.claude/settings.example.json`](.claude/settings.example.json) for the exact `hooks` block to merge into your **global** `~/.claude/settings.json`. Restart Claude Code (or start a new session) after editing `settings.json` so the hook registration is picked up. The scripts themselves are read fresh on every run, so you can tweak them without restarting.

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

### Fire only when Claude needs input (not every turn)

Move the hook from `"Stop"` to `"Notification"` in `settings.json`. `Stop` fires
when a turn ends; `Notification` fires when Claude is waiting on you.

### Non-WSL machines

Swap the player in `notify-done.sh`: on native Linux use `paplay`/`aplay`
directly against your normal PulseAudio/PipeWire; on macOS use
`afplay claude-chime.wav`.

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

### Two confidence tiers

Some metadata can't be told from ordinary code talk by pattern alone. `cleared it
(0010)` is a stamp; `mask (0010) selects the second lane` is a bitmask — same
shape, and only the author's intent separates them. Hard-blocking that shape
would reject correct edits with no way to override, so the hook splits by
confidence:

| Tier | Matches | Verdict |
| --- | --- | --- |
| 1 | keyword-anchored: `plan 0071`, `task #12`, `phase 3`, ISO dates, `added in` / `fixed by` | **deny** — exit 2, edit blocked, reason fed back to Claude |
| 2 | bare parenthesised 4-digit IDs, changelog voice (`cleared/renamed/bumped it`), spec-version dates | **ask** — `permissionDecision: "ask"` JSON on stdout, you decide |

Tier 2 is a smoke detector, not a lock: a false positive costs one keypress
instead of an argument with the agent. Tier 1 skips dates inside URLs
(`…/specification/2025-06-18/`), which are describing the code, not stamping it.
A tier-1 hit always wins over a tier-2 one on the same edit.

Measured over ~95k comment lines of real source, tier 2 fires on 0.06% of comment
lines; on a codebase with no metadata convention at all (`llama.cpp`), tier 1
fires 4 times in 11.3k comment lines and tier 2 five times.

For check (b) the hook simulates the edit against the on-disk file (splicing
`new_string` over `old_string`, including `replace_all` and sequential
`MultiEdit` edits), so a short comment added next to existing comment lines is
counted as one run. Only runs the edit actually touches are flagged —
pre-existing long comments elsewhere in the file never block an unrelated edit.
If the file can't be read (e.g. a new file), it falls back to checking the added
text in isolation.

It's comment-syntax aware per file extension (`.rs .js .ts .jsx .tsx .go .php .py
.css .html`). The intent: keep history in git and planning docs, not in code
comments, and discourage over-commenting. Tune `MAX_COMMENT_LINES` and the `meta`
(tier 1) / `suspect` (tier 2) regexes at the top of the script to taste — move a
pattern between them to change whether it blocks or asks.
