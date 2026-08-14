#!/usr/bin/env bash
# Claude Code completion chime — pure Linux path via WSLg PulseAudio (no Windows
# process). Soft marimba at ~10% (volume baked into the WAV) with a 1s silent
# lead-in so a sleeping audio device doesn't swallow it.
#   Volume: either regenerate the WAV, or add `--volume=N` below (0..65536, 65536=100%).
#   Sound:  replace claude-chime.wav (regen via make-chime.ps1, or drop in any WAV).
LOG="$HOME/.claude/hooks/notify-done.log"
CHIME="$HOME/.claude/hooks/claude-chime.wav"
# WSLg's PulseServer — set explicitly in case the hook shell didn't inherit it.
export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"

echo "[$(date '+%F %T')] hook fired" >>"$LOG"

# Detach so the hook shell's teardown can't cut playback short.
setsid bash -c "paplay '$CHIME' >>\"$LOG\" 2>&1; echo \"[\$(date '+%F %T')] done rc=\$?\" >>\"$LOG\"" >/dev/null 2>&1 &

exit 0
