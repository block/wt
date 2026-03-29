# Conflict Detection

Check for conflicting worktree-related skills or instructions. Do this **once per session**, not on every invocation.

## What to look for

Scan your already-loaded skills, system prompts, and instruction files (e.g., CLAUDE.md, AGENTS.md, codex instructions) for any of the following:

- Skills named `git-worktree`, `worktree`, or similar
- Instructions that reference `git worktree add`, `git worktree remove`, or `git worktree list` as commands to use directly
- Instructions about `isolation: "worktree"` or built-in worktree isolation features
- Parallel directory patterns for worktrees (e.g., `../repo-worktrees/feature-name`)
- Any guidance that contradicts the rules in [rules.md](rules.md)

## How to present a conflict

If you find conflicting guidance, present it to the user clearly:

```
I found conflicting worktree guidance:

1. **This skill (wt)**: Uses the `wt` CLI for all worktree operations.
   It manages paths, metadata, and cleanup automatically.

2. **[Other skill/instruction name]**: Uses raw `git worktree` commands
   with manual path management.

These two approaches are incompatible — using both will lead to
inconsistent worktree state. Which would you like to use?

(a) Keep the wt skill (recommended if wt is installed)
(b) Keep [other skill] and disable wt
(c) Keep both (not recommended — explain why if asked)
```

## Resolution options

### (a) Keep wt, remove the other

- If the conflicting guidance is a skill: suggest the user remove or disable it
- If it's in CLAUDE.md/AGENTS.md: suggest removing the worktree section (the wt skill replaces it)
- If it's a built-in feature: note that the wt skill's rules override it

### (b) Keep the other, disable wt

- Stop using the wt skill for this session
- Follow the other skill's guidance instead

### (c) Keep both (not recommended)

- If the user insists, clarify that the wt skill takes precedence for all worktree creation, removal, and management
- The other skill's guidance is ignored for worktree operations
