# Worktree Manager - IntelliJ Plugin

Native git worktree management for all JetBrains IDEs, using atomic symlink switching for sub-second context switches. This is the IDE companion to the [wt CLI](http://go/wt).

## Requirements

- JetBrains IDE **2025.3+** (IntelliJ IDEA, Android Studio, CLion, WebStorm, etc.)
- Git on PATH
- macOS or Linux
- [wt CLI](http://go/wt) setup recommended

## Installation

```bash
./gradlew buildPlugin
```

Then **Settings > Plugins > gear icon > Install Plugin from Disk...** and select `build/distributions/wt-intellij-plugin-0.1.0.zip`.

To update, rebuild and reinstall. The old version is replaced automatically.

## Screenshot

![Tool Window](src/main/resources/ui.png)

## Features

| wt CLI command | Plugin equivalent |
|---|---|
| `wt list [-v]` | **Worktrees** tool window with async status indicators |
| `wt add [-b] <branch>` | **Create Worktree** dialog (stash/pull/create/restore) |
| `wt switch <worktree>` | **Switch Worktree** with atomic symlink swap |
| `wt remove [--merged]` | **Remove Worktree** / **Remove Merged** with safety checks |
| `wt context [name]` | **Context selector** in status bar + popup |
| `wt metadata-export` | **Export Metadata to Vault** |
| `wt metadata-import` | **Import Metadata from Vault** |
| `wt-metadata-refresh` | **Refresh Bazel Targets** |
| `wt cd` | **Open in Terminal** |

The plugin reads the same `~/.wt/` config files as the CLI. Both work side by side. A file watcher auto-refreshes the tool window on external changes.

---

## Usage

### Tool Window

**View > Tool Windows > Worktrees** shows all worktrees:

| Column | Description |
|---|---|
| `*` | Currently linked worktree |
| Path | Directory name |
| Branch | Checked-out branch |
| Status | `⚠`conflicts `●`staged `✱`modified `…`untracked `↑`ahead `↓`behind |
| Agent | Active Claude Code session IDs (truncated; hover for full) |
| Provisioned | `✓` current context, `~` other context |

Double-click a row to switch. Hover Status or Agent cells for details.

### Shortcuts

| Action | Shortcut |
|---|---|
| Switch Worktree | `Ctrl+Alt+W` |
| Create Worktree | `Ctrl+Alt+Shift+W` |

Also available under **VCS > Worktrees**.

### Status Bar

Shows current context (e.g. `wt: java`). Click to switch.

### Settings

**Settings > Tools > Worktree Manager**:

- Auto-refresh interval
- Status indicator loading
- Auto-export metadata on shutdown (default: off)
- Switch/remove confirmation dialogs
- Provision prompt on switch

---

## How It Works

### Symlink Swap

```
1. Create temp symlink:  .active.<uuid>.tmp -> /new/worktree
2. Atomic rename:        rename(.tmp, active)  -- single syscall, zero gap
3. VFS refresh:          save docs -> swap -> reload editors -> refresh VFS -> update git
```

### Metadata Vault

`~/.wt/repos/<context>/idea-files/` stores symlinks to worktree metadata:

- **Export**: vault symlinks point to current worktree's `.idea/`, `.ijwb/`, `.run/`, etc.
- **Import**: copies from vault (following symlinks) into target worktree

### Agent Detection

Two complementary methods:

- **Process** (`/usr/sbin/lsof`): finds running `claude` processes by cwd
- **Session files** (`~/.claude/projects/`): checks for recently-modified `.jsonl` transcripts (30 min window)

A worktree shows the agent indicator if either method detects activity.

---

## Development

JDK 25 toolchain is auto-provisioned by Gradle (via [foojay](https://github.com/gradle/foojay-toolchains)). Just needs JDK 17+ to run Gradle itself.

```bash
./gradlew buildPlugin       # Build ZIP
./gradlew test              # 65 tests
./gradlew runIde            # Launch sandbox IDE
./gradlew clean buildPlugin test  # Full rebuild
```

Debug: **Gradle tool window > Tasks > intellij platform > runIde > right-click > Debug**.

### Project Structure

```
src/main/kotlin/com/block/wt/
  model/          WorktreeInfo, WorktreeStatus, ContextConfig, ProvisionMarker
  git/            GitParser, GitBranchHelper, GitDirResolver
  provision/      ProvisionMarkerService, ProvisionHelper, ProvisionSwitchHelper
  agent/          AgentDetection (interface), AgentDetector (lsof + session files)
  util/           PathHelper, PathExtensions, ConfigFileHelper, ProcessHelper/Runner
  services/       WorktreeService (facade), GitClient, WorktreeEnricher,
                  WorktreeRefreshScheduler, CreateWorktreeUseCase,
                  SymlinkSwitchService, ContextService, MetadataService,
                  BazelService, ExternalChangeWatcher
  actions/        14 actions: worktree/, context/, metadata/, util/
  ui/             WorktreePanel, WorktreeTableModel, ContextPopupHelper,
                  ContextStatusBarWidgetFactory, dialogs, Notifications
  settings/       WtPluginSettings, WtSettingsComponent, WtSettingsConfigurable
src/test/kotlin/  65 tests across 8 classes + test fakes
```

### Tests

| Test class | Coverage |
|---|---|
| `PathHelperTest` | Atomic symlink, tilde expansion, normalization |
| `ConfigFileHelperTest` | Config parse/write, missing files, quoted paths |
| `WorktreeInfoTest` | Porcelain parsing, WorktreeStatus sealed class, isDirty |
| `WorktreeServiceTest` | Parsing + agent enrichment with test fakes |
| `MetadataServiceTest` | Path deduplication, directory copy |
| `MetadataServiceStaticTest` | Static export/import |
| `ProvisionMarkerServiceTest` | Markers: write/read/remove, multi-context, linked worktrees |
| `GitDirResolverTest` | Git dir resolution (main + linked) |

---

## Architecture

| Decision | Rationale |
|---|---|
| Atomic symlink swap | `create-temp + Files.move(ATOMIC_MOVE)` -- `rename(2)` syscall, zero gap |
| Git CLI over Git4Idea | `git worktree list --porcelain` is more reliable for all worktree states |
| Direct `~/.wt/` file I/O | Ensures CLI interop (no `PersistentStateComponent`) |
| Coroutines + StateFlow | Reactive UI from background loading |
| Facade pattern | `WorktreeService` delegates to `GitClient`, `WorktreeEnricher`, `WorktreeRefreshScheduler` internally; 18 callers unchanged |
| Dual agent detection | `lsof` for running processes + session files for recently active; path encoding matches Claude Code (`[^a-zA-Z0-9]` -> `-`) |
| `WorktreeStatus` sealed class | Replaces 6 nullable `Int?` with `NotLoaded` / `Loaded` states |
| `Result<Unit>` mutations | `ProvisionMarkerService` preserves exceptions instead of bare `Boolean` |

## Compatibility

| | |
|---|---|
| IDE versions | 2025.3 (253) through 2026.1 (261.*) |
| Platforms | macOS, Linux |
| Build | Gradle 9.3.1, Kotlin 2.3.0, IntelliJ Platform Gradle Plugin 2.11.0, JDK 25 toolchain → JVM 21 bytecode |
