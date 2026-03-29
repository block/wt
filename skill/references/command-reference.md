# Command Reference

## wt add

Create a new worktree.

```
wt add -b <branch>                  # New branch, auto-path
wt add -b <branch> <path>           # New branch, explicit path
wt add <existing-branch>            # Existing branch, auto-path
wt add <path> <branch> [...]        # Passed directly to git worktree add
```

The auto-path is `$WT_WORKTREES_BASE/<branch-name>`.

**Examples:**
```bash
wt add -b guodong/add-logging           # Creates worktree + new branch
wt add feature/existing-branch          # Creates worktree for existing branch
```

After creation, `cd` into the worktree path printed by the command.

## wt list

List all worktrees with status indicators.

```
wt list                             # Quick list
wt list -v                          # Verbose: show dirty/ahead/behind
```

Output shows the context name, each worktree path, branch, and markers like `[main]` (main repo) and the pin icon for the current context.

## wt remove

Remove one or more worktrees.

```
wt remove                           # Interactive: pick from menu
wt remove <worktree|branch> ...     # Remove specific worktrees
wt remove --merged                  # Remove all with merged branches
```

**Flags:**
| Flag | Description |
|------|-------------|
| `-y`, `--yes` | Skip confirmation prompts |
| `-b`, `--branch` | Also delete the git branch |
| `--merged` | Remove all worktrees whose branches are merged (regular + squash) |
| `--on-dirty=MODE` | `warn` (default), `skip`, or `remove` |

**Examples:**
```bash
wt remove guodong/old-feature       # Remove by branch name
wt remove --merged -b               # Remove merged worktrees + delete branches
wt remove --merged --on-dirty=skip  # Remove merged, skip dirty ones
```

## wt switch

Update the active worktree symlink. This is how IDEs (IntelliJ) see a "branch switch" without re-importing.

```
wt switch                           # Interactive: pick from menu
wt switch <worktree|branch>         # Switch to specific worktree
```

## wt cd

Change directory to a worktree. Requires an interactive shell with `wt.sh` sourced.

```
wt cd                               # Interactive: pick from menu
wt cd <worktree|branch>             # Go to specific worktree
```

In scripts or non-interactive shells, use:
```bash
cd "$(wt-cd <worktree|branch>)"
```

## wt context

Manage repository contexts for multi-repo support.

```
wt context                          # Interactive: pick context to switch to
wt context <name>                   # Switch to named context
wt context --list                   # List all contexts
wt context add                      # Add new context (interactive)
wt context add <path>               # Add context for repo at path
wt context add <name> <path>        # Add context with specific name
wt context remove [name]            # Remove a context
```

## wt metadata-export / wt metadata-import

Manage IDE project metadata (`.ijwb`, `.idea`, `.vscode`, etc.).

```
wt metadata-export [src] [vault]    # Export metadata to vault
wt metadata-import [worktree]       # Import metadata into worktree
wt metadata-import [vault] [wt]     # Import from specific vault
```

These commands preserve IDE configuration across worktrees so you don't need to re-setup your IDE for each new worktree.
