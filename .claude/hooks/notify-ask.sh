#!/usr/bin/env bash
# Claude Code attention chime — fires whenever Claude is blocked on you rather
# than working. Two events feed it, because no single one covers both cases:
#
#   Notification  a permission prompt (a tool it may not run unattended, or
#                 switching to auto-accept), or a background agent asking for
#                 input. Carries `notification_type`, which is what we filter on.
#   PreToolUse    matched to `AskUserQuestion` — the a) b) c) option picker.
#                 It emits no notification of any kind, and the turn hasn't
#                 ended, so `Stop` won't fire either: without this it is silent.
#
# Sound is two short blips (claude-ask.wav) so it's audibly different from the
# single completion chime notify-done.sh plays — you can tell "needs you" from
# "finished" without looking at the terminal. Same WSLg PulseAudio path; see
# notify-done.sh for volume and playback notes.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${NOTIFY_LOG:-$HERE/notify-done.log}"
export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"

# Config file first, environment second, so an env var can override a session.
_env_mode="${NOTIFY_ASK_MODE:-}"
_env_events="${NOTIFY_ASK_EVENTS:-}"
_env_chime="${NOTIFY_ASK_CHIME:-}"
# shellcheck source=/dev/null
[ -f "$HERE/notify-done.conf" ] && . "$HERE/notify-done.conf"
NOTIFY_ASK_MODE="${_env_mode:-${NOTIFY_ASK_MODE:-on}}"
NOTIFY_ASK_CHIME="${_env_chime:-${NOTIFY_ASK_CHIME:-$HERE/claude-ask.wav}}"
# `idle_prompt` is out by default: it lands ~60s after a turn ends, announcing a
# moment the Stop chime already announced. Add it if you want the later nudge.
NOTIFY_ASK_EVENTS="${_env_events:-${NOTIFY_ASK_EVENTS:-question permission_prompt worker_permission_prompt agent_needs_input}}"

[ "$NOTIFY_ASK_MODE" = "off" ] && exit 0

payload="$(cat)"

# One line: "<kind> <detail>". PreToolUse carries no notification_type, so the
# question picker gets the synthetic kind `question`; anything unrecognised
# yields an empty kind, which is never in the chime list.
read -r kind detail <<<"$(python3 -c '
import json, sys
try:
    p = json.load(sys.stdin) or {}
except Exception:
    p = {}
tool = p.get("tool_name") or ""
if p.get("hook_event_name") == "PreToolUse":
    print("question" if tool == "AskUserQuestion" else "-", tool)
else:
    print(p.get("notification_type") or "-", (p.get("message") or "").replace("\n", " "))
' <<<"$payload" 2>>"$LOG")"
kind="${kind:--}"

echo "[$(date '+%F %T')] ask hook fired kind=$kind detail=${detail:-(none)}" >>"$LOG"

case " $NOTIFY_ASK_EVENTS " in
    *" $kind "*) ;;
    *) exit 0 ;;
esac

# Detach so the hook shell's teardown can't cut playback short.
setsid bash -c "paplay '$NOTIFY_ASK_CHIME' >>\"$LOG\" 2>&1; echo \"[\$(date '+%F %T')] ask done rc=\$?\" >>\"$LOG\"" >/dev/null 2>&1 &

exit 0
