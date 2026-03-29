# Subagent Pattern

How to spawn subagents that work in isolated worktrees.

## When to use

Create a worktree for a subagent when the task needs an isolated copy of the repo:
- Large refactors touching many files
- Parallel feature work (multiple subagents working simultaneously)
- Risky or experimental changes you may want to discard
- Any task where the subagent's edits shouldn't affect the main working directory

## Pattern

Instruct the subagent to:

1. **Create the worktree**: Run `wt add -b <username>/<descriptive-task-name>`
2. **Enter the worktree**: `cd` into the directory path printed by `wt add`
3. **Do the work**: Make changes, run builds/tests, commit
4. **Leave the worktree in place**: Do not remove the worktree when done. The parent agent or user will review the changes and decide whether to merge or discard.

### Example subagent prompt

```
Create a worktree and implement the changes there:

1. Run: wt add -b guodong/refactor-auth-middleware
2. cd into the created worktree directory
3. [describe the implementation task]
4. Commit your changes when done

Do NOT remove the worktree when finished.
```

## Branch naming

Derive the username from `git config user.name` (lowercase, hyphens for spaces). The task name should be descriptive and kebab-case.

Pattern: `<username>/<task-name>`

Examples:
- `guodong/refactor-auth-middleware`
- `guodong/add-order-validation`
- `guodong/fix-kafka-partition-key`

## After completion

The parent agent or user can:
- Review the changes in the worktree
- Merge the branch via PR
- Remove the worktree with `wt remove <branch>` (add `-b` to also delete the branch)
- Batch-clean with `wt remove --merged` after PRs are merged

## What NOT to do

- Never use `isolation: "worktree"` (Claude Code's built-in parameter)
- Never use `git worktree add` directly
- Never create worktrees inside `.claude/`, `.git/`, or other agent-managed directories
- Never remove the worktree from within the subagent (let the parent/user decide)
