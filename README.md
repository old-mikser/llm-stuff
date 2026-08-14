# llm-stuff

Personal Claude Code configuration — hooks I reuse across machines.

Everything lives under [`.claude/hooks/`](.claude/hooks/). Two hooks are included:

| Hook | Event | What it does |
|------|-------|--------------|
| [`notify-done.sh`](.claude/hooks/notify-done.sh) | `Stop` | Plays a soft completion chime when Claude finishes a turn. |
| [`no-comment-metadata.sh`](.claude/hooks/no-comment-metadata.sh) | `PostToolUse` (Edit/Write/MultiEdit) | Blocks edits that put metadata in comments or add long comment blocks. |

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

A Python hook (despite the `.sh` name — it's invoked as `python3 …`) that runs on
every `Edit`/`Write`/`MultiEdit`. It reads the hook JSON on stdin and **blocks the
edit** (exit code 2, with the reason sent back to Claude) when the added text:

- **(a)** puts metadata inside a comment — dates (`YYYY-MM-DD`), plan/phase/wave
  numbers, task IDs, or phrases like `added in` / `fixed by` / `review fix`; or
- **(b)** contains a run of **4+ consecutive** comment lines — doc comments
  (`///`, `//!`, `/** */`) count too, so long doc blocks are blocked as well.

It's comment-syntax aware per file extension (`.rs .js .ts .jsx .tsx .go .php .py
.css .html`). The intent: keep history in git and planning docs, not in code
comments, and discourage over-commenting. Tune `MAX_COMMENT_LINES` and the
`meta` regex at the top of the script to taste.
