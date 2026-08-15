#!/usr/bin/env bash
# Tests for notify-ask.sh. No audio is played: a fake paplay on PATH records its
# arguments instead. Run from anywhere:
#   tests/notify-ask.test.sh
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

ASK="$HOOKS/claude-ask.wav"
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

run_hook() { # payload-json -> "<wav>" | "silent"
    rm -f "$WORK/played"
    printf '%s' "$1" | bash "$HOOKS/notify-ask.sh"
    # Playback is detached, so give the child a moment to land.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -f "$WORK/played" ] && break
        sleep 0.1
    done
    if [ -f "$WORK/played" ]; then cat "$WORK/played"; else echo silent; fi
}

notification() { # notification_type message
    printf '{"hook_event_name":"Notification","notification_type":"%s","message":"%s"}' "$1" "$2"
}

pre_tool() { # tool_name
    printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{}}' "$1"
}

# --- the reason this hook exists --------------------------------------------

check "the a) b) c) picker chimes" "$ASK" "$(run_hook "$(pre_tool AskUserQuestion)")"
check "a permission prompt chimes" "$ASK" \
    "$(run_hook "$(notification permission_prompt 'Claude needs your permission to use Bash')")"
check "a background agent asking chimes" "$ASK" \
    "$(run_hook "$(notification agent_needs_input 'reviewer needs your input')")"
check "a worker permission prompt chimes" "$ASK" \
    "$(run_hook "$(notification worker_permission_prompt 'w1 needs permission for Bash')")"

# --- what stays quiet -------------------------------------------------------

check "an ordinary tool call is silent" "silent" "$(run_hook "$(pre_tool Bash)")"
check "the idle nag is silent (Stop already chimed)" "silent" \
    "$(run_hook "$(notification idle_prompt 'Claude is waiting for your input')")"
check "an agent finishing is silent" "silent" \
    "$(run_hook "$(notification agent_completed 'reviewer finished')")"
check "an unknown notification type is silent" "silent" \
    "$(run_hook "$(notification auth_success 'Claude Code login successful')")"

# --- configuration ----------------------------------------------------------

check "off means never" "silent" \
    "$(NOTIFY_ASK_MODE=off run_hook "$(pre_tool AskUserQuestion)")"
check "the idle nag can be switched on" "$ASK" \
    "$(NOTIFY_ASK_EVENTS="idle_prompt" run_hook "$(notification idle_prompt 'waiting')")"
check "switching idle on can switch questions off" "silent" \
    "$(NOTIFY_ASK_EVENTS="idle_prompt" run_hook "$(pre_tool AskUserQuestion)")"
: >"$WORK/other.wav"
check "the sound is swappable" "$WORK/other.wav" \
    "$(NOTIFY_ASK_CHIME="$WORK/other.wav" run_hook "$(pre_tool AskUserQuestion)")"

# --- malformed input --------------------------------------------------------

check "garbage on stdin is silent" "silent" "$(run_hook 'not json at all')"
check "an empty payload is silent" "silent" "$(run_hook '{}')"
check "a notification with no type is silent" "silent" \
    "$(run_hook '{"hook_event_name":"Notification","message":"hi"}')"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
