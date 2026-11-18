---
name: delegate
description: "Hand implementation of a plan to omp (oh-my-pi) running DeepSeek, then verify the result and loop fixes back into the same omp session. Claude plans and verifies; omp implements. Use when the user says delegate / hand off / let omp (or deepseek) implement, or invokes /delegate."
---

# Delegate implementation to omp

Division of labour: **you (Claude) plan and verify; omp + DeepSeek implements.**
You never edit the implementation yourself in this flow — fixes go back to omp.

Runner: `~/.claude/skills/delegate/scripts/omp-run.py` wraps `omp -p --mode json`
and prints `SESSION / STATUS / COST / TOOLS / FILES / LOG` plus the worker's final
message. Default model `opencode-go/deepseek-v4.1-flash` (override `--model`
or env `OMP_WORKER_MODEL`). Logs go to `~/.cache/omp-runs/<repo>/`.

Inside omp, the `orchestrate-omp` skill (`~/.omp/agent/skills/orchestrate-omp/`)
dispatches parallel DeepSeek `task` workers and reviewers and ends with a fixed
report (`RESULT / COMMITS / VERIFY / REVIEW / DEVIATIONS / BLOCKED / NOTES`).

## 1. Plan

- If there's no plan yet, write one with the user. Save it in the repo where
  plans live (`plans/`, `docs/plans/`, …; else `.plans/<slug>.md`).
- Make it executable by a weaker model: numbered tasks, each with its **exact
  file list**, the concrete change, pre-made decisions (names, signatures,
  libraries), how to test it, and dependencies between tasks. Ambiguity is the
  #1 cause of bad DeepSeek output — resolve it in the plan, not in the run.
- Name the verify command (build + tests + lint) in the plan.
- Show the user the plan and get a go-ahead unless they already said to run
  straight through.

## 2. Prepare

- `git status --short` and note `BASE=$(git rev-parse HEAD)`. If the tree has
  uncommitted changes that aren't the plan file, ask the user whether to commit,
  stash, or proceed (workers will leave foreign changes alone).
- Commit the plan file itself so workers see a clean tree.
- Optional, if the user wants isolation: `git switch -c omp/<slug>`.

## 3. Hand off

Pick the mode:

- **orchestrate** (default; plans with ≥2 tasks):
  ```bash
  python3 ~/.claude/skills/delegate/scripts/omp-run.py --cwd <repo> \
    --max-cost 3 --max-time 60m \
    "Load skill://orchestrate-omp and follow it exactly. Plan: <plan path>. Verify command: <cmd>. <overrides, e.g. 'one review round'>"
  ```
- **direct** (one small task, ≤ ~3 files): skip the orchestrator:
  ```bash
  python3 ~/.claude/skills/delegate/scripts/omp-run.py --cwd <repo> \
    --max-cost 1 --max-time 20m --prompt-file <plan> \
    "Implement this plan. Commit by explicit path. Run <cmd>. Report commits, test result, deviations."
  ```

Run it with `run_in_background: true` (runs exceed the 10-min foreground limit)
and wait for the completion notification — don't poll. Tell the user it's
running and roughly what's happening. Record the `SESSION` id.

## 4. Verify (your job — don't trust the report)

1. `git log --oneline $BASE..HEAD` and `git diff --stat $BASE..HEAD`; check
   `git status --short` for leftovers.
2. Read the actual diff against the plan, task by task: is each task done, did
   anything land outside its file list, any stubs/TODOs/skipped tests, deleted
   or weakened assertions, swallowed errors?
3. Run the verify command yourself.
4. Answer anything under `BLOCKED`, using the user if it's their decision.

## 5. Fix loop

If anything is wrong, send a precise fix list back into the **same session**:

```bash
python3 ~/.claude/skills/delegate/scripts/omp-run.py --cwd <repo> --resume <SESSION> \
  --max-cost 1 --max-time 30m \
  "Verification found these problems: <numbered list with file:line, expected vs actual, failing test output>. Fix them via workers per orchestrate-omp, then give the same final report."
```

Max **2** fix rounds. If it's still wrong after that, stop and report to the
user what's left, with your recommendation (fix manually, re-plan, or use a
stronger model with `--model`).

## 6. Report to the user

Short: commits (`$BASE..HEAD`), verify result, what you checked, fixes you had
omp make, total cost (sum of COST lines), anything left. Never push.

## Notes

- The runner exits 3 when `--max-cost` was hit; treat that as partial and ask
  before raising the limit.
- Full event log is in the `LOG` path; grep it if the report is unclear.
- `omp` subagents use omp's default model (`opencode-go/deepseek-v4.1-flash`
  in `~/.omp/agent/config.yml`).
