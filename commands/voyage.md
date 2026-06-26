---
description: Plan and build a WHOLE project: decompose into tasks, then auto-loop ship-planner -> ship-coder -> ship-tester -> ship-reviewer per task, committing each.
argument-hint: <project request>
---
Run the full PROJECT pipeline for: $ARGUMENTS

This is the project-scale sibling of `/ship`. It decomposes a whole project into ordered
tasks, then drives each task through the build/validate/review pipeline, committing each
task on success. Nothing here may touch the live system — no service restarts, no firewall
applies, no migrations, and NEVER `git push`.

## State lives in files, not in your memory

`.pipeline/plan.md` is the single source of truth for progress. RE-READ it FRESH FROM DISK
at the top of EVERY loop iteration and recompute the next task from it. NEVER carry the task
list in working memory — a voyage is many subagent round-trips and must survive interruption.

## Staging rule (use everywhere you stage, diff, or commit)

Always stage with a pathspec that excludes the scratch dir:

    git add -A -- ':!.pipeline'

Then `git diff --cached > .pipeline/run/diff.txt` for the reviewer, and `git commit` for a task.
This guarantees pipeline scratch (spec.md, changes.md, diff.txt, failed/, the churning
plan.md) never enters a task commit or the reviewer's diff, regardless of the target repo's
`.gitignore`. (Belt-and-suspenders: if `.pipeline/` is not already ignored, you may append it
to the project `.gitignore`, but the pathspec exclude is what makes this correct.)

## Failure model

