# delegate

A model-invoked skill, also `/delegate`. Claude plans and verifies; omp (oh-my-pi) running DeepSeek implements. Claude writes a plan a weaker model can execute, hands it to omp headless,
then checks the commits and runs the verify command itself rather than trusting the report. Problems go
back into the same omp session as a numbered fix list, at most two rounds. It never pushes.

Two parts:

- `SKILL.md` and `scripts/omp-run.py`, the Claude Code side. The runner wraps `omp -p --mode json` and
  prints `SESSION / STATUS / COST / TOOLS / FILES / LOG` plus the worker's final message. The default
  model is `opencode-go/deepseek-v4.1-flash`; override it with `--model` or `OMP_WORKER_MODEL`.
- `omp/orchestrate-omp/`, the omp side: `orchestrate` adapted to omp's `task` tool. It dispatches
  parallel workers and reviewers and ends with a fixed `RESULT / COMMITS / VERIFY / REVIEW /
  DEVIATIONS / BLOCKED / NOTES` report.

Install both by linking them, from the repository root:

```bash
ln -s "$PWD/skills/delegate" ~/.claude/skills/delegate
mkdir -p ~/.omp/agent/skills
ln -s "$PWD/skills/delegate/omp/orchestrate-omp" ~/.omp/agent/skills/orchestrate-omp
```
