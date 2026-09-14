#!/usr/bin/env bash
# Claude Code completion chime — pure Linux path via WSLg PulseAudio (no Windows
# process). Soft marimba at ~14% (volume baked into the WAV) with a leading
# silence so a sleeping audio device doesn't swallow it.
#   Volume, live:  add `--volume=N` to paplay below (0..65536, 65536=100%).
#   Rebuild WAV:   make-chime.py --src <any.wav> --amp 0.6   (pure stdlib).
#   Any sound:     just replace claude-chime.wav with another WAV.
#
# `Stop` fires whenever the turn is handed back, including while a background
# agent is still running — so the chime alone can't tell "finished" from "paused
# mid-work". NOTIFY_MODE picks what to do about that; see notify-done.conf.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${NOTIFY_LOG:-$HERE/notify-done.log}"
CHIME="$HERE/claude-chime.wav"
# WSLg's PulseServer — set explicitly in case the hook shell didn't inherit it.
export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"

# Config file first, environment second, so an env var can override a session.
_env_mode="${NOTIFY_MODE:-}"
_env_volume="${NOTIFY_PENDING_VOLUME:-}"
_env_stale="${NOTIFY_STALE_MINUTES:-}"
_env_skip_sdk="${NOTIFY_SKIP_SDK:-}"
# shellcheck source=/dev/null
[ -f "$HERE/notify-done.conf" ] && . "$HERE/notify-done.conf"
NOTIFY_MODE="${_env_mode:-${NOTIFY_MODE:-quiet}}"
NOTIFY_PENDING_VOLUME="${_env_volume:-${NOTIFY_PENDING_VOLUME:-22000}}"
export NOTIFY_STALE_MINUTES="${_env_stale:-${NOTIFY_STALE_MINUTES:-60}}"
NOTIFY_SKIP_SDK="${_env_skip_sdk:-${NOTIFY_SKIP_SDK:-on}}"

payload="$(cat)"

# Headless SDK runs (`claude -p`, eval and test harnesses) end a turn each, so a
# batch of them plays one chime per run for work the operator never started. The
# Stop payload has no entrypoint field, so read it off the transcript's first
# entry. Anything unreadable falls through to chiming.
if [ "$NOTIFY_SKIP_SDK" != "off" ] && printf '%s' "$payload" | python3 -c '
import json, sys
try:
    path = (json.load(sys.stdin) or {}).get("transcript_path") or ""
    with open(path) as f:
        for _ in range(20):
            line = f.readline()
            if not line:
                break
            entry = json.loads(line)
            kind = entry.get("entrypoint") or entry.get("promptSource") or ""
            if kind:
                sys.exit(0 if kind.startswith("sdk") else 1)
except Exception:
    pass
sys.exit(1)
' 2>>"$LOG"; then
    echo "[$(date '+%F %T')] hook skipped kind=sdk" >>"$LOG"
    exit 0
fi
pending=0
if [ "$NOTIFY_MODE" != "always" ]; then
    pending="$(printf '%s' "$payload" | python3 "$HERE/pending-agents.py" 2>>"$LOG")"
    case "$pending" in ''|*[!0-9]*) pending=0 ;; esac
fi

echo "[$(date '+%F %T')] hook fired mode=$NOTIFY_MODE pending=$pending" >>"$LOG"

volume=()
if [ "$pending" -gt 0 ]; then
    case "$NOTIFY_MODE" in
        # Silent until the work it would be announcing is actually over.
        quiet) exit 0 ;;
        distinct) volume=(--volume="$NOTIFY_PENDING_VOLUME") ;;
    esac
fi

# Detach so the hook shell's teardown can't cut playback short.
setsid bash -c "paplay ${volume[*]} '$CHIME' >>\"$LOG\" 2>&1; echo \"[\$(date '+%F %T')] done rc=\$?\" >>\"$LOG\"" >/dev/null 2>&1 &

exit 0