- RECOVERABLE (retry, don't halt): tester red; reviewer `NEEDS WORK`.
- UNRECOVERABLE (halt, surface, leave state for resume): retry budget exhausted (3 coder
  attempts); spec `OPEN QUESTIONS`; reviewer `BLOCK`; regression gate red; budget guard hit.

## Pipeline

0. PRECONDITIONS / ROUTING
   - Must be a git repo on a NON-default branch (commits + the reviewer's diff need it).
   - Working tree must be CLEAN: if `git status --porcelain` is non-empty, STOP and ask me
     to commit/stash first (so task 1's commit doesn't sweep up pre-existing edits).
   - `mkdir -p .pipeline/run` (creates the ephemeral handoff dir and `.pipeline` itself;
     the durable `plan.md` and `failed/` live at the `.pipeline/` top level).
   - Read `.pipeline/plan.md` from disk if it exists and route:
       * `Project-State: regressed:<T>`  -> go to REGRESSION RESUME (step 6b), even if all
         tasks are done.
       * any task `failed`/`blocked`, or `pending` tasks remain  -> go to RESUME (step 5).
       * otherwise (no plan.md)  -> fresh plan (step 1).

1. DECOMPOSE
   Delegate to the `ship-architect` subagent with the request above. Wait for
   `.pipeline/plan.md`. If its `## Open Questions` is not "(none)", STOP and show them.

2. ROADMAP GATE (the single planned human gate)
   Show `.pipeline/plan.md` and ask me to approve the roadmap before any building begins.

3. LOOP — top of each iteration
   - RE-READ `.pipeline/plan.md` from disk.
   - BUDGET GUARD:
       * Max-task cap (default 20 tasks built this voyage): exceeded -> halt + report.
       * Checkpoint pause every 5 completed tasks: pause, run a FULL regression
         (`ship-tester` regression mode, level=full), show progress, and wait for my go.
       * Track total coder/agent invocations; if a configured ceiling is hit -> halt + report.
     (Token metering isn't available here; the budget is task + invocation counts plus the
     checkpoint pauses.)

4. PICK & BUILD THE NEXT TASK
   Pick the next task T with `Status: pending` AND every `Depends on` task `done`
   (topological order). If pending tasks exist but none are eligible, report the
   blocked/stranded tasks and STOP.
   a. If `.pipeline/run/spec.md` etc. exist from a prior attempt, archive them to
      `.pipeline/failed/<T-id>/`; then clear live handoffs:
          rm -f .pipeline/run/spec.md .pipeline/run/changes.md .pipeline/run/test-results.md \
                .pipeline/run/review.md .pipeline/run/diff.txt
   b. Set T `Status: in-progress` and `Attempts: 0` in plan.md.
   c. Delegate to the `ship-planner` subagent for task T. Tell it the task id and that
      `.pipeline/plan.md` exists (project mode). Wait for `.pipeline/run/spec.md`. If it has
      OPEN QUESTIONS, archive handoffs, set T `Status: failed`, and STOP.
   d. PER-TASK RETRY LOOP (orchestrator-level — ship-coder does NOT self-iterate).
      Attempts are FIX-FORWARD: the tree is NOT reset between attempts. For attempt 1..3:
        i.   Delegate to `ship-coder`. On attempt > 1, tell it to read the prior
             `.pipeline/run/test-results.md` / `.pipeline/run/review.md` as fix-this feedback, and
             to DELETE any wrong-path files left by the previous attempt. Wait for
             `.pipeline/run/changes.md`. Increment T `Attempts`.
        ii.  Delegate to `ship-tester`. Wait for `.pipeline/run/test-results.md`.
               - RED: if attempts remain, loop (feedback carries to the next coder run);
                 else EXHAUSTED -> go to (f) FAIL.
        iii. Stage and capture the diff, then review:
                 git add -A -- ':!.pipeline'
                 git diff --cached > .pipeline/run/diff.txt
             Delegate to `ship-reviewer`. Wait for `.pipeline/run/review.md`.
               - SHIP        -> success, go to (e).
               - NEEDS WORK  -> if attempts remain, loop (feedback to coder); else
                                EXHAUSTED -> (f) FAIL.
               - BLOCK       -> (f) FAIL (unrecoverable).
   e. SUCCESS:
          git add -A -- ':!.pipeline'
          git commit -m "voyage: <T-id> <task title>"
      Record the commit SHA and set T `Status: done` (and `[x]`) in plan.md.
      Then run a CHEAP SMOKE regression: delegate to `ship-tester` in regression mode
      (level=smoke) on the just-committed files. If RED, set
      `Project-State: regressed:<T-id>` in plan.md and STOP (go to step 6). Otherwise
      continue the LOOP (step 3).
   f. FAIL: archive handoffs AND the current diff to `.pipeline/failed/<T-id>/`; set T
      `Status: failed`; STOP and surface exactly why (the captured tester/review output).
      The working tree is left dirty with the failed attempt — resume decides what to do.

5. RESUME (build/spec failure — dirty tree, task NOT committed)
   Read `.pipeline/failed/<T-id>/` and surface WHY the task failed. Detect the dirty tree
   and offer me:
     - retry      -> `git reset --hard HEAD && git clean -fd` (prior tasks are committed,
                     so this restores to the last good commit), then re-attempt T with the
                     failure diagnostics available to the planner+coder.
     - skip       -> set T `Status: skipped`; set every TRANSITIVE dependent of T to
                     `Status: blocked` (do NOT leave them dangling as silent pending),
                     report them, and continue with still-eligible tasks.
     - edit-task  -> let me amend T in plan.md, then retry.
   Never blind-retry on a dirty tree.

6. REGRESSION (fires AFTER a successful commit — tree is CLEAN, task is done, HEAD is the
   boundary commit)
   a. On detection set `Project-State: regressed:<T-id>` and that task's `Status: regressed`,
      then STOP. ATTRIBUTION: with per-task commits you CANNOT truly bisect a culprit —
      attribute the regression to the COMMIT BOUNDARY whose regression pass first went red,
      not to a precisely identified cause.
   b. REGRESSION RESUME: surface the failing regression output. Do NOT use the dirty-tree
      retry flow (the tree is clean; `reset --hard HEAD` would keep the bad commit). Offer:
        - revert       -> `git revert <commit>` (keeps history; adds an inverse commit).
        - reset-parent -> `git reset --hard <commit>^` (drops the bad commit; warn this
                          discards it and anything committed after it).
        - fix-task     -> insert a new fix task into plan.md and run it through the loop.
      Once the regression pass is green again, set `Project-State: ok` and continue.

7. DONE
   Run the END-OF-PROJECT FULL regression (`ship-tester` regression mode, level=full).
   Report the summary: tasks built, commits (SHAs), branch, and the regression result. Do
   NOT push, apply, restart, or migrate. Leave the branch for me to review and merge.
