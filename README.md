# shipyard

A **Planner → Coder → Tester → Reviewer** pipeline for Claude Code, packaged as an
installable plugin. `/ship` runs one change through spec → implementation → validation → a
structurally read-only security review. `/voyage` plans and builds a whole project by
decomposing it into tasks and looping the pipeline through each. Neither **touches your live
system** — they only write, validate, and (for `/voyage`) commit to your local branch. You
apply and push by hand.

Built for infrastructure-as-code (Podman/Quadlet, Caddy/nginx, nftables, shell
scripts) but works on general app code too.

## Which command?

| You want to… | Use | Result |
|---|---|---|
| One bounded change (a unit, a rule, a script) | `/ship` | a validated, security-reviewed **staged** diff you commit yourself |
| A whole project / multi-step feature | `/voyage` | a roadmap you approve, then per-task **commits** on your branch |

Rule of thumb: single validation → `/ship`; needs a plan → `/voyage`. Running `/ship`
mid-voyage is refused (it points you back to `/voyage` to resume).

## Install

```bash
# In Claude Code, add this repo as a marketplace…
/plugin marketplace add DimitriosBatsinis/shipyard

# …then install the plugin
/plugin install shipyard@shipyard-marketplace
```

Restart Claude Code if prompted. The pipeline is now available in every project.

## Use

```bash
cd /path/to/your/repo
git checkout -b change/my-change   # the reviewer needs a git diff
claude
```

Then inside Claude Code:

```text
/ship add a hardened Quadlet unit for jellyfin, localhost-only, following the existing units in this repo
```

(If `/ship` doesn't resolve, Claude Code namespaces plugin commands —
use `/shipyard:ship`.)

Read the result, then apply it yourself:

```bash
cat .pipeline/run/spec.md .pipeline/run/changes.md .pipeline/run/test-results.md .pipeline/run/review.md
git diff --cached
git commit -m "..."   # your sign-off — the pipeline never commits or applies
```

Add `.pipeline/` to your project's `.gitignore`:

```bash
printf '.pipeline/*\n!.pipeline/.gitkeep\n' >> .gitignore
```

## Project mode — `/voyage`

`/ship` handles one atomic change. `/voyage` plans and builds a **whole project**: it
decomposes your request into an ordered list of small tasks, then auto-loops the pipeline
through each one, committing each task on success.

```text
/voyage add a hardened jellyfin Quadlet unit, a Caddy reverse-proxy route for it, and an nftables allow rule
```

How it works:

1. **Decompose** — `ship-architect` (Opus) reads your repo and writes a roadmap to
   `.pipeline/plan.md`: an ordered DAG of right-sized tasks (single validation, bounded
   file set each). Anything ambiguous is raised as `Open Questions` and stops the run.
2. **Roadmap gate** — you approve the plan before any building begins (the one human gate).
3. **Auto-loop** — for each task in dependency order: `ship-planner` writes that task's spec
   (seeing what earlier tasks already committed), then `ship-coder` → `ship-tester` →
   `ship-reviewer`. A failing tester or a `NEEDS WORK` review is fed back to the coder and
   retried (up to 3 attempts); a `BLOCK`, an exhausted retry budget, or `OPEN QUESTIONS`
   halts the voyage.
4. **Commit per task** — each task that passes review is committed to your branch as
   `voyage: T0x …`, so each reviewer sees only that task's diff and you get clean history,
   rollback, and resumability. Pipeline scratch never lands in commits (staged with
   `git add -A -- ':!.pipeline'`).
