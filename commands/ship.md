---
description: Run the ship-planner -> ship-coder -> ship-tester -> ship-reviewer pipeline for an infra or code change.
argument-hint: <change request>
---
Run the full change pipeline for: $ARGUMENTS

Execute these stages in order. Do not skip ahead. After each stage, confirm the
handoff file exists before the next. Nothing here may touch the live system — no
service restarts, no firewall applies, no migrations.

0. PRECONDITIONS
   a. VOYAGE GUARD: if `.pipeline/plan.md` exists AND it has any task with
      `Status: pending`/`in-progress`/`failed`, OR a `Project-State: regressed:*` line, a
      voyage is in progress. `/ship` will NOT advance it. STOP and tell me: "A voyage is
      active (N tasks pending) — to continue it, run /voyage (it resumes from plan.md)."
      Only proceed with a one-off /ship change if I explicitly confirm. NEVER delete or
      modify `.pipeline/plan.md` (or `.pipeline/failed/`) — they are durable voyage state.
   b. Clean stale run handoffs only (durable plan.md / failed/ are untouched):
       mkdir -p .pipeline/run && rm -f .pipeline/run/*

1. Delegate to the `ship-planner` subagent with the request above. Wait for
   .pipeline/run/spec.md. If it has OPEN QUESTIONS, STOP and show them to me.

2. Delegate to the `ship-coder` subagent. Wait for .pipeline/run/changes.md.

3. Delegate to the `ship-tester` subagent. Wait for .pipeline/run/test-results.md.
   If any validator failed, STOP and show me the failures.

4. Capture the diff for the read-only reviewer:
       git add -A && git diff --cached > .pipeline/run/diff.txt
   Then delegate to the `ship-reviewer` subagent. Wait for .pipeline/run/review.md
   and show it.

5. Report the final verdict (SHIP / NEEDS WORK / BLOCK). Do NOT commit, apply, or
   restart anything. Leave the working tree staged for my review.
