#!/usr/bin/env python3
"""Run one omp (oh-my-pi) worker turn non-interactively and print a compact report.

Usage:
  omp-run.py --cwd DIR [--prompt-file F] [--resume SESSION_ID] [--model M]
             [--max-cost USD] [--max-time 20m] [--log-dir DIR] [PROMPT...]

Prints (stdout): SESSION, STATUS, COST, TOOLS used, FILES touched, and the worker's
final message. The full JSONL event stream is saved to the log dir for inspection.
Exit code: 0 ok, 1 worker error/abort, 2 usage error, 3 cost limit hit.
"""
import argparse, json, os, subprocess, sys, time
from pathlib import Path

DEFAULT_MODEL = os.environ.get("OMP_WORKER_MODEL", "opencode-go/deepseek-v4.1-flash")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cwd", required=True)
    ap.add_argument("--prompt-file")
    ap.add_argument("--resume", help="omp session id to continue")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--max-cost", default="1")
    ap.add_argument("--max-time", default="20m")
    ap.add_argument("--approval-mode", default="yolo")
    ap.add_argument("--thinking", default=None)
    ap.add_argument("--log-dir", default=None)
    ap.add_argument("prompt", nargs="*")
    a = ap.parse_args()

    text = " ".join(a.prompt).strip()
    if a.prompt_file:
        body = Path(a.prompt_file).read_text()
        text = body + ("\n\n" + text if text else "")
    if not text:
        print("error: no prompt", file=sys.stderr)
        sys.exit(2)

    cwd = Path(a.cwd).resolve()
    log_dir = Path(a.log_dir or Path.home() / ".cache" / "omp-runs" / cwd.name)
    log_dir.mkdir(parents=True, exist_ok=True)
    log = log_dir / f"{time.strftime('%Y%m%d-%H%M%S')}.jsonl"

    cmd = ["omp", "-p", "--mode", "json", "--model", a.model,
           "--approval-mode", a.approval_mode, "--max-cost", str(a.max_cost),
           "--max-time", a.max_time, "--no-title", "--cwd", str(cwd)]
    if a.thinking:
        cmd += ["--thinking", a.thinking]
    if a.resume:
        cmd += ["--resume", a.resume]
    cmd.append(text)

    session = None; cost = 0.0; tools = {}; files = set(); final = ""; stop = None; errors = []
    with open(log, "w") as lf:
        p = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in p.stdout:
            lf.write(line)
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                if line.strip():
                    errors.append(line.strip())
                continue
            t = ev.get("type")
            if t == "session":
                session = ev.get("id")
            elif t == "message_end":
                m = ev.get("message", {})
                if m.get("role") != "assistant":
                    continue
                cost += ((m.get("usage") or {}).get("cost") or {}).get("total", 0) or 0
                stop = m.get("stopReason", stop)
                if m.get("errorMessage"):
                    errors.append(m["errorMessage"])
                txt = []
                for c in m.get("content", []):
                    if c.get("type") == "text":
                        txt.append(c.get("text", ""))
                    elif c.get("type") == "toolCall":
                        n = c.get("name", "?"); tools[n] = tools.get(n, 0) + 1
                        args = c.get("arguments") or {}
                        if isinstance(args, dict):
                            for k in ("path", "file_path", "file"):
                                if isinstance(args.get(k), str) and n in ("edit", "write", "Edit", "Write", "patch"):
                                    files.add(args[k])
                if txt:
                    final = "\n".join(txt).strip()
        rc = p.wait()

    status = "ok" if rc == 0 and stop not in ("error", "aborted") else f"exit={rc} stop={stop}"
    print(f"SESSION: {session}")
    print(f"STATUS:  {status}")
    print(f"COST:    ${cost:.4f}")
    print(f"TOOLS:   {', '.join(f'{k}x{v}' for k, v in sorted(tools.items())) or '-'}")
    print(f"FILES:   {', '.join(sorted(files)) or '- (check git diff)'}")
    print(f"LOG:     {log}")
    if errors:
        print("ERRORS:\n  " + "\n  ".join(errors[-5:]))
    print("---- worker final message ----")
    print(final or "(none)")
    sys.exit(0 if status == "ok" else (3 if rc == 3 else 1))


if __name__ == "__main__":
    main()
