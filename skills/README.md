# wt AI Agent Skill

An AI agent skill that teaches coding assistants (Claude Code, Codex, Cursor, etc.) to use the `wt` CLI for git worktree management instead of raw `git worktree` commands or built-in worktree isolation.

## How it works

When an agent needs to create or manage worktrees, this skill guides it through a structured flow:

1. **Check availability** — Is `wt` installed? If not, walk the user through installation.
2. **Detect conflicts** — Are there other worktree-related skills loaded? If so, ask the user which to keep.
3. **Decide** — Does this task actually need a worktree? Not every change does.
4. **Follow the rules** — Use `wt` commands, never raw `git worktree`. Follow the branch naming convention.
5. **Execute** — Run `wt add`, `wt list`, `wt remove`, etc. For subagents, each gets its own worktree.
6. **Handle errors** — Consult troubleshooting steps. If stuck, suggest filing an issue.

## Installation

### Claude Code

Copy the `skill/` directory to your skills location:

```bash
# Personal (available in all projects)
cp -r skill/ ~/.claude/skills/wt/

# Project-scoped (available in this project only)
cp -r skill/ .claude/skills/wt/
```

### Other agents

Copy the files to your agent's skill/plugin directory, or include the content of `SKILL.md` and the relevant reference files in your agent's instruction set.

## Architecture — lazy loading

Only `SKILL.md` is loaded into context when the skill activates. The 9 reference files in `references/` are loaded **on demand** — only when the agent follows a link from `SKILL.md`.

This keeps context usage minimal:
- A simple `wt add` might only load `rules.md` + `command-reference.md`
- Error handling adds `troubleshooting.md`
- Subagent workflows add `subagent-pattern.md`
- The full set never loads at once unless every concern is relevant in a single session

## Things to note

- **Agent-agnostic** — No Claude-specific APIs or fields. Works with any AI coding assistant that supports markdown-based skill definitions.
- **No silent installs** — The skill does not auto-install `wt` or the JetBrains plugin. It always asks the user first.
- **No auto-filing issues** — The skill suggests filing issues when stuck but never does it without explicit permission.
- **Replaces CLAUDE.md worktree sections** — If you have worktree instructions in your CLAUDE.md or AGENTS.md, this skill is more comprehensive and can replace them.
- **Conflict-aware** — The skill detects other worktree skills (like a generic `git-worktree` skill) and prompts the user to choose, avoiding contradictory guidance.

## File structure

```
skill/
├── README.md                   # This file (for humans)
├── SKILL.md                    # Entry point (for AI agents)
└── references/
    ├── rules.md                # Core constraints and naming conventions
    ├── command-reference.md    # Full wt command reference
    ├── subagent-pattern.md     # Worktree-per-subagent workflow
    ├── installation.md         # CLI + JetBrains plugin install
    ├── conflict-detection.md   # Detect and resolve conflicting skills
    ├── when-to-use.md          # Decision heuristic: worktree vs. not
    ├── troubleshooting.md      # Common errors + self-resolution
    ├── examples.md             # Concrete scenarios
    └── contributing.md         # Issue filing + contribution prompt
```
