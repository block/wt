# Worktree Toolkit

[![Tests](https://github.com/block/wt/actions/workflows/test.yml/badge.svg)](https://github.com/block/wt/actions/workflows/test.yml)
[![ShellCheck](https://github.com/block/wt/actions/workflows/lint.yml/badge.svg)](https://github.com/block/wt/actions/workflows/lint.yml)
[![Plugin Build](https://github.com/block/wt/actions/workflows/plugin-build.yml/badge.svg)](https://github.com/block/wt/actions/workflows/plugin-build.yml)

A streamlined workflow for developing in large Bazel + IntelliJ monorepos using Git worktrees.

Enables instant IntelliJ context switching between worktrees—no re-imports, no re-indexing—and scales to support parallel development by humans and AI agents alike.

## Overview

Git worktrees let you work on multiple branches in parallel, but IntelliJ treats each worktree as a separate project, requiring expensive Bazel syncs and index rebuilds every time you switch to a new worktree.

This toolkit makes IntelliJ context switching **instant** by:

- **Symlink trick**: IntelliJ always opens the same path; switching worktrees looks like a branch checkout → incremental refresh in seconds, not minutes
- **Metadata vault**: IDE project metadata (`.ijwb`, `.idea`, `.vscode`, etc.) is stored externally and automatically installed into every new worktree—no manual IDE setup needed
- **Safe worktree management**: New branches are created from a freshly fetched base ref without ever touching the main checkout, plus cleanup of merged branches
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
1. Copy the toolkit to `~/.wt/`
2. Add sourcing to your shell rc file
3. Prompt for workspace paths (main repo, worktrees, metadata vault)
4. Create required directories
5. Optionally migrate existing repo to worktree structure
6. Optionally export project metadata to the vault
7. Optionally set up a nightly cron job to refresh Bazel IDE metadata

## Workflow

### Initial Setup

The directory structure expected (controlled by environment variables, can be overwritten):

```
~/Development/
├── java -> java-master          # Symlink (IntelliJ opens this)
├── java-master/                 # Main repository
├── java-worktrees/              # Worktrees go here
└── idea-project-files/          # Project metadata vault
```

### Full Workflow Diagram

```
                      ┌─────────────────────────────────────────────┐
                      │   External Project Metadata Vault           │
                      │  ~/Development/idea-project-files           │
                      │    (IDE configs: .ijwb, .idea, etc.)        │
                      └──────────▲───────────────┬──────────────────┘
                                 │               │
                                 │               │
           ┌──wt metadata-export─┘               └──wt metadata-import─┐
           │                                                           │
┌──────────┴───────────────────────┐                     ┌─────────────▼──────────────────────┐
│   Main Repository                │                     │    Worktrees                       │
│ ~/Development/java-master        │       wt add        │ ~/Development/java-worktrees/...   │
│  • master branch                 │ ──────────────────► │  • feature/foo                     │
│  • never touched by wt add       │(calls metadata-imp) │  • bugfix/bar                      │
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
1. Fetches the latest base branch (`git fetch origin <base>`); a failed fetch warns and falls back to the last-known base ref
2. Creates branch + worktree from `origin/<base>` (or the local base branch when there is no remote), without ever touching the main repo checkout — no stash, no branch switch
3. Imports project metadata from vault
4. Copies configured seed files (`WT_SEED_FILES`, e.g. `user.bazelrc`) from the main repo

Each worktree gets its own Bazel output base (Bazel derives it from the worktree path), so builds in different worktrees never clobber each other. `wt remove` reclaims that disk space automatically.

Set `WT_SKIP_PULL=1` to skip the `git fetch` step (useful offline or in scripts):

```bash
WT_SKIP_PULL=1 wt add -b feature/foo
```

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
wt list -v            # Adds dirty/ahead/behind indicators (slower; worktrees probed in parallel)
wt list --porcelain   # Machine-readable output (for scripts and agents)
```

Shows all worktrees with status indicators:
- `*` = Currently linked worktree
- `[main]` = Main repository root
- `[linked]` = Active symlink target
- `[unadopted]` = Worktree not adopted by wt (fix with `wt adopt`)
- `[dirty]` = Has uncommitted changes (with `-v`)
- `[↑N]` / `[↓N]` = Commits ahead/behind upstream (with `-v`)

`--porcelain` prints `git worktree list --porcelain` output augmented with extra
lines per worktree: `wt.active`, `wt.adopted`, and (with `-v`) `wt.dirty`,
`wt.ahead N`, `wt.behind N`.

### Adopting Existing Worktrees

Worktrees created outside `wt` (e.g. with plain `git worktree add`) show as
`[unadopted]` in `wt list`. Adoption imports project metadata from the vault and
marks the worktree as managed by wt:

```bash
wt adopt                          # Adopt the worktree at the current directory
wt adopt <worktree-path|branch>   # Adopt a specific worktree
wt adopt --redo                   # Re-run adoption on an adopted worktree
wt adopt --force                  # Skip conflict checks, overwrite without prompting
```

The main repository cannot be adopted (only worktrees).

### Removing Worktrees

```bash
# Interactive
wt remove

# Direct (with confirmation)
wt remove ~/Development/java-worktrees/feature/foo

# Skip confirmation (unless uncommitted changes exist)
wt remove -y ~/Development/java-worktrees/feature/foo

# Also delete the git branch
wt remove -b feature/foo

# Remove all worktrees with branches merged into base branch
wt remove --merged

# Remove merged without prompts, skipping worktrees with uncommitted changes
wt remove --merged -y --on-dirty=skip
```

Flags:
- `-y`/`--yes` = Skip confirmation prompts (dirty worktrees still prompt unless `--on-dirty` says otherwise)
- `-b`/`--branch` = Also delete the git branch after removing the worktree
- `--merged` = Remove all worktrees whose branches are merged (regular + squash)
- `--on-dirty=MODE` = What to do with uncommitted changes: `warn` (default, prompts), `skip`, or `remove`

Safety features:
- Warns if the worktree is currently linked (symlink will be switched to main repo)
- Warns if there are uncommitted changes (shows summary)
- Always prompts for confirmation if uncommitted changes exist, even with `-y` (use `--on-dirty=skip` or `--on-dirty=remove` to override)
- `--merged` mode: automatically finds and removes all worktrees whose branches are merged

After a successful removal, `wt remove` also reaps the worktree's dedicated Bazel output base (best-effort): it locates the output base named after the md5 hash of the worktree path under the known Bazel output user roots (`~/Library/Caches/bazel/_bazel_$USER`, `/private/var/tmp/_bazel_$USER`, `~/.cache/bazel/_bazel_$USER`), verifies it contains `execroot/`, deletes it, and reports the disk space freed. If no matching output base exists, nothing is printed; cleanup failures only warn and never fail the removal.

### Multi-Repo Contexts

`wt` can manage worktrees for multiple repositories. Each repository is a named
context whose configuration lives in `~/.wt/repos/<name>.conf`:

```bash
wt context                       # Interactive: pick context to switch to
wt context <name>                # Switch to named context
wt context --list                # List all available contexts
wt context add                   # Add a new repository context (interactive)
wt context add <path>            # Add context for repository at path
wt context add <name> <path>     # Add context with specific name and path
wt context remove [name]         # Remove a context and clean up all wt config
```

### Managing Project Metadata

```bash
# Export metadata from main repo to vault (run after setting up new IDE projects)
wt metadata-export

# Import metadata into a worktree (interactive selection if target omitted)
wt metadata-import
wt metadata-import ~/Development/java-worktrees/feature/foo

# Skip confirmation prompts (useful in scripts)
wt metadata-export -y
wt metadata-import -y ~/Development/java-worktrees/feature/foo
```

### Refreshing Stale Bazel IDE Metadata (Cron Job)

When most development work is done in worktrees, the Bazel IDE directories (`.ijwb`, `.aswb`, `.clwb`) in the main repository can become stale (targets files don't reflect new Bazel targets).

The `bin/wt-metadata-refresh` script is designed to run as a cron job to keep metadata current.

**Note:** When IntelliJ has `derive_targets_from_directories: true` in `.bazelproject` (the default), it queries Bazel fresh on every sync. The `targets-*` file serves as a cache for initial project imports and may improve import speed.

**Note:** The installer (`install.sh`) offers to set up this cron job automatically (default: yes).

To set it up manually:

```bash
# Create log directory
mkdir -p ~/.wt/logs

# Edit crontab
crontab -e

# Add this line to run nightly at 2am (uses login shell for full PATH):
0 2 * * * /bin/zsh -lc '~/.wt/bin/wt-metadata-refresh' >> ~/.wt/logs/metadata-refresh.log 2>&1
```

You can also run the script manually:

```bash
# Refresh all Bazel IDE directories and re-export to vault
~/.wt/bin/wt-metadata-refresh

# Preview what would be refreshed (dry run)
~/.wt/bin/wt-metadata-refresh --dry-run

# Refresh targets files only (skip re-export step)
~/.wt/bin/wt-metadata-refresh --no-export
```

The refresh script:
- Uses `bazel query` to regenerate `targets/targets-*` files in each Bazel IDE directory
- Supports all Bazel patterns configured in WT_METADATA_PATTERNS (`.ijwb`, `.aswb`, `.clwb`)
- Parses `.bazelproject` to determine which directories to include in the query
- Preserves existing targets file hashes (IntelliJ may reference them)
- Re-exports all metadata to the vault (including non-Bazel patterns)
- Logs timestamped output for monitoring
- Returns exit codes: 0=success, 1=error, 2=partial success


## Configuration: Environment Variables
The scripts rely on a few environment variables to know where your
main repository, worktrees, and IntelliJ metadata live.

These variables are normally read from the per-context config file
(`~/.wt/repos/<name>.conf`, written by `wt context add`). If set in your
shell configuration, they take precedence over the context config (except in
`wt.enabled` repos, where git local config has highest priority).

`wt` commands require a config source to actually load: if neither a context
`.conf` nor a repo's `wt.*` git local config is found, or if
`WT_MAIN_REPO_ROOT` does not point at an existing git repository, commands
exit with an error directing you to `wt context add`. The built-in defaults
below exist only so sourcing `wt.sh` never breaks an unconfigured shell.

| Variable | Default | Purpose |
|----------|---------|---------|
| `WT_MAIN_REPO_ROOT` | `~/.wt/repos/repo/base` | Main repository root |
| `WT_WORKTREES_BASE` | `~/.wt/repos/repo/worktrees` | Where worktrees are created |
| `WT_IDEA_FILES_BASE` | `~/.wt/repos/repo/idea-files` | IntelliJ metadata vault |
| `WT_ACTIVE_WORKTREE` | `~/Development/java` | Symlink to active worktree |
| `WT_BASE_BRANCH` | `master` | Default branch for new worktrees |
| `WT_SEED_FILES` | (empty) | Root files copied from main repo into new worktrees |
| `WT_METADATA_PATTERNS` | (empty) | Space-separated metadata patterns to preserve |

### WT_MAIN_REPO_ROOT
Path to your primary git repository clone.

**Default:** `~/.wt/repos/repo/base`

```bash
export WT_MAIN_REPO_ROOT="$HOME/Development/java-master"
```

Used by:
- wt-add (base branch operations)
- wt-choose (listing worktrees)
- wt-switch (default symlink target)
- wt-remove (safety check to prevent removing main repo)


### WT_WORKTREES_BASE
Directory where new worktrees are created by default.

**Default:** `~/.wt/repos/repo/worktrees`

```bash
export WT_WORKTREES_BASE="$HOME/Development/java-worktrees"
```


### WT_IDEA_FILES_BASE
Canonical metadata vault storing project metadata (IDE configs, etc.).

**Default:** `~/.wt/repos/repo/idea-files`

```bash
export WT_IDEA_FILES_BASE="$HOME/Development/idea-project-files"
```

Used by:
- wt-metadata-import
- wt-metadata-export
- wt-metadata-refresh
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

### WT_SEED_FILES
Space-separated, repo-root-relative names of files to copy (`cp -p`) from the main repo into every new/adopted worktree. Useful for gitignored per-machine files like `user.bazelrc` or `.bazelversion` overrides that a fresh checkout would otherwise lack.

Seeding is best-effort: files missing in the main repo are skipped, files already present in the worktree are never overwritten, and copy failures only warn.

**Default:** (empty)

```bash
export WT_SEED_FILES="user.bazelrc .bazelversion"
```

Used by:
- wt-add (via adoption treatment)
- wt-adopt

### WT_METADATA_PATTERNS
Space-separated list of project metadata patterns to preserve across worktrees.

**Default:** empty (context setup typically sets `.ijwb`)

```bash
export WT_METADATA_PATTERNS=".ijwb .idea .vscode"
```

Used by:
- wt-metadata-import / wt-metadata-export
- wt-metadata-refresh
- wt-add and wt-adopt (when installing metadata)

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
│   ├── wt-adopt
│   ├── wt-cd
│   ├── wt-context
│   ├── wt-list
│   ├── wt-remove
│   ├── wt-switch
│   ├── wt-metadata-import
│   ├── wt-metadata-export
│   └── wt-metadata-refresh  # Cron script to refresh Bazel IDE metadata
├── lib/                     # Shared libraries
│   ├── wt-common            # Configuration and helpers
│   ├── wt-adopt             # Worktree adoption helpers
│   ├── wt-choose            # Interactive worktree selection
│   ├── wt-context           # Multi-repo context management
│   ├── wt-context-setup     # Context creation (wt context add)
│   └── wt-help              # Help text for wt command
├── completion/              # Shell completions for wt-* scripts
│   ├── wt.zsh
│   └── wt.bash
├── install.sh
└── README.md
```

## Individual Scripts

You can also run the underlying scripts directly:

```bash
wt-add, wt-adopt, wt-switch, wt-remove, wt-list, wt-cd, wt-context, wt-metadata-export, wt-metadata-import
```

These are located in `bin/` and work identically to the `wt` subcommands.

The `bin/` directory is the subcommand registry: `wt <name>` dispatches to any executable `bin/wt-<name>`, and shell completion derives the top-level command list from the same directory. Only `cd`, `remove`, and `context` have dedicated dispatch branches (they need in-shell behavior), so adding a new subcommand is just dropping an executable `bin/wt-<name>` script.

The `bin/wt-metadata-refresh` script is designed for cron jobs; run it directly or as `wt metadata-refresh`.

## Project Resources

| Resource                       | Description                |
| ------------------------------ | -------------------------- |
| [CODEOWNERS](./CODEOWNERS)     | Project lead(s)            |
| [GOVERNANCE.md](./GOVERNANCE.md) | Project governance       |
| [LICENSE](./LICENSE)           | Apache License, Version 2.0 |
