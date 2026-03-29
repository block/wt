# When to Use a Worktree

Not every task needs a worktree. Use this guide to decide.

## Use a worktree when

- **Spawning subagents** for parallel work — each subagent gets its own worktree
- **Large multi-file refactors** that could break the build mid-way
- **Risky or experimental changes** you may want to discard entirely
- **Reviewing someone else's PR** without disturbing your current work
- **Working on a separate feature** while another feature is in-progress on the current branch
- **Long-running tasks** where you need to switch back to the main branch mid-work

## Don't use a worktree when

- **Single-file edits** or small changes
- **Quick bug fixes** that can be committed immediately
- **Reading or exploring code** (no changes needed)
- **Running tests** on the current branch
- **Changes that don't need isolation** from the current working directory

## Rule of thumb

If the work could be done in a single commit on the current branch without disrupting anything, skip the worktree.

If you'd normally say "let me switch to a new branch for this" — that's when `wt add -b` is the right call.
