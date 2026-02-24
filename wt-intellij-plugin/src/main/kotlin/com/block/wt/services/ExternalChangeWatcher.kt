package com.block.wt.services

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
    private var lastContextName: String? = null

    fun startWatching() {
        stopWatching()

        lastContextName = ContextService.getInstance().getCurrentConfig()?.name

        watchJob = cs.launch(Dispatchers.IO) {
            try {
                val ws = FileSystems.getDefault().newWatchService()
                watchService = ws

                val pathsToWatch = mutableListOf<Path>()

                // Watch ~/.wt/ for context changes
                val wtRoot = PathHelper.wtRoot
                if (java.nio.file.Files.isDirectory(wtRoot)) {
                    wtRoot.register(
                        ws,
                        StandardWatchEventKinds.ENTRY_MODIFY,
                        StandardWatchEventKinds.ENTRY_CREATE,
                    )
                    pathsToWatch.add(wtRoot)
                }

                // Watch the symlink's parent directory for symlink changes
                val config = ContextService.getInstance().getCurrentConfig()
                val symlinkParent = config?.activeWorktree?.parent
                if (symlinkParent != null && java.nio.file.Files.isDirectory(symlinkParent)) {
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
                if (gitWorktreesDir != null && java.nio.file.Files.isDirectory(gitWorktreesDir)) {
                    gitWorktreesDir.register(
                        ws,
                        StandardWatchEventKinds.ENTRY_CREATE,
                        StandardWatchEventKinds.ENTRY_DELETE,
                    )
                    pathsToWatch.add(gitWorktreesDir)
                }

                log.info("Watching for external changes: $pathsToWatch")

                while (true) {
                    val key = ws.take()
                    var relevant = false

                    val watchedPath = key.watchable() as? Path

                    for (event in key.pollEvents()) {
                        val context = event.context() as? Path ?: continue
                        val fileName = context.fileName?.toString() ?: continue

                        if (fileName == "current" || fileName.endsWith(".conf") ||
                            fileName == config?.activeWorktree?.fileName?.toString()
                        ) {
                            relevant = true
                        }

                        // Any change in .git/worktrees/ means a worktree was created/removed
                        if (watchedPath != null && gitWorktreesDir != null &&
                            watchedPath == gitWorktreesDir
                        ) {
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
            ContextService.getInstance().reload()
            WorktreeService.getInstance(project).refreshWorktreeList()

            // Re-register watches if the context changed (different watched paths)
            val currentContextName = ContextService.getInstance().getCurrentConfig()?.name
            if (currentContextName != lastContextName) {
                log.info("Context changed from '$lastContextName' to '$currentContextName', re-registering watches")
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

    companion object {
        fun getInstance(project: Project): ExternalChangeWatcher = project.service()
    }
}
