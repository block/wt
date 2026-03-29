# Rules

Core constraints for all worktree operations.

## Always use `wt`

- **Never** use raw `git worktree add`, `git worktree remove`, or `git worktree list`. Always use `wt add`, `wt remove`, `wt list`.
- **Never** use built-in agent worktree isolation. This includes Claude Code's `isolation: "worktree"`, Codex sandbox worktrees, and Cursor worktree features. Always use `wt`.
- **Never** create worktrees inside the repo's `.claude/`, `.git/`, or any agent-managed directory.

## Branch naming

Use `<username>/<descriptive-name>` for all new branches.

To get the username, run:
```bash
git config user.name
```

Then convert to lowercase and replace spaces with hyphens. For example, `Guodong Zhu` becomes `guodong`. If this is the first worktree operation in the session, confirm the username with the user once.

Examples:
- `guodong/add-logging`
- `guodong/fix-auth-timeout`
- `guodong/refactor-order-storage`

## Cleanup

- After work is complete (PR merged, experiment finished), use `wt remove` to clean up.
- Use `wt remove --merged` to batch-remove all worktrees whose branches have been merged.
- Use `wt remove -b` to also delete the git branch after removing the worktree.

## Multi-repo

If working across multiple repositories, use `wt context` to switch between them. Each context has its own worktree directory, metadata vault, and base branch.
