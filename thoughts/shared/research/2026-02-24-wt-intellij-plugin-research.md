---
date: 2026-02-24T07:30:00Z
researcher: guodong
git_commit: b9efc6b2ec3782f48c0a588773c20fc6740771d9
branch: guodong/intellij_plugin
repository: block/wt
topic: "Deep Research — wt-intellij-plugin Implementation"
tags: [research, codebase, intellij, plugin, kotlin, worktree, symlink, provision, bazel, metadata]
status: complete
last_updated: 2026-02-24
last_updated_by: guodong
last_updated_note: "Comprehensive re-research with exact line counts, full method signatures, and cross-component dependency analysis at commit b9efc6b"
---

# Research: wt-intellij-plugin Implementation

**Date**: 2026-02-24T16:41:41Z
**Researcher**: guodong
**Git Commit**: `b9efc6b`
**Branch**: guodong/intellij_plugin
**Repository**: [block/wt](https://github.com/block/wt)

## Research Question

Comprehensive documentation of the `wt-intellij-plugin` implementation: every package, class, method, data flow, IntelliJ platform integration, build configuration, and test coverage.

## Summary

The `wt-intellij-plugin` is a Kotlin-based IntelliJ Platform plugin (4,447 lines of source across 58 files, plus 1,314 lines of tests across 10 files) that provides native git worktree management for all JetBrains IDEs. It is the IDE companion to the `wt` CLI and operates on the same `~/.wt/` configuration files. The plugin's core innovation is **atomic symlink switching**: instead of opening a new IDE window per worktree, it swaps the symlink target that IntelliJ has open, achieving sub-second context switches without IDE restarts.

### Key Metrics

| Metric | Value |
|---|---|
| Source files (Kotlin) | 58 |
| Source lines (Kotlin) | 4,447 |
| Test files | 10 (8 test classes + 2 fakes) |
| Test lines | 1,314 |
| Test methods | 62 |
| Resource files | 2 (plugin.xml: 206 lines, welcome.html: 647 lines) |
| Packages | 9 (`model`, `git`, `provision`, `agent`, `util`, `services`, `actions/*`, `ui`, `settings`) |
| IntelliJ actions | 15 (in 3 action groups) |
| Services | 5 project + 2 application + 1 startup + 1 lifecycle listener |
| Data models | 6 (`WorktreeInfo`, `WorktreeStatus`, `ContextConfig`, `ProvisionMarker`, `ProvisionEntry`, `MetadataPattern`) |
| Plugin dependencies | `com.intellij.modules.platform` + `Git4Idea` |
| Build tool | Gradle 9.3.1 + Kotlin 2.3.0 + IntelliJ Platform Plugin 2.11.0 |
| JDK | Toolchain 25, bytecode target 21 |
| IDE compatibility | 2025.3 (build 253) through 2026.1 (261.*) |

---

## Detailed Findings

### 1. Build Configuration

#### `build.gradle.kts` (72 lines)

| Configuration | Value |
|---|---|
| `kotlin.jvmToolchain` | 25 |
| `jvmTarget` | `JVM_21` |
| IntelliJ Platform Plugin | `org.jetbrains.intellij.platform` v2.11.0 |
| Kotlin | `org.jetbrains.kotlin.jvm` v2.3.0 |
| Platform target | `intellijIdea("2025.3.3")` |
| Bundled plugin dependency | `Git4Idea` |
| Test framework | `TestFrameworkType.Platform` + `junit:junit:4.13.2` |
| `runIde` JVM args | `-Xmx2g`, `idea.is.internal=true` |
| Maven repository | `https://maven.global.square/artifactory/square-public` + IntelliJ defaults |

#### `gradle.properties` (12 lines)

| Property | Value |
|---|---|
| `pluginGroup` | `com.block.wt` |
| `pluginName` | `Worktree Manager` |
| `pluginVersion` | `0.1.0` |
| `pluginSinceBuild` | `253` (IntelliJ 2025.3) |
| `pluginUntilBuild` | `261.*` (IntelliJ 2026.1) |
| `platformVersion` | `2025.3.3` |
| `kotlin.stdlib.default.dependency` | `false` (uses bundled IDE stdlib) |
| `org.gradle.configuration-cache` | `true` |
| `org.gradle.caching` | `true` |

#### `settings.gradle.kts` (5 lines)

Root project name `wt-intellij-plugin`. Uses `org.gradle.toolchains.foojay-resolver-convention` v0.9.0 for automatic JDK provisioning.

---

### 2. Plugin Manifest — `plugin.xml` (206 lines)

**ID**: `com.block.wt`, **Name**: Worktree Manager, **Vendor**: Block

#### Extensions Registered

| Extension Point | Implementation | Level |
|---|---|---|
| `toolWindow` (id=`Worktrees`) | `WorktreeToolWindowFactory` | bottom anchor, DumbAware |
| `applicationConfigurable` | `WtSettingsConfigurable` | under "Tools" |
| `applicationService` | `WtPluginSettings` | app-level persistent state |
| `projectService` | `WorktreeService` | project-level |
| `projectService` | `SymlinkSwitchService` | project-level |
| `projectService` | `MetadataService` | project-level |
| `projectService` | `BazelService` | project-level |
| `projectService` | `ExternalChangeWatcher` | project-level |
| `applicationService` | `ContextService` | app-level |
| `statusBarWidgetFactory` | `ContextStatusBarWidgetFactory` | after positionWidget |
| `postStartupActivity` | `WtStartupActivity` | runs after project open |
| `notificationGroup` | "Worktree Manager" | BALLOON display |

#### Application Listener

`MetadataAutoExporter` listens on `AppLifecycleListener` for IDE shutdown.

#### Actions (15 total, 3 groups)

**`Wt.VcsGroup`** (popup, added to VcsGroups):
- `Wt.SwitchWorktree` — `Ctrl+Alt+W`
- `Wt.CreateWorktree` — `Ctrl+Alt+Shift+W`
- `Wt.RemoveWorktree`
- `Wt.RemoveMerged`
- `Wt.ProvisionWorktree`
- `Wt.SwitchContext`
- `Wt.AddContext`
- `Wt.ExportMetadata`
- `Wt.ImportMetadata`
- `Wt.RefreshBazelTargets`
- `Wt.Welcome`

**`Wt.ToolWindowToolbar`** (toolbar):
- Create, Switch, Remove, OpenTerminal, SwitchContext, AddContext, Refresh

**`Wt.WorktreeRowContextMenu`** (right-click):
- Switch, OpenTerminal, RevealInFinder, CopyPath, ProvisionWorktree, Remove, ExportMetadata, ImportMetadata

---

### 3. Data Models (`model/`)

#### `ContextConfig.kt` (13 lines)

Pure value `data class` with 7 required fields: `name`, `mainRepoRoot`, `worktreesBase`, `activeWorktree`, `ideaFilesBase`, `baseBranch`, `metadataPatterns`. Serialized to/from `~/.wt/repos/<name>.conf` via `ConfigFileHelper`.

#### `WorktreeInfo.kt` (48 lines)

Central domain data class with `WorktreeStatus` sealed class:

```kotlin
sealed class WorktreeStatus {
    data object NotLoaded : WorktreeStatus()
    data class Loaded(
        val staged: Int, val modified: Int, val untracked: Int,
        val conflicts: Int, val ahead: Int?, val behind: Int?,
    ) : WorktreeStatus() {
        val isDirty: Boolean get() = staged + modified + untracked + conflicts > 0
    }
}

data class WorktreeInfo(
    val path: Path, val branch: String?, val head: String,
    val isMain: Boolean = false, val isLinked: Boolean = false,
    val isPrunable: Boolean = false, val status: WorktreeStatus = WorktreeStatus.NotLoaded,
    val isProvisioned: Boolean = false, val isProvisionedByCurrentContext: Boolean = false,
    val activeAgentSessionIds: List<String> = emptyList(),
)
```

Computed properties: `hasActiveAgent`, `isDirty: Boolean?` (null if NotLoaded), `displayName`, `shortPath`, `relativePath(worktreesBase)`.

#### `ProvisionMarker.kt` + `ProvisionEntry.kt` (14 lines)

JSON model for `wt-provisioned` marker files stored in `.git/` directories:

```kotlin
data class ProvisionMarker(val current: String, val provisions: List<ProvisionEntry>)
data class ProvisionEntry(
    val context: String,
    @SerializedName("provisioned_at") val provisionedAt: String,
    @SerializedName("provisioned_by") val provisionedBy: String,
)
```

#### `MetadataPattern.kt` (28 lines)

Data class with `name`/`description`. Companion contains `KNOWN_PATTERNS` (14 patterns: `.idea`, `.ijwb`, `.aswb`, `.clwb`, `.bazelproject`, `.xcodeproj`, `.xcworkspace`, `.swiftpm`, `.vscode`, `.bsp`, `.metals`, `.eclipse`, `.classpath`, `.project`, `.settings`) and `BAZEL_IDE_PATTERNS` set (`{".ijwb", ".aswb", ".clwb"}`).

---

### 4. Git Package (`git/`)

#### `GitParser.kt` (57 lines) — Kotlin `object`

Parses `git worktree list --porcelain` output. Splits on `"\n\n"` for worktree blocks. Per block, dispatches on line prefixes: `"worktree "` → path, `"HEAD "` → SHA, `"branch "` → strips `"refs/heads/"`, `"detached"` → null branch, `"prunable"` → flag. Sets `isMain = index == 0`. Compares `path.normalizeSafe()` against `linkedWorktreePath` for `isLinked`.

#### `GitBranchHelper.kt` (19 lines) — Kotlin `object`

- `sanitizeBranchName(name)`: trims, rejects `".."`, blank, or leading `"-"`.
- `worktreePathForBranch(worktreesBase, branchName)`: replaces `/` with `-`, resolves against base.

#### `GitDirResolver.kt` (30 lines) — Kotlin `object`

`resolveGitDir(worktreePath): Path?`: If `.git` is a directory → returns it. If `.git` is a file → reads `gitdir: ...` content, resolves absolute or relative. Otherwise → null. IO exceptions caught → null.

---

### 5. Services (`services/`)

#### `WorktreeService.kt` (269 lines) — `@Service(PROJECT)` — Facade

Constructor receives `Project` and platform-injected `CoroutineScope`.

**Injectable fields** (for testing):
```kotlin
internal var processRunner: ProcessRunner = ProcessHelper
internal var agentDetection: AgentDetection = AgentDetector
```

**Internal components** (lazy):
- `gitClient: GitClient` — stateless git CLI wrapper
- `enrichers: List<WorktreeEnricher>` — `[ProvisionStatusEnricher, AgentStatusEnricher]`
- `refreshScheduler: WorktreeRefreshScheduler`

**State**: `_worktrees: MutableStateFlow<List<WorktreeInfo>>`, `_isLoading: MutableStateFlow<Boolean>`, `statusMutex: Mutex`, `@Volatile lastRefreshTime: Long`

**Key methods**:
- `refreshWorktreeList()` — launches coroutine: calls `listWorktrees()`, stores result, optionally loads status indicators per-worktree in parallel `async` blocks guarded by `statusMutex`.
- `listWorktrees()` — suspend on `Dispatchers.IO`: runs `git worktree list --porcelain`, delegates to `parseAndEnrich()`
- `parseAndEnrich(output, linkedPath)` — `internal fun`: parses via `GitParser`, applies enrichers via `fold()`
- `loadStatusIndicators(wt)` — suspend: parses `git status --porcelain` (handles staged/modified/untracked/conflicts columns) and `git rev-list --left-right --count`
- Facade delegates to `gitClient`: `createWorktree`, `removeWorktree`, `getMergedBranches`, `hasUncommittedChanges`, `stashSave`, `stashPop`, `checkout`, `pullFfOnly`, `getCurrentBranch`, `getCurrentRevision`
- `getMainRepoRoot()` — reads from context config, falls back to `GitRepositoryManager`
- `startPeriodicRefresh()` / `stopPeriodicRefresh()` — delegates to `refreshScheduler`

#### `GitClient.kt` (131 lines) — Stateless git CLI wrapper

All methods are `suspend fun` with `withContext(Dispatchers.IO)`. Wraps `ProcessRunner` for: `createWorktree`, `removeWorktree`, `getMergedBranches`, `hasUncommittedChanges`, `stashSave`, `stashPop` (finds stash by name via `git stash list`), `checkout`, `pullFfOnly`, `getCurrentBranch`, `getCurrentRevision`.

#### `WorktreeEnricher.kt` (46 lines) — Interface + 2 implementations

```kotlin
interface WorktreeEnricher {
    fun enrich(worktrees: List<WorktreeInfo>): List<WorktreeInfo>
}
```

**`ProvisionStatusEnricher`**: reads `ProvisionMarkerService.isProvisioned()` and `isProvisionedByContext()` per worktree.

**`AgentStatusEnricher`**: calls `agentDetection.detectActiveAgentDirs()` once (union of lsof + session detection), then per worktree matches paths and reads session IDs. Uses `"(running)"` placeholder for idle processes with no recent sessions.

#### `WorktreeRefreshScheduler.kt` (33 lines)

Coroutine loop with `@Volatile periodicRefreshJob`. Reads `autoRefreshIntervalSeconds` from settings. `start()` cancels any existing job before launching. `stop()` cancels and nulls.

#### `CreateWorktreeUseCase.kt` (61 lines)

Transactional create flow receiving `WorktreeService` and `Project`.

```kotlin
suspend fun runCreateNewBranchFlow(indicator, mainRepoRoot, baseBranch, branchName, worktreePath, config)
```

Steps with `indicator.checkCanceled()` between each:
1. Save current branch/revision
2. Stash uncommitted changes (unique name `wta-<ts>-<pid>`)
3. Checkout base branch
4. Pull `--ff-only`
5. Create worktree (`git worktree add -b`)
6. `ProvisionHelper.provisionWorktree()`
7. Refresh worktree list
- `finally` (via `runCatching`): restore original branch + pop stash

#### `SymlinkSwitchService.kt` (114 lines) — `@Service(PROJECT)`

5-phase atomic switch:
1. `FileDocumentManager.saveAllDocuments()` via EDT `WriteAction`
2. `PathHelper.atomicSetSymlink()` via `Dispatchers.IO`
3. `FileDocumentManager.reloadFromDisk()` per open editor via EDT `WriteAction`
4. `VfsUtil.markDirtyAndRefresh()` + `VirtualFileManager.asyncRefresh`
5. `GitRepositoryManager.repo.update()` + `VcsDirtyScopeManager.markEverythingDirty()` via `Dispatchers.IO`

#### `ContextService.kt` (68 lines) — `@Service(APP)`

Manages multi-repo contexts. State: `_currentContextName: MutableStateFlow<String?>`, `_contexts: MutableStateFlow<List<ContextConfig>>`, `@Volatile cachedConfig`. Methods: `initialize()`, `reload()`, `listContexts()`, `getCurrentConfig()`, `getConfig(name)`, `switchContext(name)`, `addContext(config)`. All delegate to `ConfigFileHelper`.

#### `MetadataService.kt` (201 lines) — `@Service(PROJECT)`

- `exportMetadata(source, vault, patterns)` — delegates to static companion
- `importMetadata(vault, target)` — resolves symlinks in vault, copies real directory contents
- `detectPatterns(repoPath)` — checks `MetadataPattern.KNOWN_PATTERNS` against repo
- Static `exportMetadataStatic()` — creates symlinks in vault pointing to source dirs, with deduplication of nested paths

#### `BazelService.kt` (157 lines) — `@Service(PROJECT)`

- `installBazelSymlinks(mainRepo, worktree)` — copies `bazel-out`, `bazel-bin`, `bazel-testlogs`, `bazel-genfiles` symlinks
- `refreshTargets(bazelDir)` — parses `.bazelproject`, runs `bazel query`, writes sorted targets file
- `refreshAllBazelMetadata(repoPath)` — iterates `BAZEL_IDE_PATTERNS` and calls `refreshTargets`
- `parseDirectoriesSection(projectViewFile)` — state machine parsing of `.bazelproject` format

#### `ExternalChangeWatcher.kt` (155 lines) — `@Service(PROJECT)`, `Disposable`

NIO `WatchService` on 3 directories:
1. `~/.wt/` — context changes (`current`, `*.conf`)
2. `config.activeWorktree.parent` — symlink changes
3. `mainRepoRoot/.git/worktrees` — linked worktree create/delete

500ms debounced refresh via `debouncedRefresh()`. Auto-restarts on context switch or key invalidation.

#### `WtStartupActivity.kt` (52 lines) — `ProjectActivity`

Runs on project open:
1. `ContextService.initialize()`
2. `ExternalChangeWatcher.startWatching()`
3. `WorktreeService.refreshWorktreeList()`
4. If context config exists: `ContextSetupDialog.showIfNeeded()` on EDT
5. `showWelcomeTabIfNeeded()` — version-gated via `lastWelcomeVersion`, requires JCEF, uses `WelcomePageHelper.buildThemedHtml()` + `HTMLEditorProvider`

#### `MetadataAutoExporter.kt` (59 lines) — `AppLifecycleListener`

Exports metadata on IDE shutdown when `autoExportOnShutdown` setting is enabled. Resolves source path from symlink target with open-project cross-reference.

---

### 6. Provision Package (`provision/`)

#### `ProvisionMarkerService.kt` (147 lines) — Kotlin `object`

Reads/writes `<gitDir>/wt-provisioned` JSON files. Constants: `MARKER_FILE = "wt-provisioned"`, `IDE_METADATA_DIRS = [".idea", ".ijwb", ".aswb", ".clwb", ".vscode"]`. Uses `GsonBuilder().setPrettyPrinting()`.

| Method | Description |
|---|---|
| `isProvisioned(worktreePath)` | Fast filesystem check via `GitDirResolver.resolveGitDir()` |
| `isProvisionedByContext(worktreePath, contextName)` | Reads JSON, checks `marker.current == contextName` |
| `readProvisionMarker(worktreePath)` | Parses JSON with `@Suppress("SENSELESS_COMPARISON")` null-safety guards for Gson |
| `writeProvisionMarker(worktreePath, contextName): Result<Unit>` | Creates/updates marker, deduplicates entries, sets `provisionedBy = "intellij-plugin"` |
| `removeProvisionMarker(worktreePath, contextName?): Result<Unit>` | Removes specific context (promotes remaining) or deletes entire file |
| `hasExistingMetadata(worktreePath)` | Checks `IDE_METADATA_DIRS` |

#### `ProvisionHelper.kt` (70 lines) — Kotlin `object`

Consolidated provision flow — `suspend provisionWorktree(project, worktreePath, config, keepExistingFiles=false, indicator?)`:
1. Write provision marker
2. Import metadata from vault (skipped if `keepExistingFiles`)
3. Install Bazel symlinks (skipped if `keepExistingFiles`)

Errors collected into a list and reported as a single warning notification.

#### `ProvisionSwitchHelper.kt` (126 lines) — Kotlin `object`

Decision tree for `switchWithProvisionPrompt(project, wt)`:
1. If `confirmBeforeSwitch` → yes/no dialog
2. If `promptProvisionOnSwitch` AND not provisioned by current context:
   - **Has existing metadata**: 4-choice dialog ("Provision keep files" / "Provision overwrite" / "Switch Only" / "Cancel")
   - **No existing metadata**: 3-choice dialog ("Provision & Switch" / "Switch Only" / "Cancel")
3. Otherwise: direct switch via `SymlinkSwitchService`

`provisionAndSwitch()` runs `ProvisionHelper.provisionWorktree()` then `SymlinkSwitchService.doSwitch()` in a cancellable background task.

---

### 7. Agent Detection (`agent/`)

#### `AgentDetection.kt` (13 lines) — Interface

```kotlin
interface AgentDetection {
    fun detectActiveAgentDirs(): Set<Path>
    fun detectActiveSessionIds(worktreePath: Path): List<String>
}
```

#### `AgentDetector.kt` (146 lines) — `object : AgentDetection`

Constants: `SESSION_ACTIVE_THRESHOLD_MS = 30 * 60 * 1000` (30 min), `CLAUDE_PROJECTS_DIR = ".claude/projects"`.

| Method | Description |
|---|---|
| `detectActiveAgentDirs()` | Union of `detectViaLsof()` + `detectViaSessions()` |
| `detectActiveSessionIds(worktreePath)` | Scans `~/.claude/projects/<encoded>/` for `.jsonl` files within 30-min threshold |
| `detectViaLsof()` | Tries `/usr/sbin/lsof`, `/usr/bin/lsof`, `lsof` with flags `-a -d cwd -c claude -Fn`. Returns `emptySet()` on Windows. |
| `detectViaSessions()` | Scans all `~/.claude/projects/` dirs for recent sessions, decodes dir names to paths |
| `encodePath(path)` | Replaces non-alphanumeric chars with `-` |
| `decodeDirToPath(encoded)` | Reverse encoding with **round-trip validation**. Returns null on Windows or validation failure. |

All methods defensively wrapped in `try/catch` returning empty collections.

---

### 8. Actions (`actions/`)

#### Base Classes — `WtAction.kt` (69 lines)

**`WtAction`** — `AnAction(), DumbAware`:
- `getActionUpdateThread() = BGT`
- `update()` delegates to `isAvailable()` (default: `project != null`)
- `runInBackground(project, title, cancellable, action)` — `Task.Backgroundable` + `runBlockingCancellable`

**`WtConfigAction`** — extends `WtAction`:
- `isAvailable()` requires both project and context config
- `requireConfig()` helper

**`WtTableAction`** — `AnAction(), DumbAware`:
- `getActionUpdateThread() = EDT` (reads Swing state)
- `update()` checks `getSelectedPanel()?.getSelectedWorktree() != null`

#### Action Inheritance Hierarchy

```
AnAction (IntelliJ Platform)
├── WtAction : AnAction, DumbAware
│   ├── SwitchWorktreeAction (59 lines)    [worktree/]
│   ├── RemoveWorktreeAction (111 lines)   [worktree/]
│   ├── RemoveMergedAction (90 lines)      [worktree/]
│   ├── CreateWorktreeAction (56 lines)    [worktree/]
│   ├── SwitchContextAction (33 lines)     [context/]
│   ├── AddContextAction (71 lines)        [context/]
│   ├── RefreshWorktreeListAction (13 lines) [util/]
│   ├── OpenInTerminalAction (48 lines)    [util/]
│   ├── WelcomeAction (19 lines)           [util/]
│   └── WtConfigAction : WtAction
│       ├── ExportMetadataAction (36 lines)        [metadata/]
│       ├── ImportMetadataAction (36 lines)         [metadata/]
│       └── RefreshBazelTargetsAction (37 lines)    [metadata/]
└── WtTableAction : AnAction, DumbAware
    ├── ProvisionWorktreeAction (57 lines)  [worktree/]
    ├── RevealInFinderAction (13 lines)     [util/]
    └── CopyWorktreePathAction (14 lines)   [util/]
```

#### Key Action Behaviors

- **SwitchWorktreeAction**: Fast-path from table selection via `WorktreePanel.DATA_KEY`; slow-path loads worktrees and shows popup via `BaseListPopupStep`.
- **RemoveWorktreeAction**: Safety checks (prevents main repo removal, warns on dirty/linked), auto-switches symlink to main if removing linked worktree.
- **RemoveMergedAction**: Batch removes clean merged worktrees, skips dirty ones.
- **CreateWorktreeAction**: Shows `CreateWorktreeDialog`, delegates new-branch flow to `CreateWorktreeUseCase`.
- **ProvisionWorktreeAction**: Extends `WtTableAction`, disabled when already provisioned by current context.
- **OpenInTerminalAction**: Uses reflection to access `TerminalToolWindowManager.createLocalShellWidget()`.
- **AddContextAction**: Overrides `isAvailable()` to return `true` unconditionally (no project needed).

---

### 9. UI Package (`ui/`)

#### `WorktreeToolWindowFactory.kt` (38 lines)

Implements `ToolWindowFactory, DumbAware`. Creates `WorktreePanel`, starts periodic refresh, subscribes to `ToolWindowManagerListener` for stale-refresh on tool window show.

#### `WorktreePanel.kt` (341 lines) — Main panel

`JPanel(BorderLayout)` implementing `DataProvider` and `Disposable`.

Layout:
```
NORTH  → ActionToolbar (Wt.ToolWindowToolbar group)
CENTER → CardLayout ("table" card: JBScrollPane(JBTable), "empty" card: add-context prompt)
SOUTH  → Context label (clickable, shows context switch popup)
```

State observation via `combine(worktreeService.worktrees, contextService.currentContextName).collectLatest` on `Dispatchers.Main`. Shows `CARD_EMPTY` when no context is configured. Double-click on table row triggers `ProvisionSwitchHelper.switchWithProvisionPrompt()`. Right-click context menu via `PopupHandler.installPopupMenu(table, "Wt.WorktreeRowContextMenu", ...)`.

Tooltip builders for Status (HTML with Staged/Modified/Untracked/Conflicts/Ahead/Behind), Agent (session IDs), and Provisioned (reads marker, shows provision history).

`refreshIfStale()`: checks `lastRefreshTime` against 2000ms threshold.

#### `WorktreeTableModel.kt` (81 lines)

6 columns: Linked (`*`), Path (relative), Branch (+ `[main]`), Status (Unicode symbols: `⚠` conflicts, `●` staged, `✱` modified, `…` untracked, `↑↓` ahead/behind), Agent (robot emoji + session IDs), Provisioned (`✓` current / `~` other / empty).

#### `CreateWorktreeDialog.kt` (64 lines)

`DialogWrapper` with branch text field (inline validation: no blank, no `..`, no leading `-`), "Create new branch" checkbox, and auto-derived path field.

#### `ContextSetupDialog.kt` (199 lines)

First-run dialog shown once per context. `CheckBoxList<WorktreeEntry>` of unprovisioned worktrees. Buttons: "Provision Selected" (OK), "Remind Me Later" (Cancel), "Skip Setup" (left-side action). Runs provisioning in background with progress fraction. Tracks completion in `WtPluginSettings.state.setupCompletedContexts`.

#### `AddContextDialog.kt` (237 lines)

Full context creation form: repo path (with folder browser), context name, base branch (auto-detected via `git symbolic-ref`), active worktree, derived worktrees/idea-files paths. Pattern detection from `MetadataPattern.KNOWN_PATTERNS`. Validates: directory exists, is git repo, name matches `[a-zA-Z0-9_-]+`, no duplicate context.

#### `ContextStatusBarWidgetFactory.kt` (79 lines)

`StatusBarWidgetFactory` + `StatusBarWidget.MultipleTextValuesPresentation`. Shows `"wt: <name>"` or `"wt: (none)"`. Click shows context switch popup via `ContextPopupHelper`. Updates via `currentContextName.collectLatest`.

#### `ContextPopupHelper.kt` (57 lines) — Kotlin `object`

Shared popup factory used by 3 callers (SwitchContextAction, WorktreePanel, ContextStatusBarWidget). Builds `BaseListPopupStep` with optional "Add Context..." entry.

#### `Notifications.kt` (29 lines) — Kotlin `object`

Wraps `NotificationGroupManager` with `info`, `warning`, `error` methods targeting the "Worktree Manager" group.

#### `WelcomePageHelper.kt` (123 lines) — Kotlin `object`

Builds themed HTML by:
1. Loading `/welcome.html` from classpath
2. Loading `/ui.png` as base64 data URI
3. Reading IntelliJ theme colors at runtime (`EditorColorsManager`, `UIUtil`, `JBUI.CurrentTheme`, `JBColor.namedColor`)
4. Deriving ~28 CSS custom properties via `ColorUtil` (brighten/darken/blend/withAlpha)
5. Injecting `:root { }` CSS block and screenshot data URI into template placeholders

#### `welcome.html` (647 lines)

Self-contained HTML5 page with sections: Hero, Quick Reference (6 feature cards), How Switching Works (SVG diagram), Tool Window screenshot, Getting Started (5 steps), Tips (4 cards), Footer. CSS animations with staggered `fadeInUp`. Fonts: JetBrains Mono + Source Serif 4.

---

### 10. Settings (`settings/`)

#### `WtPluginSettings.kt` (44 lines) — `@Service(APP)`, `PersistentStateComponent`

`State` data class with **11 fields**:

| Setting | Type | Default | Used By |
|---|---|---|---|
| `showStatusBarWidget` | `Boolean` | `true` | widget visibility |
| `autoRefreshOnExternalChange` | `Boolean` | `true` | file watcher |
| `confirmBeforeSwitch` | `Boolean` | `false` | `ProvisionSwitchHelper` |
| `confirmBeforeRemove` | `Boolean` | `true` | `RemoveWorktreeAction` |
| `statusLoadingEnabled` | `Boolean` | `true` | `WorktreeService.refreshWorktreeList()` |
| `autoExportOnShutdown` | `Boolean` | `false` | `MetadataAutoExporter` |
| `debounceDelayMs` | `Long` | `500` | `ExternalChangeWatcher` |
| `promptProvisionOnSwitch` | `Boolean` | `true` | `ProvisionSwitchHelper` |
| `autoRefreshIntervalSeconds` | `Int` | `30` | `WorktreeRefreshScheduler` |
| `setupCompletedContexts` | `MutableList<String>` | `mutableListOf()` | `ContextSetupDialog.showIfNeeded()` |
| `lastWelcomeVersion` | `String` | `""` | `WtStartupActivity.showWelcomeTabIfNeeded()` |

`@Volatile private var state = State()`. Stored in `WtPluginSettings.xml`.

#### `WtSettingsComponent.kt` (100 lines) + `WtSettingsConfigurable.kt` (30 lines)

Settings UI panel using IntelliJ UI DSL with 2 groups ("General" and "Confirmations"). 8 of the 11 settings are user-editable (excludes `debounceDelayMs`, `setupCompletedContexts`, `lastWelcomeVersion`). Uses local var binding pattern with `isModified`/`apply`/`reset` delegation.

---

### 11. Utility Package (`util/`)

#### `ProcessRunner.kt` (12 lines) — Interface

```kotlin
interface ProcessRunner {
    fun run(command: List<String>, workingDir: Path? = null, timeoutSeconds: Long = 60): ProcessHelper.ProcessResult
    fun runGit(args: List<String>, workingDir: Path? = null): ProcessHelper.ProcessResult
}
```

#### `ProcessHelper.kt` (53 lines) — `object : ProcessRunner`

Uses IntelliJ's `GeneralCommandLine` + `CapturingProcessHandler`. `ProcessResult(exitCode, stdout, stderr)` with `isSuccess` computed property. Timeout returns `exitCode = -1`. Failed commands logged at `DEBUG` level. `runGit` prepends `"git"` to args.

#### `PathHelper.kt` (58 lines) — Kotlin `object`

- `expandTilde(path)` — resolves `~` to `$HOME`
- `normalize(path)` / `normalizeSafe(path)` — `toRealPath()` with fallback
- `atomicSetSymlink(linkPath, newTarget)` — create temp symlink + `Files.move(ATOMIC_MOVE)` + cleanup on error
- `isSymlink(path)` / `readSymlink(path)`
- Computed: `wtRoot` (`~/.wt`), `reposDir` (`~/.wt/repos`), `currentFile` (`~/.wt/current`)

#### `PathExtensions.kt` (12 lines)

```kotlin
fun Path.normalizeSafe(): Path = try { toRealPath() } catch (_: Exception) { toAbsolutePath().normalize() }
fun Path.relativizeAgainst(base: Path?): String =
    if (base != null && startsWith(base)) base.relativize(this).toString() else toString()
```

#### `ConfigFileHelper.kt` (71 lines) — Kotlin `object`

- `readConfig(confFile)` — parses `WT_*` key=value lines via regex, returns `ContextConfig?`
- `writeConfig(confFile, config)` — writes all 6 keys with double-quoted values
- `readCurrentContext()` — reads `~/.wt/current`
- `setCurrentContext(name)` — writes to `~/.wt/current`
- `listConfigFiles()` — lists `~/.wt/repos/*.conf`

---

### 12. Test Suite

10 test files, 1,314 lines total, 62 test methods. All JUnit 4. No mocking frameworks — hand-written fakes.

#### Test Utilities

| File | Lines | Description |
|---|---|---|
| `testutil/FakeProcessRunner.kt` | 20 | `ProcessRunner` impl returning canned `ProcessResult` from a `Map<List<String>, ProcessResult>` |
| `testutil/FakeAgentDetection.kt` | 15 | `AgentDetection` impl returning configurable `Set<Path>` and `Map<Path, List<String>>` |

#### Test Classes

| File | Lines | Tests | What It Tests |
|---|---|---|---|
| `model/WorktreeInfoTest.kt` | 230 | 14 | Parsing, branch validation, computed props, `WorktreeStatus`, `sanitizeBranchName` edge cases |
| `git/GitDirResolverTest.kt` | 130 | 7 | Main worktree, linked (absolute/relative gitdir), no `.git`, malformed, unreadable, empty |
| `provision/ProvisionMarkerServiceTest.kt` | 254 | 13 | Write/read/remove markers, multi-context history, dedup, JSON edge cases, linked worktrees |
| `services/WorktreeServiceTest.kt` | 141 | 6 | `GitParser.parsePorcelainOutput`, agent enrichment with fakes, `FakeProcessRunner` behavior |
| `services/MetadataServiceTest.kt` | 104 | 4 | Deduplication logic, directory copy |
| `services/MetadataServiceStaticTest.kt` | 108 | 4 | Static `exportMetadataStatic`: symlink creation, replacement, vault auto-creation |
| `util/ConfigFileHelperTest.kt` | 158 | 6 | Config parse/write round-trip, quoted values, spaces in paths, missing fields |
| `util/PathHelperTest.kt` | 154 | 8 | Atomic symlink create/replace/cleanup, tilde expansion, isSymlink, readSymlink, normalizeSafe |

All tests using filesystem create temp directories and clean up via `deleteRecursive` in `finally` blocks.

---

## Architecture Documentation

### Data Flow Diagrams

#### Startup Sequence

```
IDE opens project
  -> WtStartupActivity.execute()
      -> ContextService.initialize()             [reads ~/.wt/current + repos/*.conf]
      -> ExternalChangeWatcher.startWatching()    [NIO watch on 3 directories]
      -> WorktreeService.refreshWorktreeList()    [async]
          -> git worktree list --porcelain
          -> GitParser.parsePorcelainOutput()
          -> enrichers.fold(parsed):
               ProvisionStatusEnricher.enrich()   [reads .git/wt-provisioned markers]
               AgentStatusEnricher.enrich()       [lsof + .claude/projects/ scan]
          -> (per worktree) loadStatusIndicators() [git status + rev-list, parallel async]
      -> ContextSetupDialog.showIfNeeded()        [on EDT, one-time per context]
      -> showWelcomeTabIfNeeded()                 [JCEF HTML editor, one-time per version]
```

#### Worktree Switch Sequence

```
User action (double-click / Ctrl+Alt+W / popup)
  -> ProvisionSwitchHelper.switchWithProvisionPrompt()
      +-- [if provision needed] ProvisionHelper.provisionWorktree()
      |     1. ProvisionMarkerService.writeProvisionMarker()
      |     2. MetadataService.importMetadata()
      |     3. BazelService.installBazelSymlinks()
      +-- SymlinkSwitchService.switchWorktree()
            1. FileDocumentManager.saveAllDocuments()     [EDT WriteAction]
            2. PathHelper.atomicSetSymlink()              [IO, ATOMIC_MOVE]
            3. FileDocumentManager.reloadFromDisk()       [EDT WriteAction, per editor]
            4. VfsUtil.markDirtyAndRefresh()              [async]
            5. GitRepositoryManager.repo.update()         [IO, per repo]
            6. WorktreeService.refreshWorktreeList()
```

#### Worktree Creation — New Branch Flow

```
CreateWorktreeAction -> CreateWorktreeUseCase.runCreateNewBranchFlow()
  1. getCurrentBranch(mainRepo)                [save original position]
  2. stashSave(mainRepo, "wta-<ts>-<pid>")    [if dirty]
  3. checkout(mainRepo, baseBranch)            [indicator.checkCanceled()]
  4. pullFfOnly(mainRepo)
  5. createWorktree(path, branch, -b)          [git worktree add -b]
  6. ProvisionHelper.provisionWorktree()       [marker + metadata + Bazel]
  7. refreshWorktreeList()
  finally:
    checkout(mainRepo, origBranch)
    stashPop(mainRepo, stashName)
```

#### Enrichment Pipeline

```
WorktreeService.parseAndEnrich(porcelainOutput, linkedPath)
  -> GitParser.parsePorcelainOutput()    -> List<WorktreeInfo>
  -> enrichers.fold(parsed) { list, enricher -> enricher.enrich(list) }
       [0] ProvisionStatusEnricher: reads ProvisionMarkerService per worktree
       [1] AgentStatusEnricher: lsof + session file scan
  -> enriched List<WorktreeInfo>
```

#### State Observation Flow

```
StateFlow sources:
  WorktreeService.worktrees (StateFlow<List<WorktreeInfo>>)
  ContextService.currentContextName (StateFlow<String?>)

Observers:
  WorktreePanel.observeState()
    -> combine() + collectLatest on Dispatchers.Main
    -> tableModel.setWorktrees() + updateContextLabelText() + cardLayout.show()

  ContextStatusBarWidget.install()
    -> currentContextName.collectLatest -> statusBar.updateWidget()
```

### Cross-Service Dependency Map

```
WtStartupActivity
  +-- ContextService              [app singleton]
  +-- ExternalChangeWatcher       [project service]
  +-- WorktreeService             [project service]
  +-- ContextSetupDialog          [UI]
  +-- WelcomePageHelper           [HTML generation]

WorktreeService (facade)
  +-- GitClient                   [internal, stateless git wrapper]
  |     +-- ProcessRunner         [interface, default: ProcessHelper]
  +-- ProvisionStatusEnricher     [enricher]
  |     +-- ProvisionMarkerService
  |     +-- ContextService
  +-- AgentStatusEnricher         [enricher]
  |     +-- AgentDetection        [interface, default: AgentDetector]
  +-- WorktreeRefreshScheduler    [internal]
  +-- GitParser                   [porcelain output parsing]
  +-- WtPluginSettings            [statusLoadingEnabled, autoRefreshIntervalSeconds]

SymlinkSwitchService
  +-- ContextService              [for config]
  +-- PathHelper                  [atomicSetSymlink]
  +-- WorktreeService             [post-switch refresh]
  +-- VFS/Git APIs                [document save/reload, VFS refresh, git update]

ProvisionHelper
  +-- ProvisionMarkerService      [write marker]
  +-- MetadataService             [import metadata]
  +-- BazelService                [install symlinks]

ProvisionSwitchHelper
  +-- ProvisionHelper             [full provision flow]
  +-- ProvisionMarkerService      [hasExistingMetadata, writeProvisionMarker]
  +-- SymlinkSwitchService        [switchWorktree / doSwitch]
  +-- ContextService              [getCurrentConfig]
  +-- WtPluginSettings            [confirmBeforeSwitch, promptProvisionOnSwitch]

CreateWorktreeUseCase
  +-- WorktreeService             [git operations via facade]
  +-- ProvisionHelper             [post-create provision]

ExternalChangeWatcher
  +-- Java NIO WatchService       [filesystem events]
  +-- ContextService              [reload on change]
  +-- WorktreeService             [refresh on change]
  +-- WtPluginSettings            [debounceDelayMs]
```

### Design Patterns

1. **Atomic symlink swap** via `create-temp + Files.move(ATOMIC_MOVE)` — uses `rename(2)` syscall, zero gap
2. **Facade pattern** — `WorktreeService` is the stable public API; internally delegates to `GitClient`, enrichers, and `WorktreeRefreshScheduler`
3. **Enricher pipeline** — composable `WorktreeEnricher` interface with `fold()` application
4. **Interface-based DI** — `ProcessRunner` and `AgentDetection` interfaces enable field injection for testing
5. **Action hierarchy** — `WtAction`/`WtConfigAction`/`WtTableAction` base classes eliminate boilerplate, ensure all actions are `DumbAware`
6. **Use case extraction** — `CreateWorktreeUseCase` encapsulates transactional stash/checkout/pull/create/restore flow with cancellation support
7. **`runBlockingCancellable`** — modern IntelliJ coroutine bridge replacing plain `runBlocking`
8. **Sealed status model** — `WorktreeStatus` distinguishes "not loaded" from "loaded with zeros"
9. **`@SerializedName` annotations** — Gson annotations for snake_case JSON fields
10. **Extension functions** — `Path.normalizeSafe()` and `Path.relativizeAgainst()` as top-level extensions
11. **Direct config file I/O** for `~/.wt/` — ensures CLI interop
12. **Platform-aware agent detection** — `lsof` on macOS/Linux with round-trip path validation, degrades to empty on Windows
13. **Three-level provision prompt** — distinguishes "has existing metadata" (4 options) vs "no metadata" (3 options)
14. **Theme-adaptive welcome page** — runtime IntelliJ color extraction injected into HTML CSS variables

---

## Code References

| File | Lines | Purpose |
|---|---|---|
| `build.gradle.kts` | 72 | Build configuration |
| `gradle.properties` | 12 | Plugin metadata and platform version |
| `settings.gradle.kts` | 5 | Project settings |
| `plugin.xml` | 206 | Extension point registrations, action declarations |
| **Model** | | |
| `model/WorktreeInfo.kt` | 48 | `WorktreeStatus` sealed class + `WorktreeInfo` data class |
| `model/ContextConfig.kt` | 13 | Context configuration value object |
| `model/ProvisionMarker.kt` | 14 | Provision marker JSON model with `@SerializedName` |
| `model/MetadataPattern.kt` | 28 | 14 known IDE metadata patterns |
| **Git** | | |
| `git/GitParser.kt` | 57 | Porcelain output parser |
| `git/GitBranchHelper.kt` | 19 | Branch name validation + path derivation |
| `git/GitDirResolver.kt` | 30 | `.git` dir resolution with IO safety |
| **Services** | | |
| `services/WorktreeService.kt` | 269 | Facade: worktree list, create, remove, status, git ops |
| `services/GitClient.kt` | 131 | Stateless git CLI wrapper |
| `services/WorktreeEnricher.kt` | 46 | Enricher interface + Provision/Agent implementations |
| `services/WorktreeRefreshScheduler.kt` | 33 | Periodic refresh with configurable interval |
| `services/CreateWorktreeUseCase.kt` | 61 | Transactional create-new-branch flow |
| `services/SymlinkSwitchService.kt` | 114 | 5-phase atomic switch sequence |
| `services/ContextService.kt` | 68 | Multi-repo context management |
| `services/MetadataService.kt` | 201 | Vault export/import |
| `services/BazelService.kt` | 157 | Bazel symlinks + target refresh |
| `services/ExternalChangeWatcher.kt` | 155 | NIO file watcher for CLI changes |
| `services/WtStartupActivity.kt` | 52 | Plugin initialization + welcome tab |
| `services/MetadataAutoExporter.kt` | 59 | Metadata export on IDE shutdown |
| **Provision** | | |
| `provision/ProvisionMarkerService.kt` | 147 | Read/write/remove `.git/wt-provisioned` markers |
| `provision/ProvisionHelper.kt` | 70 | Consolidated provision flow |
| `provision/ProvisionSwitchHelper.kt` | 126 | "Provision before switch?" prompt logic |
| **Agent** | | |
| `agent/AgentDetection.kt` | 13 | Interface for agent detection |
| `agent/AgentDetector.kt` | 146 | Claude agent detection via lsof + session files |
| **Actions** | | |
| `actions/WtAction.kt` | 69 | Base classes: WtAction, WtConfigAction, WtTableAction |
| `actions/worktree/SwitchWorktreeAction.kt` | 59 | Switch via table row or popup |
| `actions/worktree/CreateWorktreeAction.kt` | 56 | Create with dialog + use case |
| `actions/worktree/RemoveWorktreeAction.kt` | 111 | Remove with safety checks |
| `actions/worktree/RemoveMergedAction.kt` | 90 | Batch remove merged |
| `actions/worktree/ProvisionWorktreeAction.kt` | 57 | Provision selected worktree |
| `actions/context/SwitchContextAction.kt` | 33 | Context switch popup |
| `actions/context/AddContextAction.kt` | 71 | Context creation |
| `actions/metadata/ExportMetadataAction.kt` | 36 | Export to vault |
| `actions/metadata/ImportMetadataAction.kt` | 36 | Import from vault |
| `actions/metadata/RefreshBazelTargetsAction.kt` | 37 | Bazel target refresh |
| `actions/util/RefreshWorktreeListAction.kt` | 13 | Refresh list |
| `actions/util/OpenInTerminalAction.kt` | 48 | Open in Terminal |
| `actions/util/RevealInFinderAction.kt` | 13 | Reveal in Finder |
| `actions/util/CopyWorktreePathAction.kt` | 14 | Copy path to clipboard |
| `actions/util/WelcomeAction.kt` | 19 | Show welcome HTML tab |
| **UI** | | |
| `ui/WorktreeToolWindowFactory.kt` | 38 | Tool window factory |
| `ui/WorktreePanel.kt` | 341 | Main panel with table, toolbar, context label |
| `ui/WorktreeTableModel.kt` | 81 | 6-column table model |
| `ui/CreateWorktreeDialog.kt` | 64 | Branch + path dialog |
| `ui/ContextSetupDialog.kt` | 199 | First-run provision dialog |
| `ui/AddContextDialog.kt` | 237 | Full context creation dialog |
| `ui/ContextStatusBarWidgetFactory.kt` | 79 | Status bar widget |
| `ui/ContextPopupHelper.kt` | 57 | Shared context switch popup factory |
| `ui/Notifications.kt` | 29 | Notification helper |
| `ui/WelcomePageHelper.kt` | 123 | Theme-adaptive HTML generation |
| **Settings** | | |
| `settings/WtPluginSettings.kt` | 44 | Persistent state (11 fields) |
| `settings/WtSettingsComponent.kt` | 100 | Settings UI panel |
| `settings/WtSettingsConfigurable.kt` | 30 | Settings bridge |
| **Util** | | |
| `util/PathHelper.kt` | 58 | Atomic symlink, path normalization |
| `util/PathExtensions.kt` | 12 | `normalizeSafe()`, `relativizeAgainst()` |
| `util/ConfigFileHelper.kt` | 71 | Read/write `~/.wt/` config files |
| `util/ProcessRunner.kt` | 12 | Interface for process execution |
| `util/ProcessHelper.kt` | 53 | ProcessRunner impl with logging + process cleanup |
| **Resources** | | |
| `resources/META-INF/plugin.xml` | 206 | Plugin manifest |
| `resources/welcome.html` | 647 | Welcome tab HTML |
| **Tests** | | |
| `test/.../model/WorktreeInfoTest.kt` | 230 | 14 tests: parsing, validation, computed props |
| `test/.../git/GitDirResolverTest.kt` | 130 | 7 tests: main/linked worktrees, error cases |
| `test/.../provision/ProvisionMarkerServiceTest.kt` | 254 | 13 tests: write/read/remove, JSON edge cases |
| `test/.../services/WorktreeServiceTest.kt` | 141 | 6 tests: parsing, enrichment with fakes |
| `test/.../services/MetadataServiceTest.kt` | 104 | 4 tests: deduplication, directory copy |
| `test/.../services/MetadataServiceStaticTest.kt` | 108 | 4 tests: static export, symlink replacement |
| `test/.../util/ConfigFileHelperTest.kt` | 158 | 6 tests: config parse/write round-trip |
| `test/.../util/PathHelperTest.kt` | 154 | 8 tests: atomic symlink, tilde expansion |
| `test/.../testutil/FakeProcessRunner.kt` | 20 | Canned ProcessResult responses |
| `test/.../testutil/FakeAgentDetection.kt` | 15 | Configurable agent detection |

## Related Research

- `thoughts/shared/research/2026-02-23-full-codebase-research.md` — Full CLI codebase research

## Open Questions

1. `MetadataPattern.BAZEL_IDE_PATTERNS` is declared but `BazelService.refreshAllBazelMetadata()` references it correctly — this is resolved.
2. `OpenInTerminalAction` uses reflection to access `TerminalToolWindowManager.createLocalShellWidget()` with an empty catch block — behavior when the Terminal plugin is absent is silent fallback with the terminal window still activated.
3. `autoExportOnShutdown` defaults to `false` — safer default to avoid unexpected writes.
4. The `WtSettingsComponent` exposes 8 of 11 settings to the user; `debounceDelayMs`, `setupCompletedContexts`, and `lastWelcomeVersion` are internal-only.
