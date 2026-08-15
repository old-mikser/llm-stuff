#!/usr/bin/env python3
"""Count background agents this session launched but hasn't heard back from.

Reads a Claude Code hook payload on stdin (uses its `transcript_path`), or takes
a transcript path as argv[1]. Prints one integer: how many background agents are
still outstanding. Anything unexpected prints 0 — the caller treats 0 as "go
ahead and chime", so a detector that breaks goes back to chiming rather than
going permanently silent.

Two markers in the transcript, both on `user` entries:

  launch     `toolUseResult.isAsync` (Agent tool) or `toolUseResult.background`
             (a skill forked into the background, e.g. `/code-review`), in both
             cases carrying an `agentId`. Requiring the `agentId` keeps a
             long-lived background Bash — a dev server that never exits — from
             wedging the count above zero.
  completion `origin.kind == "task-notification"`, carrying `<task-id>` and
             usually `<tool-use-id>`. Emitted for killed and failed agents too,
             so stopping an agent clears it.

An agent whose launch is older than the staleness window is dropped from the
count, bounding the damage if one ever dies without a notification.
"""
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

STALE_MINUTES = float(os.environ.get("NOTIFY_STALE_MINUTES") or 60)

TASK_ID = re.compile(r"<task-id>\s*([^<\s]+)\s*</task-id>")
TOOL_USE_ID = re.compile(r"<tool-use-id>\s*([^<\s]+)\s*</tool-use-id>")


def text_of(content):
    """Flatten a message content field (string, or a list of typed blocks)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            b.get("text", "") for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        )
    return ""


def tool_use_id_of(entry):
    for block in (entry.get("message") or {}).get("content") or []:
        if isinstance(block, dict) and block.get("type") == "tool_result":
            return block.get("tool_use_id")
    return None


def parse_time(stamp):
    try:
        return datetime.fromisoformat(str(stamp).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


def now():
    override = os.environ.get("NOTIFY_NOW")
    return parse_time(override) if override else datetime.now(timezone.utc)


def pending(path):
    launched = {}  # agentId -> (launch time, tool_use_id)
    by_tool_use = {}  # tool_use_id -> agentId

    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if not isinstance(entry, dict) or entry.get("isSidechain"):
                continue

            result = entry.get("toolUseResult")
            if isinstance(result, dict) and (result.get("isAsync") or result.get("background")):
                agent_id = result.get("agentId")
                if agent_id:
                    tool_use = tool_use_id_of(entry)
                    launched[agent_id] = (parse_time(entry.get("timestamp")), tool_use)
                    if tool_use:
                        by_tool_use[tool_use] = agent_id
                continue

            if (entry.get("origin") or {}).get("kind") != "task-notification":
                continue
            body = text_of((entry.get("message") or {}).get("content"))
            for agent_id in TASK_ID.findall(body):
                launched.pop(agent_id, None)
            for tool_use in TOOL_USE_ID.findall(body):
                launched.pop(by_tool_use.get(tool_use), None)

    cutoff = now() - timedelta(minutes=STALE_MINUTES)
    return sum(1 for started, _ in launched.values() if started and started > cutoff)


def transcript_path():
    if len(sys.argv) > 1:
        return sys.argv[1]
    return (json.load(sys.stdin) or {}).get("transcript_path")


def main():
    try:
        path = transcript_path()
        print(pending(path) if path else 0)
    except Exception:
        print(0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
