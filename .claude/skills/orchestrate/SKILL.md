---
name: orchestrate
description: "Execute one or more plans as orchestrator: subagent per task, two review rounds, report."
disable-model-invocation: true
---

You are the orchestrator. Execute plan(s): $ARGUMENTS

Keep the main session clean: run each task as a separate subagent (for some tasks, separate subagents even for subtasks). Opus for tasks that need some brain, sonnet for mechanical or simple ones. Don't let them interfere with each other when running in parallel, and don't let them balloon context: decompose wisely. Let agents commit. Don't retest every minor change; optimize on that. Tell me if you need anything. Do all the work in main. Don't redeploy.

## Steps

1. **Map the work.** Read each plan's task and step headers, plus the sections a task points at. List each task's files. Tasks with disjoint files may run in parallel; tasks sharing a file run in sequence. Check `ListAgents` for other sessions working in this repo or a companion repo and message them which files you will touch.
2. **Dispatch.** One subagent per task (or subtask). Every prompt starts with the contents of [`subagent-brief.md`](subagent-brief.md), then the task: plan path, task number, its file list, the facts earlier tasks reported that it needs, and which files a parallel agent owns. When a report arrives, check it against the brief's report format before dispatching the next task; resume an agent whose report is missing its sha or test result.
3. **Verify once.** After the last implementation commit: clean tree, then the repo's full build, test and lint command once.
4. **Review round 1.** Dispatch an opus code reviewer, read-only, over the whole commit range against the plans' stated intent (behaviour changes, invariants, hot-path cost, lost coverage). Act on its findings through a subagent that commits.
5. **Review round 2.** Dispatch an opus reviewer over the fix commits only. Act on what it finds.
6. **Close the plans.** Update each plan's status line in the repo's own format: today's date from `date`, every commit by sha (listed, not a range), and what is not done (deploys, operator steps). Commit it.
7. **Report:** commits per plan, what each review found and what changed, and what is left for me.
