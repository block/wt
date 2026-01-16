# Worktree Toolkit

A streamlined workflow for developing in large Bazel + IntelliJ monorepos using Git worktrees.

Enables instant IntelliJ context switching between worktrees—no re-imports, no re-indexing—and scales to support parallel development by humans and AI agents alike.

## Overview

Git worktrees let you work on multiple branches in parallel, but IntelliJ treats each worktree as a separate project, requiring expensive Bazel syncs and index rebuilds every time you switch to a new worktree.

This toolkit makes IntelliJ context switching **instant** by:

- **Symlink trick**: IntelliJ always opens the same path; switching worktrees looks like a branch checkout → incremental refresh in seconds, not minutes
- **Metadata vault**: `.ijwb` directories are stored externally and automatically installed into every new worktree—no manual Bazel import needed
- **Safe worktree management**: Automatic stash/restore, branch creation, and cleanup of merged branches
- **Parallel development at scale**: Works for humans and AI agents alike

📊 See the [presentation slides](presentation/slides.pdf) for a visual walkthrough.

## Quick Start

```bash
# Install (interactive prompts for configuration)
./install.sh

# Reload shell
source ~/.zshrc

# Use
wt help
```

The installer will:
1. Copy the toolkit to `~/.config/wt/`
2. Add sourcing to your shell rc file
3. Prompt for workspace paths (main repo, worktrees, metadata vault)
4. Create required directories
5. Optionally migrate existing repo to worktree structure
6. Optionally export `.ijwb` metadata to the vault
7. Optionally set up a nightly cron job to refresh `.ijwb` metadata

## Workflow

### Initial Setup

The directory structure expected (controlled by environment variables, can be overwritten):

```
~/Development/
├── java -> java-master          # Symlink (IntelliJ opens this)
├── java-master/                 # Main repository
├── java-worktrees/              # Worktrees go here
└── idea-project-files/          # .ijwb metadata vault
```

### Full Workflow Diagram

```
                      ┌─────────────────────────────────────────────┐
                      │   External IntelliJ Metadata Vault          │
                      │  ~/Development/idea-project-files           │
                      │    (canonical .ijwb directories)            │
                      └──────────▲───────────────┬──────────────────┘
                                 │               │ 
                                 │               │
           ┌────wt ijwb-export───┘               └───wt ijwb-import──┐
           │                                                         │
┌──────────┴───────────────────────┐                     ┌───────────▼────────────────────────┐
│   Main Repository                │                     │    Worktrees                       │
│ ~/Development/java-master        │       wt add        │ ~/Development/java-worktrees/...   │
│  • master branch                 │ ──────────────────► │  • feature/foo                     │
│  • safe stash/pull/restore       │ (calls ijwb-import) │  • bugfix/bar                      │
│  • never removed                 │                     │  • agent-task-123                  │
└───────────────┬──────────────────┘                     └─────────┬──────────────────────────┘
                │                                                  │
             wt switch                                          wt remove
                │                                                  │
    ┌───────────▼──────────────────┐                     ┌─────────▼────────────┐
    │ Stable IntelliJ Project Dir  │                     │  Safe cleanup with   │
    │ ~/Development/java           │                     │  confirmation prompt │
    │ (symlink updated per switch) │                     └──────────────────────┘
    └───────────▲──────────────────┘
                │ 
          IntelliJ auto-refresh
                │
     ┌──────────▼───────────────────┐
     │ IntelliJ loads worktree      │
     │ instantly (no import needed) │
     └──────────────────────────────┘
```


### Creating Worktrees

```bash
# Existing branch
wt add feature/foo

# New branch (from latest master)
wt add -b feature/foo
```

When creating with `-b`, the script:
1. Stashes uncommitted changes
2. Switches to master, pulls latest
3. Creates branch + worktree
4. Imports .ijwb metadata
5. Restores original state

### Switching Worktrees

```bash
# Interactive
wt switch

# Direct
wt switch ~/Development/java-worktrees/feature/foo
```

Updates the symlink so IntelliJ instantly loads the new worktree.

### Navigation

```bash
# Interactive cd
wt cd

# Direct cd
wt cd ~/Development/java-worktrees/feature/foo
```

### Listing Worktrees

```bash
wt list
```

Shows all worktrees with status indicators:
- `*` = Currently linked worktree
- `[main]` = Main repository root
- `[linked]` = Active symlink target
- `[dirty]` = Has uncommitted changes
- `[↑N]` / `[↓N]` = Commits ahead/behind upstream

### Removing Worktrees

```bash
# Interactive
wt remove

# Direct (with confirmation)
wt remove ~/Development/java-worktrees/feature/foo

# Skip confirmation (unless uncommitted changes exist)
wt remove -y ~/Development/java-worktrees/feature/foo

# Remove all worktrees with branches merged into base branch
wt remove --merged

# Auto-remove merged without prompts (skips worktrees with uncommitted changes)
wt remove --merged -y
```

Safety features:
- Warns if the worktree is currently linked (symlink will be switched to main repo)
- Warns if there are uncommitted changes (shows summary)
- Always prompts for confirmation if uncommitted changes exist, even with `-y`
- `--merged` mode: automatically finds and removes all worktrees whose branches are merged

### Managing IntelliJ Metadata

```bash
# Export .ijwb from main repo to vault (run after importing new Bazel projects)
wt ijwb-export

# Import .ijwb into a worktree (interactive selection if target omitted)
wt ijwb-import
wt ijwb-import ~/Development/java-worktrees/feature/foo

# Skip confirmation prompts (useful in scripts)
wt ijwb-export -y
wt ijwb-import -y ~/Development/java-worktrees/feature/foo
```

