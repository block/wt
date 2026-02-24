---
date: 2026-02-23T20:00:45Z
researcher: guodong
git_commit: 68a154edf54c2ac31ff5f375711d1075582890b6
branch: guodong/add_fix_script_for_when_intellij_messes_up_workspace_directories
repository: block/wt
topic: "Full Codebase Research — Worktree Toolkit (wt)"
tags: [research, codebase, worktree, git, bash, shell, bazel, intellij, multi-repo]
status: complete
last_updated: 2026-02-23
last_updated_by: guodong
last_updated_note: "Full re-research at commit 68a154e (9 files changed since previous research at 5949654)"
---

# Research: Full Codebase — Worktree Toolkit (wt)

**Date**: 2026-02-23T20:00:45Z
**Researcher**: guodong
**Git Commit**: `68a154e`
**Branch**: guodong/add_fix_script_for_when_intellij_messes_up_workspace_directories
**Repository**: [block/wt](https://github.com/block/wt)

## Research Question

Comprehensive documentation of the entire `wt` codebase: architecture, every file, data flow, configuration, testing, and CI.

## Summary

The Worktree Toolkit (`wt`) is a pure Bash/Zsh shell toolkit (~5,218 lines of source code across 18 source files, plus ~3,075 lines of tests across 13 test files — 8,293 lines total) for managing Git worktrees in Bazel + IntelliJ monorepos. It provides a unified `wt` command with subcommands for creating, switching, listing, navigating, and removing worktrees, plus managing IDE project metadata across worktrees. It supports multiple repository contexts and includes shell completions for both bash and zsh (with optional fzf integration). The project uses BATS for testing (4 unit, 8 integration, 1 e2e test files) and GitHub Actions for CI (tests + ShellCheck linting).

### Changes Since Previous Research (commit `5949654` → `68a154e`)

9 files changed across 6 commits:
- **`wt.sh`**: Simplified from 175 to 134 lines. `_WT_ROOT` changed from a dynamic symlink-resolving function to a simple constant defaulting to `$HOME/.wt`. Removed `_wt_resolve_root()` function entirely. Cross-reference comments between `_WT_ROOT` and `INSTALL_DIR` added then removed.
- **`install.sh`**: Removed 1 line (cross-reference comment cleanup).
- **`lib/wt-common`**: 472→471 lines. `prompt_confirm` now uses `read -erp` (readline editing enabled).
- **`lib/wt-choose`**: `read` calls now use `-e` flag for readline editing.
- **`lib/wt-context`**: `read` calls now use `-e` flag for readline editing.
- **`lib/wt-context-setup`**: 847→846 lines. All 10 interactive `read` calls updated from `read -rp` to `read -erp` for readline editing support.
- **`.github/workflows/lint.yml`** and **`test.yml`**: `actions/checkout` updated from v4 to v6 (pinned to digest `de0fac2e4500dabe0009e67214ff5f5447ce83dd`).
- **`test/unit/wt-sh.bats`**: New file (35 lines) — unit test verifying `_WT_ROOT` default in `wt.sh` matches `INSTALL_DIR` in `install.sh`.

---

## Detailed Findings

### 1. Entry Point — `wt.sh`

**File**: [`wt.sh`](https://github.com/block/wt/blob/68a154e/wt.sh) (134 lines)

This is the sole entry point. It **must be sourced** (not executed) because `wt cd` needs to change the current shell's directory. On load, it:

1. **Sets `_WT_ROOT`** (line 16): `_WT_ROOT="${_WT_ROOT:-$HOME/.wt}"` — a simple constant defaulting to `~/.wt`, overridable via environment variable.
2. **Validates sourcing** via `_wt_ensure_sourced()` (lines 19–42) — checks `ZSH_EVAL_CONTEXT` in zsh or `BASH_SOURCE[0] == $0` in bash.
3. **Provides helper functions**:
   - `_wt_source_lib()` (lines 46–56) — sources a library from `$_WT_ROOT/lib/`, supports `"optional"` mode.
   - `_wt_run()` (lines 59–71) — runs a `wt-*` command from `$_WT_ROOT/bin/` or PATH, returns exit code 127 if not found.
   - `__wt_do_cd()` (lines 75–85) — captures path from `wt-cd` stdout and runs `cd` in current shell.
4. **Defines the `wt()` function** (lines 88–113) — a `case` dispatcher mapping subcommands to `_wt_run wt-*` calls. Subcommands: `add`, `switch`, `remove`, `list`, `context`, `metadata-export`, `metadata-import`, `cd`, `help`. Legacy aliases `ijwb-export`/`ijwb-import` preserved.
5. **Sources shell completions** via `_wt_source_shell_completion()` (lines 116–124) — detects zsh vs bash and sources the appropriate completion file.
6. **Initialization block** (lines 130–133): calls `_wt_ensure_sourced`, sources `wt-common`, `wt-help`, and shell completions.

### 2. Shared Library — `lib/wt-common`

**File**: [`lib/wt-common`](https://github.com/block/wt/blob/68a154e/lib/wt-common) (471 lines)

The central configuration and utility library, sourced by every script and both completion files.

#### Configuration System (lines 25–110)
- **`wt_clear_config_vars()`** (lines 28–36) — unsets all 7 `WT_*` variables for fresh reload.
- **`wt_read_config()`** (lines 45–84) — reads `~/.wt/current` to get context name, then parses `~/.wt/repos/<name>.conf` using `grep`/`while read` (no `source`ing for safety). Two-level indirection: `current` → context name → `.conf` file. Only sets variables not already in the environment, enabling env-var overrides. Uses `eval` with `${VAR:-}` to check existing values.
- **Auto-load on source** (line 87): `wt_read_config "$HOME/.wt/current"` runs immediately.
- **Fallback defaults** (lines 92–110): `WT_MAIN_REPO_ROOT`, `WT_WORKTREES_BASE`, `WT_IDEA_FILES_BASE`, `WT_ACTIVE_WORKTREE`, `WT_BASE_BRANCH`, `WT_METADATA_PATTERNS`, `WT_CONTEXT_NAME` — all use `: "${VAR:=default}"` syntax.

#### Path Helper (lines 118–122)
- `_wt_expand_path()` — expands `~` to `$HOME` via bash parameter substitution.

#### Color and Output Helpers (lines 130–196)
- Conditional ANSI color codes (`RED`, `GREEN`, `YELLOW`, `BLUE`, `BOLD`, `NC`) — only set if stdout/stderr is a TTY (lines 130–144).
- `echoerr()` (lines 151–153) — stderr via `printf`.
- `error()` (lines 156–158) — red `"Error: ..."` to stderr.
- `success()` (lines 161–163) — green `"✓ ..."` to stdout.
- `warn()` (lines 166–168) — yellow `"⚠  ..."` to stderr.
- `info()` (lines 171–173) — blue `"ℹ  ..."` to stdout.
- `wt_show_context_banner()` (lines 177–196) — prints `[Context: <name>]` to stderr when multi-repo contexts are configured.

#### Library Sourcing (lines 201–218)
- `wt_source()` — sources from `$LIB_DIR` or `~/.wt/lib/`. Distinct from `_wt_source_lib` in `wt.sh`.

#### Git Helpers (lines 232–432)
- **`wt_resolve_worktree()`** (lines 232–258) — resolves a worktree identifier (path or branch name) to an absolute path. Tries filesystem path first, then parses `git worktree list --porcelain` for branch name match.
- **`wt_resolve_and_validate()`** (lines 265–277) — combines resolution + `git rev-parse --is-inside-work-tree` validation.
- **`wt_worktree_branch_list()`** (lines 283–306) — lists branch names of active worktrees (parses porcelain output); supports `exclude_main` filter.
- **`wt_get_linked_worktree()`** (lines 315–334) — resolves the symlink at `WT_ACTIVE_WORKTREE` to a physical path. Handles macOS `/var` → `/private/var` quirk with `pwd -P`. Resolves both relative and absolute symlink targets.
- **`wt_format_worktree()`** (lines 340–390) — formats a worktree entry for display: bold path, blue `(branch)`, then indicators: yellow `[main]`, green `[linked]`, and (verbose only) red `[dirty]`, green `[↑N]`, yellow `[↓N]`.
- **`wt_has_uncommitted_changes()`** (lines 395–411) — checks `git status --porcelain`.
- **`wt_uncommitted_summary()`** (lines 416–432) — counts staged/modified/untracked files.

#### Prompt Helper (lines 447–471)
- `prompt_confirm()` — yes/no prompt with configurable default. Uses `read -erp` (readline editing enabled). Handles Ctrl-C/EOF.

### 3. Subcommand Scripts (`bin/`)

All 8 bin scripts follow the same bootstrap pattern (11-line block): resolve `SCRIPT_DIR` and `LIB_DIR` relative to the script, source `wt-common` (try `LIB_DIR` first, fall back to `~/.wt/lib/`), source additional libraries via `wt_source`, show context banner.

#### 3.1 `bin/wt-add` (481 lines)

**File**: [`bin/wt-add`](https://github.com/block/wt/blob/68a154e/bin/wt-add)

Creates git worktrees. Two modes:

**Fast path (no `-b` flag)** (lines 220–294):
- **Convenience mode** (`wt-add <branch>`): derives path as `$WT_WORKTREES_BASE/<branch>`, runs `git worktree add`, installs metadata + Bazel symlinks.
- **Passthrough mode** (`wt-add <path> <branch> [args]`): passes all args to `git worktree add`.
- Validates branch names don't contain `..` (path traversal prevention).

**New branch path (`-b` flag)** (lines 296–481):
1. Records original branch/SHA and sets up `trap restore_state EXIT INT TERM` (lines 307–357).
2. Stashes uncommitted changes with a unique name (`wta-<timestamp>-<pid>`) (lines 360–367).
3. Switches to `WT_BASE_BRANCH`, runs `git pull --ff-only` (with optional `timeout`/`gtimeout`, skippable with `WT_SKIP_PULL=1`) (lines 370–403).
4. Derives path if not explicitly provided (lines 409–451).
5. If branch already exists, prompts to create worktree for existing branch instead (lines 460–475).
6. Creates worktree, installs metadata + Bazel symlinks (lines 477–480).
7. `restore_state()` cleanup: switches back to original branch, pops specific stash (lines 316–352).

**Helper functions**:
- `install_metadata_for_worktree()` (lines 143–164) — locates and calls `wt-metadata-import -y`.
- `install_bazel_symlinks_for_worktree()` (lines 174–215) — copies Bazel output symlinks (`bazel-out`, `bazel-bin`, `bazel-testlogs`, `bazel-genfiles`) from main repo to worktree for shared build cache.

#### 3.2 `bin/wt-switch` (124 lines)

**File**: [`bin/wt-switch`](https://github.com/block/wt/blob/68a154e/bin/wt-switch)

Updates the `WT_ACTIVE_WORKTREE` symlink to point to a selected worktree.
- Interactive mode: uses `select_git_worktree()` from `wt-choose`.
- Direct mode: resolves and validates the argument via `wt_resolve_and_validate()`.
- Safety: only removes symlinks (errors on real files/dirs at the symlink path). Normalizes link path via `pwd -P` on parent directory. Creates parent dir with `mkdir -p`.

#### 3.3 `bin/wt-remove` (309 lines)

**File**: [`bin/wt-remove`](https://github.com/block/wt/blob/68a154e/bin/wt-remove)

Removes worktrees with safety checks. Three modes:
- **Interactive**: presents worktree menu (excludes main repo).
- **Direct**: `wt-remove <worktree>` with confirmation.
- **`--merged` mode** (lines 111–208): finds all worktrees whose branches are merged into `WT_BASE_BRANCH`, shows them, and batch-removes with confirmation. Also deletes the local branch. Skips dirty worktrees with `-y` instead of removing them.

Safety features:
- Prevents removing the main repository.
- Warns if removing the currently linked worktree (auto-switches symlink to main repo).
- Shows uncommitted changes summary and requires explicit confirmation even with `-y`.
- Uses `git worktree remove --force`.

#### 3.4 `bin/wt-list` (125 lines)

**File**: [`bin/wt-list`](https://github.com/block/wt/blob/68a154e/bin/wt-list)

Lists all worktrees with status indicators. Parses `git worktree list --porcelain` and uses `wt_format_worktree()` for display.
- Fast mode (default): shows path, branch, `[main]`, `[linked]`.
- Verbose mode (`-v`): additionally shows `[dirty]`, `[↑N]`, `[↓N]`.
- Green `*` prefix for the currently linked worktree.

#### 3.5 `bin/wt-cd` (107 lines)

**File**: [`bin/wt-cd`](https://github.com/block/wt/blob/68a154e/bin/wt-cd)

Outputs a worktree path to stdout for shell navigation. All UI goes to stderr.
- Interactive mode: uses `select_git_worktree()`.
- Direct mode: validates and outputs the path.
- Shows a hint if stdout is a TTY (direct invocation detected).

#### 3.6 `bin/wt-context` (210 lines)

**File**: [`bin/wt-context`](https://github.com/block/wt/blob/68a154e/bin/wt-context)

Manages multi-repository contexts. Subcommands:
- **(no args)**: interactive context selection menu via `select_context()`.
- **`<name>`**: switches to named context via `wt_set_current_context()`.
- **`--list`**: displays all contexts with `*` prefix for current, path, and formatted table.
- **`add [name] [path]`**: runs `wt_setup_context()` from `wt-context-setup` library.

#### 3.7 `bin/wt-metadata-export` (255 lines)

**File**: [`bin/wt-metadata-export`](https://github.com/block/wt/blob/68a154e/bin/wt-metadata-export)

Exports project metadata directories from a source repo to a vault using symlinks.
- `find_all_metadata_dirs()` (lines 159–196): Scans source for patterns in `WT_METADATA_PATTERNS` (up to 5 levels deep), deduplicates nested paths (if `.ijwb` contains `.idea`, only `.ijwb` is exported).
- Creates symlinks in vault preserving the relative directory structure.
- Cleans up old symlinks before re-exporting.

#### 3.8 `bin/wt-metadata-import` (255 lines)

**File**: [`bin/wt-metadata-import`](https://github.com/block/wt/blob/68a154e/bin/wt-metadata-import)

Imports project metadata from a vault into a target worktree by **copying** (not symlinking).
- Three invocation modes: interactive, single-arg (target only), or two-arg (source + target).
- `copy_real_metadata()` (lines 167–194) — resolves symlinks in the vault and copies the real directory contents using `cp -a`.
- `import_pattern()` (lines 198–247) — handles per-pattern import, cleans up broken symlinks in vault when encountered.

### 4. Libraries (`lib/`)

#### 4.1 `lib/wt-choose` (155 lines)

**File**: [`lib/wt-choose`](https://github.com/block/wt/blob/68a154e/lib/wt-choose)

Provides `select_git_worktree()` (lines 64–155) — an interactive numbered menu for choosing a worktree. Runs in a subshell to avoid changing the caller's working directory. All UI output goes to stderr; only the selected path goes to stdout. Uses `read -erp` for readline-enabled input. Supports `exclude_main` parameter. Green `*` prefix for currently linked worktree.

Sourced by: `bin/wt-switch`, `bin/wt-remove`, `bin/wt-cd`, `bin/wt-metadata-import`.

#### 4.2 `lib/wt-context` (218 lines)

**File**: [`lib/wt-context`](https://github.com/block/wt/blob/68a154e/lib/wt-context)

Context management library. Functions:
- `wt_get_repos_dir()` (lines 29–31) → `~/.wt/repos`
- `wt_get_current_file()` (lines 35–37) → `~/.wt/current`
- `wt_list_contexts()` (lines 45–59) — iterates `~/.wt/repos/*.conf`
- `wt_get_current_context()` (lines 63–70) — reads first line of `~/.wt/current`, strips whitespace
- `wt_context_exists()` (lines 75–81) — checks if `.conf` file exists
- `wt_get_context_config_path()` (lines 86–91) — returns path to `.conf` file
- `wt_get_context_repo_root()` (lines 96–104) — greps `WT_MAIN_REPO_ROOT` from config
- `wt_set_current_context()` (lines 113–128) — writes context name to `~/.wt/current`
- `wt_load_context_config()` (lines 133–136) — deprecated wrapper for `wt_read_config()`
- `select_context()` (lines 145–218) — interactive context selection menu with `read -erp`

Sourced by: `bin/wt-context`.

#### 4.3 `lib/wt-context-setup` (846 lines)

**File**: [`lib/wt-context-setup`](https://github.com/block/wt/blob/68a154e/lib/wt-context-setup)

The largest library. Provides the full context setup flow used by both `install.sh` and `wt context add`.

**Known metadata patterns** (lines 23–46): defines `WT_KNOWN_METADATA` array with 15 patterns and descriptions for JetBrains IDEs, Bazel, Xcode/iOS, VS Code, Scala, and Eclipse.

**Helper functions**:
- `_wt_detect_default_branch()` (lines 53–75) — tries `origin/HEAD`, then checks for `main`/`master`; ultimate fallback is `"main"`.
- `_wt_derive_paths()` (lines 80–105) — derives all `WT_*` paths from repo path, context name, and optional symlink path.
- `_wt_detect_metadata_patterns()` (lines 108–153) — finds known metadata patterns in repo (with deduplication).
- `_wt_get_pattern_description()` (lines 156–165) — looks up pattern description in `WT_KNOWN_METADATA`.
- `_wt_select_metadata_patterns()` (lines 170–285) — interactive toggle-based selection UI with `read -erp`.
- `_wt_create_directories()` (lines 292–305) — creates worktrees, idea-files, and symlink parent dirs.
- `_wt_update_context_main_repo()` (lines 309–319) — updates config file via `sed -i.bak`.
- `_wt_migrate_repo()` (lines 323–404) — handles the "symlink trick" migration (three cases: real directory → move+symlink, existing symlink → optionally update, nothing → create symlink).
- `_wt_sync_metadata()` (lines 408–480) — calls `wt-metadata-export` to populate the vault.

**`wt_setup_context()`** (lines 490–846) — the main 9-step flow:
1. Get repository path (interactive prompt or argument)
2. Get context name (with validation: `[a-zA-Z0-9_-]+`)
3. Detect git info (remote URL, default branch)
4. Derive and display configuration (with option to customize each value)
5. Detect and select metadata patterns
6. Create config file at `~/.wt/repos/<name>.conf`
7. Create directories
8. Migrate repository (move + symlink)
9. Sync metadata to vault

All interactive prompts use `read -erp` for readline editing.

Sourced by: `bin/wt-context`, `install.sh`.

#### 4.4 `lib/wt-help` (100 lines)

**File**: [`lib/wt-help`](https://github.com/block/wt/blob/68a154e/lib/wt-help)

Provides `wt_show_help()` (lines 11–100) — displays comprehensive help text with current configuration values. Force-reloads config on each invocation via `wt_read_config "$HOME/.wt/current" "force"` to pick up context changes.

Sourced by: `wt.sh`.

#### 4.5 `lib/wt-metadata-refresh` (478 lines)

**File**: [`lib/wt-metadata-refresh`](https://github.com/block/wt/blob/68a154e/lib/wt-metadata-refresh)

Executable script (not a sourced library) for refreshing Bazel IDE metadata (`.ijwb`, `.aswb`, `.clwb`). Designed for cron jobs.

Key functions:
- `parse_bazelproject_directories()` (lines 179–193) — parses `.bazelproject` files using `awk` to extract `directories:` section.
- `build_query_expression()` (lines 198–215) — constructs Bazel query like `"//dir1/... + //dir2/..."`.
- `refresh_targets_file()` (lines 220–309) — runs `bazel query "kind('.*', ...)" --output=label` and writes sorted output to `targets/targets-*` file. Preserves existing target file names (hashes) for IntelliJ compatibility.
- `refresh_all_bazel_metadata()` (lines 312–352) — orchestrates all Bazel IDE directory refreshes.
- `do_export()` (lines 355–382) — re-exports all metadata to vault via `wt-metadata-export`.
- `main()` (lines 395–476) — entry point. Supports `--dry-run` and `--no-export` flags. Structured exit codes: 0=success, 1=error, 2=partial success. Timestamped log output via `log()`.

### 5. Shell Completions (`completion/`)

#### 5.1 `completion/wt.bash` (373 lines)

**File**: [`completion/wt.bash`](https://github.com/block/wt/blob/68a154e/completion/wt.bash)

Bash completion supporting both `wt` and standalone `wt-*` commands.

- **Bootstrap** (lines 30–32): sources `~/.wt/lib/wt-common`.
- **`_wt_resolve_repo()`** (lines 39–53): three-level priority for repo resolution (configured → cwd → empty).
- **`_wt_branch_list()`** (lines 56–63): `git branch --format='%(refname:short)'`.
- **With fzf** (lines 69–126): `_wt_add_complete` launches fzf for branch picking with `--height 50% --reverse`.
- **Without fzf** (lines 131–175): `_wt_add_complete` uses standard `compgen -W`.
- Per-command completions: `_wt_switch_complete` (lines 177–188), `_wt_remove_complete` (lines 190–201), `_wt_cd_complete` (lines 203–214).
- Context completion: `_wt_context_list()` (lines 217–228), `_wt_context_complete()` (lines 231–257).
- Metadata completions: `_wt_metadata_export_complete` (lines 260–267), `_wt_metadata_import_complete` (lines 270–298).
- Unified `_wt_completion_bash` (lines 313–372) dispatches to per-subcommand completions; force-reloads config (line 315).
- Registration: `complete -F _wt_completion_bash wt` (line 373), plus conditional `complete -F` for each standalone `wt-*` command (lines 301–307).

#### 5.2 `completion/wt.zsh` (355 lines)

**File**: [`completion/wt.zsh`](https://github.com/block/wt/blob/68a154e/completion/wt.zsh)

Zsh completion using `_arguments`, `_describe`, and `compdef` patterns.

- **Bootstrap** (lines 25–27): sources `~/.wt/lib/wt-common`.
- Per-command functions: `_wt_switch` (lines 67–84), `_wt_remove` (lines 87–104), `_wt_cd` (lines 107–124), `_wt_context` (lines 127–163), `_wt_metadata_export` (lines 166–170), `_wt_metadata_import` (lines 173–193).
- **With fzf** (lines 199–261): custom ZLE widget `wt_fzf_branch_complete` (lines 201–223) bound to TAB via `wt_tab_dispatch` dispatcher (lines 236–253). Original TAB binding preserved. Ctrl+X Ctrl+A always triggers fzf branch picker.
- **Without fzf** (lines 264–290): standard `_wt_add` using `_arguments -C` with `_describe` for branches.
- Unified `_wt_completion` (lines 308–354) dispatches to per-subcommand functions; force-reloads config (line 310).
- Registration: `compdef _wt_completion wt` (line 355), plus unconditional `compdef` for each standalone `wt-*` command (lines 297–302).

### 6. Installer — `install.sh`

**File**: [`install.sh`](https://github.com/block/wt/blob/68a154e/install.sh) (222 lines)

Interactive installation flow:
1. **Old installation cleanup** (lines 151–171): migrates `~/.config/wt` to `~/.wt` if present, updates shell rc files.
2. **`install_toolkit()`** (lines 46–65): copies `wt.sh`, `bin/`, `lib/`, `completion/` to `~/.wt/`, makes scripts executable.
3. **`configure_shell_rc()`** (lines 68–80): appends `source ~/.wt/wt.sh` to `~/.zshrc`/`~/.bashrc` (idempotent via `append_if_missing`).
4. **Repository context setup** (lines 179–202): optionally runs `wt_setup_context` for initial configuration (skippable).
5. **`setup_cron_job()`** (lines 84–136): optionally installs nightly cron job at 2am for `wt-metadata-refresh`.

Constants: `SOURCE_DIR` (resolved from script location), `INSTALL_DIR="$HOME/.wt"` (hardcoded, matches `_WT_ROOT` default in `wt.sh`).

### 7. Test Suite

**Framework**: [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System) with `bats-support` and `bats-assert` helpers, included as git submodules in `test/`.

#### 7.1 Test Helper — `test/test_helper/common.bash` (251 lines)

Shared setup/teardown functions:
- `_compute_project_root()` (lines 10–17) — walks up from `$BATS_TEST_DIRNAME` to find directory containing `wt.sh`.
- `setup_test_env()` (lines 27–48) — creates isolated `$TEST_HOME` with `.wt/` structure, copies lib/bin, updates PATH.
- `teardown_test_env()` (lines 51–55) — restores original PATH.
- `create_mock_repo()` / `create_mock_repo_with_remote()` (lines 60–106) — creates test git repos with `pwd -P` normalization.
- `create_branch()`, `create_worktree()`, `create_test_context()`, `load_test_context()` (lines 110–182).
- `make_repo_dirty()`, `stage_changes()`, `create_metadata_dirs()` (lines 186–213).
- `assert_symlink_target()`, `assert_is_worktree()` (lines 217–237) — custom assertions.
- `skip_if_not_bash()`, `skip_if_no_git()` (lines 240–251) — conditional test skipping.

#### 7.2 Unit Tests (4 files, 850 lines)

| File | Lines | Tests | What It Tests |
|------|-------|-------|---------------|
| `test/unit/wt-common.bats` | 257 | 20 | Output helpers, `wt_source`, uncommitted changes detection, linked worktree resolution, worktree formatting, `prompt_confirm` |
| `test/unit/wt-context-setup.bats` | 227 | 18 | `WT_KNOWN_METADATA` array, `_wt_expand_path`, `_wt_detect_default_branch`, `_wt_derive_paths`, `_wt_detect_metadata_patterns`, `_wt_get_pattern_description`, `_wt_create_directories` |
| `test/unit/wt-context.bats` | 331 | 22 | All `wt_*` context functions, context workflow integration, multi-context coexistence, config file format |
| `test/unit/wt-sh.bats` | 35 | 1 | Consistency: `_WT_ROOT` default in `wt.sh` matches `INSTALL_DIR` in `install.sh` |

#### 7.3 Integration Tests (8 files, 1,681 lines)

| File | Lines | Tests | What It Tests |
|------|-------|-------|---------------|
| `test/integration/wt-add.bats` | 231 | 15 | Worktree creation (existing/new branch, path traversal security, state restoration, flag passthrough, slash branches) |
| `test/integration/wt-cd.bats` | 168 | 10 | Directory navigation (clean path output, error handling, symlinks, spaces in paths) |
| `test/integration/wt-context.bats` | 218 | 13 | Context listing, switching, adding, special characters, config preservation |
| `test/integration/wt-list.bats` | 176 | 10 | Listing with indicators, verbose mode, error handling, special characters |
| `test/integration/wt-metadata-export.bats` | 212 | 10 | Symlink creation, multiple patterns, deduplication, directory structure, updates |
| `test/integration/wt-metadata-import.bats` | 260 | 13 | Content copying, nested structure, symlink resolution, broken symlinks, permissions |
| `test/integration/wt-remove.bats` | 227 | 12 | Removal with safety checks, main repo protection, linked worktree handling, `--merged` mode |
| `test/integration/wt-switch.bats` | 189 | 12 | Symlink creation/update, non-symlink protection, error handling, trailing slashes |

#### 7.4 End-to-End Tests (1 file, 293 lines)

| File | Lines | Tests | What It Tests |
|------|-------|-------|---------------|
| `test/e2e/workflow.bats` | 293 | 8 | Complete worktree lifecycle, multi-worktree management, new branch creation, context switching, uncommitted changes handling, navigation, symlink consistency, failure recovery |

### 8. CI Pipeline (GitHub Actions)

#### 8.1 Tests — `.github/workflows/test.yml`
- Triggers: push to main, all PRs, daily at 8am UTC.
- Runs: `./test/bats/bin/bats test/unit/ test/integration/ test/e2e/`
- Uses `actions/checkout@v6` (pinned to digest), `submodules: true`.

#### 8.2 Lint — `.github/workflows/lint.yml`
- Triggers: push to main, all PRs, daily at 8am UTC.
- Installs ShellCheck v0.11.0.
- Runs: `shellcheck -x -s bash wt.sh install.sh bin/wt-* lib/wt-* completion/wt.bash`
- Uses `actions/checkout@v6` (pinned to digest).

### 9. Project Configuration Files

| File | Purpose |
|------|---------|
| `.gitignore` | Ignores backups, logs, temp, env/secrets, OS files, IDE files, shell history, and AI agent files (`.claude/`, `CLAUDE.md`, `[Aa]gent*.md`) |
| `.gitmodules` | Three BATS submodules: `test/bats`, `test/test_helper/bats-support`, `test/test_helper/bats-assert` |
| `.shellcheckrc` | `external-sources=true`, disables SC1090 (non-constant source) and SC1091 (file not found) |
| `CODEOWNERS` | All files owned by `@HamptonMakes` and `@guodong-sq` |
| `renovate.json` | Extends `config:recommended` and `helpers:pinGitHubActionDigests` |
| `LICENSE` | Apache License 2.0, copyright 2026 Block, Inc. |
| `CONTRIBUTING.md` | Prerequisites (Bash 4.0+, Git), dev setup, testing instructions, PR flow |
| `GOVERNANCE.md` | Links to Block organization shared governance |
| `README.md` | User-facing documentation: commands, config variables, directory structure, install |
| `presentation/slides.md` | Marp slide deck: motivation, architecture, demo, before/after results |

### 10. Configuration & Data Layout

```
~/.wt/
├── wt.sh                    # Entry point (sourced)
├── bin/                     # Executable subcommands
│   └── wt-{add,cd,context,list,metadata-export,metadata-import,remove,switch}
├── lib/                     # Shared libraries
│   └── wt-{choose,common,context,context-setup,help,metadata-refresh}
├── completion/              # Shell completions
│   └── wt.{bash,zsh}
├── current                  # Contains name of active context (e.g., "java")
├── repos/
│   ├── <name>.conf          # Per-context config file (key=value)
│   └── <name>/
│       ├── base/            # Main worktree (moved here during migration)
│       ├── worktrees/       # Additional worktrees created by wt-add
│       └── idea-files/      # Metadata vault (symlinks to real metadata dirs)
└── logs/
    └── metadata-refresh.log # Cron job output
```

**Config file format** (`~/.wt/repos/<name>.conf`):
```bash
WT_MAIN_REPO_ROOT="/path/to/base"
WT_WORKTREES_BASE="/path/to/worktrees"
WT_ACTIVE_WORKTREE="/path/to/symlink"
WT_IDEA_FILES_BASE="/path/to/vault"
WT_BASE_BRANCH="main"
WT_METADATA_PATTERNS=".ijwb .idea .vscode"
```

### 11. Data Flow Diagrams

#### Worktree Creation (`wt add -b <branch>`)
```
Main Repo → stash changes → checkout base branch → git pull
  → git worktree add → metadata import from vault → Bazel symlink install
  → restore original branch → pop stash
```

#### Metadata Flow
```
Main Repo                    Vault                       Worktree
   .ijwb/  ─── export ──→  .ijwb (symlink)  ─── import ──→  .ijwb/ (copy)
   .idea/  ─── export ──→  .idea (symlink)  ─── import ──→  .idea/ (copy)
```
Export creates **symlinks** in the vault pointing to the source. Import **copies** the real contents from the vault into the worktree.

#### Symlink Trick (IDE Integration)
```
~/Development/java  ──symlink──→  ~/.wt/repos/java/base/           (or any worktree)
       ↑
   IntelliJ opens this path
   (never changes, just a symlink)
```

## Code References

| File | Lines | Purpose |
|------|-------|---------|
| `wt.sh` | 134 | Entry point, dispatcher, initialization |
| `lib/wt-common` | 471 | Config system, color/output helpers, git helpers, prompts |
| `lib/wt-choose` | 155 | Interactive worktree selection menu |
| `lib/wt-context` | 218 | Context listing, querying, switching |
| `lib/wt-context-setup` | 846 | Full context setup wizard |
| `lib/wt-help` | 100 | Help text display |
| `lib/wt-metadata-refresh` | 478 | Cron-based Bazel metadata refresh |
| `bin/wt-add` | 481 | Worktree creation |
| `bin/wt-switch` | 124 | Active worktree symlink update |
| `bin/wt-remove` | 309 | Worktree removal with safety checks |
| `bin/wt-list` | 125 | Worktree listing with status |
| `bin/wt-cd` | 107 | Directory navigation |
| `bin/wt-context` | 210 | Context management CLI |
| `bin/wt-metadata-export` | 255 | Metadata export to vault |
| `bin/wt-metadata-import` | 255 | Metadata import from vault |
| `completion/wt.bash` | 373 | Bash completion (fzf optional) |
| `completion/wt.zsh` | 355 | Zsh completion (fzf optional) |
| `install.sh` | 222 | Installer |
| `test/test_helper/common.bash` | 251 | Test infrastructure |
| `test/unit/*.bats` | 850 | 61 unit tests |
| `test/integration/*.bats` | 1,681 | 95 integration tests |
| `test/e2e/workflow.bats` | 293 | 8 end-to-end tests |

## Architecture Documentation

### Design Patterns

1. **Source vs Execute duality**: `wt.sh` must be sourced (for `cd`); all `bin/wt-*` scripts are standalone executables. The `wt()` shell function bridges these two worlds.

2. **Bootstrap pattern**: Every `bin/wt-*` script has an identical 11-line boilerplate block to find and source `wt-common` (try `$LIB_DIR` relative to script, fall back to `~/.wt/lib/`). This makes scripts work both from the development repo and the installed location.

3. **Config-as-parsing (not sourcing)**: `wt_read_config()` uses `grep` + `while read` instead of `source` to load config files. Safer against injection and allows config updates without shell reload.

4. **Two-level config indirection**: `~/.wt/current` contains a context name → `~/.wt/repos/<name>.conf` contains actual `WT_*` values. This enables multi-repo support.

5. **Environment override precedence**: Config values are set with `${VAR:=default}` syntax, so environment variables always win over config files, which win over built-in defaults.

6. **Stdout/stderr separation**: Interactive UI always goes to stderr; only machine-readable output (paths, selections) goes to stdout. This enables clean `$()` capture patterns.

7. **Physical path normalization**: All path comparisons use `pwd -P` to resolve symlinks, handling macOS quirks like `/var` → `/private/var`.

8. **Metadata as symlinks (vault) / copies (worktrees)**: The vault stores symlinks (lightweight, always point to source of truth). Worktrees get full copies (independent of vault, can diverge).

9. **Readline editing in all prompts**: All interactive `read` calls use `-erp` flags (readline editing + raw input + prompt string) for consistent user experience with line editing, history, and cursor movement.

### Cross-File Connection Map

```
wt.sh
  sources: lib/wt-common (line 131)
           lib/wt-help   (line 132)
  calls:   bin/wt-*      (via _wt_run)

bin/wt-add
  sources: lib/wt-common
  calls:   bin/wt-metadata-import (line 163)

bin/wt-switch
  sources: lib/wt-common, lib/wt-choose

bin/wt-remove
  sources: lib/wt-common, lib/wt-choose

bin/wt-list
  sources: lib/wt-common

bin/wt-cd
  sources: lib/wt-common, lib/wt-choose

bin/wt-context
  sources: lib/wt-common, lib/wt-context, lib/wt-context-setup

bin/wt-metadata-export
  sources: lib/wt-common

bin/wt-metadata-import
  sources: lib/wt-common, lib/wt-choose

lib/wt-metadata-refresh (executable)
  sources: lib/wt-common
  calls:   bin/wt-metadata-export

lib/wt-choose
  sources: lib/wt-common (own bootstrap)

install.sh
  sources: lib/wt-common (line 23), lib/wt-context-setup (line 189)
  copies:  wt.sh, bin/, lib/, completion/ → ~/.wt/

completion/wt.bash
  sources: ~/.wt/lib/wt-common (line 31)

completion/wt.zsh
  sources: ~/.wt/lib/wt-common (line 26)
```

### Shell Compatibility

- All scripts use `#!/usr/bin/env bash` with `set -euo pipefail`.
- `wt.sh` handles both bash and zsh sourcing idioms.
- Completions have separate bash and zsh implementations.
- Path resolution and script detection handle differences between shells.

## Related Research

No other research documents exist in `thoughts/shared/research/`.

## Open Questions

- The `README.md` references `presentation/slides.pdf` generated from `slides.md`, but the PDF is not tracked in git — it may need regeneration via `npx @marp-team/marp-cli`.
- The `completion/wt.bash` references `_wt_worktree_list` (lines 282, 291) which does not exist as a named function in `wt-common`. This may be an inconsistency or it may be defined elsewhere (possibly in a completion-specific helper not analyzed).
