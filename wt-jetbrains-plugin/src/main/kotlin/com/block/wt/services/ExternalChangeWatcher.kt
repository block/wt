package com.block.wt.services

import com.block.wt.model.ContextConfig
import com.block.wt.settings.WtPluginSettings
import com.block.wt.util.PathHelper
import com.intellij.openapi.Disposable
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.service
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.nio.file.FileSystems
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardWatchEventKinds
import java.nio.file.WatchService

@Service(Service.Level.PROJECT)
class ExternalChangeWatcher(
    private val project: Project,
    private val cs: CoroutineScope,
) : Disposable {
    private val log = Logger.getInstance(ExternalChangeWatcher::class.java)
    private var watchService: WatchService? = null
    private var watchJob: Job? = null
    private var debounceJob: Job? = null
    private var lastWatchState: WatchState = WatchState.EMPTY

    fun startWatching() {
        stopWatching()

        watchJob = cs.launch(Dispatchers.IO) {
            try {
                val ws = FileSystems.getDefault().newWatchService()
                watchService = ws

                val pathsToWatch = mutableListOf<Path>()

                // Watch ~/.wt/ for `current` file changes (shell context switch)
                val wtRoot = PathHelper.wtRoot
                if (Files.isDirectory(wtRoot)) {
                    wtRoot.register(
                        ws,
                        StandardWatchEventKinds.ENTRY_MODIFY,
                        StandardWatchEventKinds.ENTRY_CREATE,
                    )
                    pathsToWatch.add(wtRoot)
                }

                // Watch ~/.wt/repos/ for .conf file changes (NIO watches are not recursive)
                val reposDir = PathHelper.reposDir
                if (Files.isDirectory(reposDir)) {
                    reposDir.register(
                        ws,
                        StandardWatchEventKinds.ENTRY_MODIFY,
                        StandardWatchEventKinds.ENTRY_CREATE,
                    )
                    pathsToWatch.add(reposDir)
                }

                // Watch the symlink's parent directory for symlink changes
                val config = ContextService.getInstance(project).getCurrentConfig()
                val symlinkParent = config?.activeWorktree?.parent
                if (symlinkParent != null && Files.isDirectory(symlinkParent)) {
                    symlinkParent.register(
                        ws,
                        StandardWatchEventKinds.ENTRY_MODIFY,
                        StandardWatchEventKinds.ENTRY_CREATE,
                    )
                    pathsToWatch.add(symlinkParent)
                }

                // Watch .git/worktrees/ for new/deleted linked worktrees
                val mainRepoRoot = config?.mainRepoRoot
                val gitWorktreesDir = mainRepoRoot?.resolve(".git/worktrees")
                if (gitWorktreesDir != null && Files.isDirectory(gitWorktreesDir)) {
                    gitWorktreesDir.register(
                        ws,
                        StandardWatchEventKinds.ENTRY_CREATE,
                        StandardWatchEventKinds.ENTRY_DELETE,
                    )
                    pathsToWatch.add(gitWorktreesDir)
                }

                // Watch .git/ for config file changes (external git config edits to wt.* keys)
                val gitDir = mainRepoRoot?.resolve(".git")
                if (gitDir != null && Files.isDirectory(gitDir)) {
                    gitDir.register(
                        ws,
                        StandardWatchEventKinds.ENTRY_MODIFY,
                    )
                    pathsToWatch.add(gitDir)
                }

                lastWatchState = buildWatchState(config, pathsToWatch.toSet())
                log.info("Watching for external changes: $pathsToWatch")

                // Note: `config` is intentionally captured once per watch session. Context-changing
                // events always go through `.git/config` or `~/.wt/current` writes, which are detected
                // without referencing `config`. When state changes, `debouncedRefresh()` detects the
                // WatchState mismatch and re-registers watches with the updated config.
                while (true) {
                    val key = ws.take()
                    var relevant = false

                    val watchedPath = key.watchable() as? Path

                    for (event in key.pollEvents()) {
                        val context = event.context() as? Path ?: continue
                        val fileName = context.fileName?.toString() ?: continue

                        if (isRelevantEvent(fileName, watchedPath, config)) {
                            relevant = true
                        }
                    }

                    if (!key.reset()) {
                        log.info("Watch key invalidated for ${key.watchable()}, re-registering watches")
                        startWatching()
                        return@launch
                    }

                    if (relevant) {
                        debouncedRefresh()
                    }
                }
            } catch (_: java.nio.file.ClosedWatchServiceException) {
                // Normal shutdown
            } catch (e: Exception) {
                log.warn("File watcher error", e)
            }
        }
    }

    private fun debouncedRefresh() {
        debounceJob?.cancel()
        debounceJob = cs.launch {
            delay(WtPluginSettings.getInstance().state.debounceDelayMs)
            log.info("External change detected, refreshing")
            ContextService.getInstance(project).reload()
            WorktreeService.getInstance(project).refreshWorktreeList()

            // Re-register watches if context-derived state changed
            val config = ContextService.getInstance(project).getCurrentConfig()
            val currentState = buildWatchState(config)
            if (currentState != lastWatchState) {
                log.info("Watch state changed, re-registering watches")
                startWatching()
            }
        }
    }

    fun stopWatching() {
        watchJob?.cancel()
        watchJob = null
        debounceJob?.cancel()
        debounceJob = null
        runCatching { watchService?.close() }
        watchService = null
    }

    override fun dispose() {
        stopWatching()
    }

    /**
     * Immutable snapshot of the state that determines which paths we watch and which
     * events we filter. When any field changes, watches must be re-registered.
     */
    data class WatchState(
        val paths: Set<Path>,
        val activeWorktreeFileName: String?,
    ) {
        companion object {
            val EMPTY = WatchState(emptySet(), null)
        }
    }

    companion object {
        fun getInstance(project: Project): ExternalChangeWatcher = project.service()

        /**
         * Determines whether a file-system event is relevant to the wt plugin.
         * Pure function — extracted for testability.
         *
         * @param fileName the name of the changed file (event context)
         * @param watchedPath the directory that emitted the event
         * @param config the current context config (may be null)
         */
        internal fun isRelevantEvent(
            fileName: String,
            watchedPath: Path?,
            config: ContextConfig?,
        ): Boolean {
            // .conf file changes in ~/.wt/repos/ (scoped to reposDir to avoid spurious matches in .git/)
            if (fileName.endsWith(".conf") && watchedPath == PathHelper.reposDir) return true

            // ~/.wt/current changed — shell context switch
            if (fileName == "current" && watchedPath == PathHelper.wtRoot) return true

            // Active worktree symlink changed (scoped to its parent directory)
            if (fileName == config?.activeWorktree?.fileName?.toString()
                && watchedPath == config.activeWorktree.parent) return true

            // .git/worktrees/ changes — worktree created/removed
            val gitWorktreesDir = config?.mainRepoRoot?.resolve(".git/worktrees")
            if (watchedPath != null && gitWorktreesDir != null && watchedPath == gitWorktreesDir) {
                return true
            }

            // .git/config modified — may contain wt.* key changes
            val gitDir = config?.mainRepoRoot?.resolve(".git")
            if (watchedPath != null && gitDir != null && watchedPath == gitDir && fileName == "config") {
                return true
            }

            return false
        }

        /**
         * Builds the watch state from the current config.
         * When called from debouncedRefresh(), applies the same existence guards
         * used by startWatching() so the path sets are comparable.
         */
        internal fun buildWatchState(
            config: ContextConfig?,
            existingPaths: Set<Path>? = null,
        ): WatchState {
            val paths = existingPaths ?: buildSet {
                if (Files.isDirectory(PathHelper.wtRoot)) add(PathHelper.wtRoot)
                if (Files.isDirectory(PathHelper.reposDir)) add(PathHelper.reposDir)
                config?.activeWorktree?.parent?.let { if (Files.isDirectory(it)) add(it) }
                config?.mainRepoRoot?.resolve(".git/worktrees")?.let { if (Files.isDirectory(it)) add(it) }
                config?.mainRepoRoot?.resolve(".git")?.let { if (Files.isDirectory(it)) add(it) }
            }
            return WatchState(
                paths = paths,
                activeWorktreeFileName = config?.activeWorktree?.fileName?.toString(),
            )
        }
    }
}
