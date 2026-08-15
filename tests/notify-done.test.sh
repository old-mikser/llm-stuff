#!/usr/bin/env bash
# Tests for notify-done.sh and pending-agents.py. No audio is played: a fake
# paplay on PATH records its arguments instead. Run from anywhere:
#   tests/notify-done.test.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.claude/hooks" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat >"$WORK/bin/paplay" <<EOF
#!/usr/bin/env bash
echo "\$@" >>"$WORK/played"
EOF
chmod +x "$WORK/bin/paplay"
export PATH="$WORK/bin:$PATH"
export NOTIFY_LOG="$WORK/hook.log"
export NOTIFY_NOW="2026-08-15T12:00:00Z"

pass=0
fail=0

check() {
    local name="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
        pass=$((pass + 1))
        printf 'ok   %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL %s\n       want: %s\n       got:  %s\n' "$name" "$want" "$got"
    fi
}

launch() { # agentId toolUseId timestamp
    printf '{"type":"user","timestamp":"%s","toolUseResult":{"isAsync":true,"status":"async_launched","agentId":"%s"},"message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":"Async agent launched successfully."}]}}\n' "$3" "$1" "$2"
}

notify() { # body
    printf '{"type":"user","origin":{"kind":"task-notification"},"message":{"content":"%s"}}\n' "$1"
}

chatter() {
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}\n'
}

count() { # transcript file -> pending count
    python3 "$HOOKS/pending-agents.py" "$1"
}

# --- pending-agents.py ------------------------------------------------------

T="$WORK/t.jsonl"

chatter >"$T"
check "no agents means nothing pending" "0" "$(count "$T")"

launch a1 toolu_1 "2026-08-15T11:59:00Z" >"$T"
check "launched agent is pending" "1" "$(count "$T")"

{ launch a1 toolu_1 "2026-08-15T11:59:00Z"
  notify "<task-id>a1</task-id><status>completed</status>"; } >"$T"
check "completion by task-id clears it" "0" "$(count "$T")"

{ launch a1 toolu_1 "2026-08-15T11:59:00Z"
  notify "<tool-use-id>toolu_1</tool-use-id><status>completed</status>"; } >"$T"
check "completion by tool-use-id alone clears it" "0" "$(count "$T")"

for status in failed killed stopped; do
    { launch a1 toolu_1 "2026-08-15T11:59:00Z"
      notify "<task-id>a1</task-id><status>$status</status>"; } >"$T"
    check "$status also clears it" "0" "$(count "$T")"
done

{ launch a1 toolu_1 "2026-08-15T11:59:00Z"
  launch a2 toolu_2 "2026-08-15T11:59:30Z"
  notify "<task-id>a1</task-id><status>completed</status>"; } >"$T"
check "only the unreported agent is counted" "1" "$(count "$T")"

launch a1 toolu_1 "2026-08-15T09:00:00Z" >"$T"
check "an agent older than the window is dropped" "0" "$(count "$T")"

{ launch a1 toolu_1 "2026-08-15T09:00:00Z"
  launch a2 toolu_2 "2026-08-15T11:59:00Z"; } >"$T"
check "staleness is per agent" "1" "$(count "$T")"

{ printf 'not json at all\n'
  printf '\n'
  launch a1 toolu_1 "2026-08-15T11:59:00Z"; } >"$T"
check "unparseable lines are skipped" "1" "$(count "$T")"

{ launch a1 toolu_1 "2026-08-15T11:59:00Z" | sed 's/"type":"user"/"type":"user","isSidechain":true/'; } >"$T"
check "a subagent's own transcript entries don't count" "0" "$(count "$T")"

check "a missing transcript counts as none" "0" "$(count "$WORK/nope.jsonl")"
check "an empty payload counts as none" "0" "$(printf '{}' | python3 "$HOOKS/pending-agents.py")"

# --- notify-done.sh ---------------------------------------------------------

run_hook() { # transcript -> "played" | "silent"
    rm -f "$WORK/played"
    printf '{"transcript_path":"%s"}' "$1" | bash "$HOOKS/notify-done.sh"
    # Playback is detached, so give the child a moment to land.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -f "$WORK/played" ] && break
        sleep 0.1
    done
    if [ -f "$WORK/played" ]; then cat "$WORK/played"; else echo silent; fi
}

chatter >"$T"
check "quiet mode chimes when nothing is running" "$HOOKS/claude-chime.wav" "$(NOTIFY_MODE=quiet run_hook "$T")"

launch a1 toolu_1 "2026-08-15T11:59:00Z" >"$T"
check "quiet mode stays silent while an agent runs" "silent" "$(NOTIFY_MODE=quiet run_hook "$T")"
check "quiet mode is the default" "silent" "$(run_hook "$T")"
check "always mode chimes anyway" "$HOOKS/claude-chime.wav" "$(NOTIFY_MODE=always run_hook "$T")"
check "distinct mode chimes quieter" "--volume=22000 $HOOKS/claude-chime.wav" "$(NOTIFY_MODE=distinct run_hook "$T")"
check "distinct volume is configurable" "--volume=9000 $HOOKS/claude-chime.wav" \
    "$(NOTIFY_MODE=distinct NOTIFY_PENDING_VOLUME=9000 run_hook "$T")"

{ launch a1 toolu_1 "2026-08-15T11:59:00Z"
  notify "<task-id>a1</task-id><status>completed</status>"; } >"$T"
check "the chime lands on the turn after the last agent reports" "$HOOKS/claude-chime.wav" "$(NOTIFY_MODE=quiet run_hook "$T")"

launch a1 toolu_1 "2026-08-15T11:59:00Z" >"$T"
check "a shorter window unblocks the chime" "$HOOKS/claude-chime.wav" \
    "$(NOTIFY_MODE=quiet NOTIFY_STALE_MINUTES=0.1 run_hook "$T")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
