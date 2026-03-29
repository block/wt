# Troubleshooting

Common errors and how to resolve them. Handle these without asking the user unless noted.

## `wt: command not found`

**Cause**: PATH not configured for non-interactive shells. This is the most common issue for AI agents.

**Resolution**:
1. Try the full path: `~/.wt/bin/wt list`
2. If that works, use `~/.wt/bin/wt` for all subsequent commands in this session. Also suggest the user add to `~/.zshenv`:
   ```bash
   export PATH="$HOME/.wt/bin:$PATH"
   ```
   Then reload: `source ~/.zshenv`
3. If the full path also fails, `wt` is not installed. See [installation.md](installation.md).

**Do NOT** attempt to `source ~/.wt/wt.sh` — this file must be sourced in an interactive shell and will fail or behave unexpectedly in scripts and agent environments.

## `fatal: '<branch>' is already checked out`

**Cause**: A worktree already exists for that branch. Git only allows one worktree per branch.

**Resolution**:
1. Run `wt list` to find the existing worktree
2. Either:
   - Use the existing worktree (cd into it)
   - Choose a different branch name (e.g., append `-v2`)
   - Remove the old worktree first with `wt remove <branch>`

## `worktree is locked`

**Cause**: A previous process crashed mid-operation, leaving a lock file.

**Resolution**:
```bash
git worktree unlock <worktree-path>
```
Then retry the `wt` command. This is one of the few cases where a raw `git worktree` command is acceptable — `wt` does not have an unlock subcommand.

## `wt remove` fails: dirty worktree

**Cause**: The worktree has uncommitted changes and the default `--on-dirty=warn` is blocking removal.

**Resolution**: Ask the user which approach to take:
- Commit or stash the changes first, then remove
- Skip this worktree: `wt remove --on-dirty=skip <worktree>`
- Force remove (loses changes): `wt remove --on-dirty=remove <worktree>`

Do not force-remove without asking.

## `wt context` shows no contexts

**Cause**: No repository has been configured yet.

**Resolution**:
```bash
wt context add
```
This starts the interactive setup flow. The user will need to provide the path to their repository.

## `wt add` hangs

**Cause**: Large repository, first-time git operations, or slow network (fetching remote).

**Resolution**: This is normal for large repos. Wait for it to complete. Subsequent operations will be faster.

## Unknown error

If the error is not listed here:
1. Check `wt help` or `wt <subcommand> --help` for flag details
2. Check `wt list` to verify the current state
3. If still stuck, see [contributing.md](contributing.md)
