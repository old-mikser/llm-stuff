---
name: grill
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases. When the user asks for docs too, use grill-docs instead.
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

**Round 1 opens with the premise.** Its Q1 restates, in at most two sentences, the problem the user has and the outcome they want. Every other question in the round builds on that reading, so a wrong premise surfaces on the first answer instead of after a round of misdirected design.

Format a round like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>

---

🔧 **Internals I will decide**: <one line each; the user may veto any>
```

Number questions continuously across the whole session: if round 1 ends at Q5, round 2 starts at Q6. A question you ask again, because its answer was missing or unclear, goes back into the numbered list under a new number, never into prose above the round.

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

**Decisions are the user's; internals are yours.** Put to the user what they will see, use, or pay for: scope, behaviour, the surface they touch, trade-offs in cost or risk. Decide the mechanics yourself: storage layout, keys, process lifecycle, algorithms, how a tool works under the hood. List those choices under **Internals I will decide** at the end of the round, so the user can veto one without being asked about each.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.
