#!/usr/bin/env bash
# Claude Code completion chime — pure Linux path via WSLg PulseAudio (no Windows
# process). Soft marimba at ~14% (volume baked into the WAV) with a leading
# silence so a sleeping audio device doesn't swallow it.
#   Volume, live:  add `--volume=N` to paplay below (0..65536, 65536=100%).
#   Rebuild WAV:   make-chime.py --src <any.wav> --amp 0.6   (pure stdlib).
#   Any sound:     just replace claude-chime.wav with another WAV.
LOG="$HOME/.claude/hooks/notify-done.log"
CHIME="$HOME/.claude/hooks/claude-chime.wav"
# WSLg's PulseServer — set explicitly in case the hook shell didn't inherit it.
export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"

echo "[$(date '+%F %T')] hook fired" >>"$LOG"

# Detach so the hook shell's teardown can't cut playback short.
setsid bash -c "paplay '$CHIME' >>\"$LOG\" 2>&1; echo \"[\$(date '+%F %T')] done rc=\$?\" >>\"$LOG\"" >/dev/null 2>&1 &

exit 0