### Refreshing Stale .ijwb Metadata (Cron Job)

When most development work is done in worktrees, the `.ijwb` directories in the main repository can become stale (targets files don't reflect new Bazel targets).

The `lib/wt-ijwb-refresh` script is designed to run as a cron job to keep metadata current.

**Note:** When IntelliJ has `derive_targets_from_directories: true` in `.bazelproject` (the default), it queries Bazel fresh on every sync. The `targets-*` file serves as a cache for initial project imports and may improve import speed.

**Note:** The installer (`install.sh`) offers to set up this cron job automatically (default: yes).

To set it up manually:

```bash
# Create log directory
mkdir -p ~/.config/wt/logs

# Edit crontab
crontab -e

# Add this line to run nightly at 2am (uses login shell for full PATH):
0 2 * * * /bin/zsh -lc '~/.config/wt/lib/wt-ijwb-refresh' >> ~/.config/wt/logs/ijwb-refresh.log 2>&1
```

You can also run the script manually:

```bash
# Refresh all .ijwb directories and re-export to vault
~/.config/wt/lib/wt-ijwb-refresh

# Preview what would be refreshed (dry run)
~/.config/wt/lib/wt-ijwb-refresh --dry-run

# Refresh targets files only (skip re-export step)
~/.config/wt/lib/wt-ijwb-refresh --no-export
```

The refresh script:
- Uses `bazel query` to regenerate `targets/targets-*` files in each `.ijwb` directory
- Parses `.bazelproject` to determine which directories to include in the query
- Preserves existing targets file hashes (IntelliJ may reference them)
- Re-exports refreshed metadata to the vault
- Logs timestamped output for monitoring
- Returns exit codes: 0=success, 1=error, 2=partial success


## Configuration: Environment Variables
The scripts rely on a few environment variables to know where your
main repository, worktrees, and IntelliJ metadata live.

These environment variables are set in `wt-common` with built-in defaults.
If set in your shell configuration, they take precedence over the built-in defaults.

| Variable | Default | Purpose |
|----------|---------|---------|
| `WT_MAIN_REPO_ROOT` | `~/Development/java-master` | Main repository root |
| `WT_WORKTREES_BASE` | `~/Development/java-worktrees` | Where worktrees are created |
| `WT_IDEA_FILES_BASE` | `~/Development/idea-project-files` | IntelliJ metadata vault |
| `WT_ACTIVE_WORKTREE` | `~/Development/java` | Symlink to active worktree |
| `WT_BASE_BRANCH` | `master` | Default branch for new worktrees |

### WT_MAIN_REPO_ROOT
Path to your primary git repository clone.

**Default:** `~/Development/java-master`

```bash
export WT_MAIN_REPO_ROOT="$HOME/Development/java-master"
```

Used by:
- wt-add (for stash/restore & base branch operations)
- wt-choose (listing worktrees)
- wt-switch (default symlink target)
- wt-remove (safety check to prevent removing main repo)


### WT_WORKTREES_BASE
Directory where new worktrees are created by default.

**Default:** `~/Development/java-worktrees`

```bash
export WT_WORKTREES_BASE="$HOME/Development/java-worktrees"
```


### WT_IDEA_FILES_BASE
Canonical metadata vault storing `.ijwb` directories.

**Default:** `~/Development/idea-project-files`

```bash
export WT_IDEA_FILES_BASE="$HOME/Development/idea-project-files"
```

Used by:
- wt-ijwb-import
- wt-ijwb-export
- wt-ijwb-refresh
- wt-add (when installing metadata)


### WT_ACTIVE_WORKTREE
Symlink path that points to the currently active worktree. This is where IntelliJ should open the project.

**Default:** `~/Development/java`

```bash
export WT_ACTIVE_WORKTREE="$HOME/Development/java"
```

Used by:
- wt-switch (updates this symlink)
- wt-remove (warns if removing the linked worktree)


### WT_BASE_BRANCH
Name of the mainline branch to branch from.

**Default:** `master`

```bash
export WT_BASE_BRANCH="master"
```

## Presentation

A 10-minute overview presentation is available in the `presentation/` directory:

- `slides.md` — Marp markdown source
- `slides.pdf` — Generated PDF

To regenerate the PDF from the markdown:

```bash
npx @marp-team/marp-cli presentation/slides.md -o presentation/slides.pdf
```

## Directory Structure

```
wt/
├── wt.sh                    # Entry point (source this)
├── presentation/            # Overview slides
├── bin/                     # Executable commands
│   ├── wt-add
│   ├── wt-cd
│   ├── wt-list
│   ├── wt-remove
│   ├── wt-switch
│   ├── wt-ijwb-import
│   └── wt-ijwb-export
├── lib/                     # Shared libraries
│   ├── wt-common            # Configuration and helpers
│   ├── wt-choose            # Interactive worktree selection
│   ├── wt-help              # Help text for wt command
│   ├── wt-completion        # Shell completion for wt command
│   └── wt-ijwb-refresh      # Cron script to refresh .ijwb metadata
├── completion/              # Shell completions for wt-* scripts
│   ├── wt.zsh
│   └── wt.bash
├── install.sh
└── WT-README.md
```

## Individual Scripts

You can also run the underlying scripts directly:

```bash
wt-add, wt-switch, wt-remove, wt-list, wt-cd, wt-ijwb-export, wt-ijwb-import
```

These are located in `bin/` and work identically to the `wt` subcommands.

The `lib/wt-ijwb-refresh` script is designed for cron jobs and can be run directly from its location.
