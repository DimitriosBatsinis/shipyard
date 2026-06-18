---
description: Run the ship-planner -> ship-coder -> ship-tester -> ship-reviewer pipeline for an infra or code change.
argument-hint: <change request>
---
Run the full change pipeline for: $ARGUMENTS

Execute these stages in order. Do not skip ahead. After each stage, confirm the
handoff file exists before the next. Nothing here may touch the live system — no
service restarts, no firewall applies, no migrations.

0. Clean stale handoffs:
       rm -f .pipeline/*.md .pipeline/diff.txt && mkdir -p .pipeline

1. Delegate to the `ship-planner` subagent with the request above. Wait for
   .pipeline/spec.md. If it has OPEN QUESTIONS, STOP and show them to me.

2. Delegate to the `ship-coder` subagent. Wait for .pipeline/changes.md.

3. Delegate to the `ship-tester` subagent. Wait for .pipeline/test-results.md.
   If any validator failed, STOP and show me the failures.

4. Capture the diff for the read-only reviewer:
       git add -A && git diff --cached > .pipeline/diff.txt
   Then delegate to the `ship-reviewer` subagent. Wait for .pipeline/review.md
   and show it.

5. Report the final verdict (SHIP / NEEDS WORK / BLOCK). Do NOT commit, apply, or
   restart anything. Leave the working tree staged for my review.
