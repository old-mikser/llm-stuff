---
name: verify-review
description: Verify a pasted review, audit, or report claim by claim against primary sources, then give a plain-English verdict and your own fix plan. Use when the user pastes a review, report, or plan critique and asks to verify, check, or push back on it.
---

Treat the review as a list of **claims** to re-derive, never as evidence. Stay read-only until the user picks fixes: no edits, no commits, no restarts.

## Steps

1. **Pin the baseline.** Record HEAD, `git status`, and the commit the review cites. If they differ, diff the cited files between them. Done: you can name the commit each verdict holds at.
2. **Split into claims.** One row per finding, in the review's numbering. A finding cut off in the paste gets the row "cut from paste". The review's evidence tables are claims too, provenance labels included ("checked at block N", "from the live DB").
3. **Re-derive each claim** from the primary source, not the review's quote: the cited line, the chain at the claimed block, the DB with its coverage. Re-run every number at the review's **pin** (commit, block, time window). If the pin is unreachable, for example a pruned node, move to an archive; if none exists, mark the number "unverified at pin". A latest-state read that matches the review proves only that the review read latest state too. Done: every claim has its own evidence, labelled code / chain@block / DB.
4. **Grade fact and fix apart.** Verdicts: Confirmed · True, not reachable today · Partly wrong · Refuted · Unverified. A true finding often carries a wrong fix, so test the fix on its own. Test both against the repo's ADRs and recorded operator decisions.
5. **Look past the review** for issues in the same code that it missed.
6. **Report** in the format below, then stop for rulings.

## Report

- Line 1: the verdict counts and the most severe item.
- Baseline: the commit, and whether the tree was clean.
- Table: #, claim in 8 words or fewer, verdict, anchor (`file:line`, block, or query).
- Per finding worth fixing:
  - **What breaks:** one sentence a non-coder can follow: what goes wrong, when, and what it costs.
  - **Fix:** yours, where it differs from the review's.
  - **Why:** the evidence that picks this fix.
- **Where I disagree:** evidence first, then reasoning.
- **New issues:** the same three fields.

Define each code term in plain words the first time the report uses it. Keep formulas out of "What breaks"; put them under "Why" when they carry the argument. End with the numbered findings, so the user can reply "1 fix, 2 skip, 3 explain".