5. **Regression gate** — a cheap smoke check runs after each commit; a full re-validation
   (all touched infra + your repo's build/test) runs at checkpoints and at project end.
6. **Resume** — re-run `/voyage` to continue from where it stopped. It reads `plan.md` on
   disk (the source of truth), surfaces *why* a task failed, and offers retry / skip /
   edit-task — or, for a post-commit regression, revert / reset-to-parent / insert-fix-task.
   `/ship` is for one-off changes only: if a voyage is in progress it refuses to run and
   points you back to `/voyage` to resume, and it never touches `plan.md`.

Durable voyage state (`.pipeline/plan.md`, `.pipeline/failed/`) is kept separate from the
ephemeral per-run handoffs (`.pipeline/run/spec.md`, `changes.md`, `test-results.md`,
`review.md`, `diff.txt`), so a `/ship` cleanup can never delete a voyage's roadmap.

Like `/ship`, `/voyage` **never pushes and never touches the live system** — it only writes,
validates, and commits to your local branch. Start it on a clean, non-default branch.

## Examples

### `/ship` — a single change

```bash
cd ~/infra
git checkout -b change/jellyfin-unit   # the reviewer needs a git diff
claude
```

Inside Claude Code:

```text
/ship add a hardened Quadlet unit for jellyfin, localhost-only, following examples/webapp.container
```

The pipeline runs planner → coder → tester → reviewer and stops with a verdict
(`SHIP` / `NEEDS WORK` / `BLOCK`), leaving the change **staged but not committed**. Inspect
the handoffs, then sign off yourself:

```bash
cat .pipeline/run/spec.md .pipeline/run/review.md   # what it did + the verdict
git diff --cached
git commit -m "Add hardened jellyfin Quadlet unit"  # your sign-off — the pipeline never commits
```

(If `/ship` doesn't resolve, use the namespaced `/shipyard:ship`.)

### `/voyage` — a whole project

```bash
cd ~/projects/portfolio
git init -q && git checkout -b voyage/build   # git repo, non-default branch, clean tree
claude
```

Inside Claude Code:

```text
/voyage create a personal portfolio site: a projects gallery, an About Me page, and a skills section
```

`/voyage` decomposes the request, writes `.pipeline/plan.md`, and **stops at the roadmap
gate** for your approval:

```text
# Project: Personal portfolio site
Request: create a personal portfolio site: a projects gallery, an About Me page, and a skills section
Branch: voyage/build
Project-State: ok

## Open Questions
(none)

## Tasks
- [ ] T01 — Scaffold static site structure
  - Goal: base index.html, assets dir, and a build/serve script
  - Touches: index.html, assets/, serve.sh
  - Validation: shell
  - Depends on: none
  - Status: pending
  - Attempts: 0
  - Commit: -
- [ ] T02 — Projects gallery section
  - Goal: gallery markup + styles rendering a list of projects
  - Touches: index.html, assets/styles.css
  - Validation: app
  - Depends on: T01
  - Status: pending
  - Attempts: 0
  - Commit: -
- [ ] T03 — About Me page
  - Goal: about.html linked from the nav
  - Touches: about.html, index.html
  - Validation: app
  - Depends on: T01
  - Status: pending
  - Attempts: 0
  - Commit: -
- [ ] T04 — Skills section
  - Goal: skills block on the home page
  - Touches: index.html, assets/styles.css
  - Validation: app
  - Depends on: T01
  - Status: pending
  - Attempts: 0
  - Commit: -
```

Approve it, and `/voyage` builds each task in dependency order, committing each on success:

```text
voyage: T01 Scaffold static site structure
voyage: T02 Projects gallery section
voyage: T03 About Me page
voyage: T04 Skills section
```

If it stops (a failed task or a regression), just **re-run `/voyage` to resume** — it reads
`plan.md` from disk and offers retry / skip / edit-task (or revert / reset-to-parent /
insert-fix-task for a post-commit regression):

```text
/voyage
```

## What each agent does

- **ship-architect** (Opus) — `/voyage` only; decomposes a project into an ordered task
  roadmap; no implementation.
- **ship-planner** (Opus) — reads your repo, writes a spec; no implementation.
- **ship-coder** (Sonnet) — implements the spec, complete files, no scope creep.
- **ship-tester** (Sonnet) — runs the real validator per file type; never fixes.
- **ship-reviewer** (Opus) — strictly read-only (no shell); verdict only.

## Safety model

- The reviewer has **no Bash**, so "read-only" is structural, not a promise. The
  orchestrator hands it the diff via `.pipeline/run/diff.txt`.
- The reviewer **does not trust the test-results claim** — it reconciles it against
  the diff and source and flags any report it can't reconcile.
- A **SECURITY OVERRIDE** makes any secret/credential/firewall-widening issue
  blocking regardless of green validators.
- Nothing applies, restarts, or migrates. `/ship` ends with a staged tree.
- `/voyage` commits each passing task to your local branch (for per-task diff isolation,
  rollback, and resume) via `git add -A -- ':!.pipeline'` so scratch never lands in a
  commit — but it still **never pushes** and never touches the live system.

## Validator prerequisites

The Tester runs real binaries; install the ones your stack uses on the machine
running Claude Code. A missing binary is reported, not faked:

```bash
# Fedora
sudo dnf install ShellCheck nftables
# Debian/Ubuntu
sudo apt install shellcheck nftables
# caddy / podman / nginx per your stack
```

**Cross-OS note:** the plugin itself is OS-agnostic markdown and runs anywhere
Claude Code runs (macOS, Linux, Windows/WSL). The *infra validators* (`nft`,
`caddy`, `podman`, `systemd-analyze`) assume a Linux host. On other OSes the
pipeline still works for general app code; infra checks just report a missing
binary.

## Publishing your own copy

1. Replace `DimitriosBatsinis` / `DimitriosBatsinis` in `.claude-plugin/plugin.json`,
   `.claude-plugin/marketplace.json`, and `LICENSE`.
2. Push to a **public** GitHub repo named `shipyard` (Claude Code fetches
   marketplaces directly from GitHub).
3. Bump `version` in `plugin.json` on changes — Claude Code uses it as the update
   cache key.

## License

MIT
