# shipyard

A four-agent **Planner → Coder → Tester → Reviewer** pipeline for Claude Code,
packaged as an installable plugin. One slash command, `/ship`, runs a change
through spec → implementation → validation → a structurally read-only security
review, and **never touches your live system** — it only writes and validates
files. You apply by hand.

Built for infrastructure-as-code (Podman/Quadlet, Caddy/nginx, nftables, shell
scripts) but works on general app code too.

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
cat .pipeline/spec.md .pipeline/changes.md .pipeline/test-results.md .pipeline/review.md
git diff --cached
git commit -m "..."   # your sign-off — the pipeline never commits or applies
```

Add `.pipeline/` to your project's `.gitignore`:

```bash
printf '.pipeline/*\n!.pipeline/.gitkeep\n' >> .gitignore
```

## What each agent does

- **ship-planner** (Opus) — reads your repo, writes a spec; no implementation.
- **ship-coder** (Sonnet) — implements the spec, complete files, no scope creep.
- **ship-tester** (Sonnet) — runs the real validator per file type; never fixes.
- **ship-reviewer** (Opus) — strictly read-only (no shell); verdict only.

## Safety model

- The reviewer has **no Bash**, so "read-only" is structural, not a promise. The
  orchestrator hands it the diff via `.pipeline/diff.txt`.
- The reviewer **does not trust the test-results claim** — it reconciles it against
  the diff and source and flags any report it can't reconcile.
- A **SECURITY OVERRIDE** makes any secret/credential/firewall-widening issue
  blocking regardless of green validators.
- Nothing applies, restarts, or migrates. The pipeline ends with a staged tree.

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
