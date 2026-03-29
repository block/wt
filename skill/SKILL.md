---
name: wt
description: Use when creating, managing, listing, removing, or switching git worktrees. Also use when spawning subagents that need isolated workspaces for parallel development.
---

# wt — Worktree Toolkit

Manage git worktrees using the `wt` CLI. Follow these steps in order.

## Step 0 — Availability check

Run `wt list`. If the command is not found (common in non-interactive shells), try `~/.wt/bin/wt list` directly. If neither works, follow [references/installation.md](references/installation.md) and **stop**. Do not fall back to raw `git worktree` commands or `source ~/.wt/wt.sh`.

**Important**: In non-interactive shells (scripts, AI agents), always use `~/.wt/bin/wt` if `wt` is not in PATH. Do not attempt to source `wt.sh` — it requires an interactive shell.

## Step 1 — Conflict detection

Check your loaded skills and instructions for conflicting worktree guidance. See [references/conflict-detection.md](references/conflict-detection.md). Resolve before proceeding.

## Step 2 — Decide

Is a worktree needed for this task? See [references/when-to-use.md](references/when-to-use.md). Not every change needs one.

## Step 3 — Follow the rules

See [references/rules.md](references/rules.md) for what is and isn't allowed.

## Step 4 — Execute

Use the commands in [references/command-reference.md](references/command-reference.md).

For spawning subagents in isolated worktrees, follow [references/subagent-pattern.md](references/subagent-pattern.md).

For concrete scenarios, see [references/examples.md](references/examples.md).

## On errors

Consult [references/troubleshooting.md](references/troubleshooting.md). If unresolvable, see [references/contributing.md](references/contributing.md).
