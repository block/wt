package com.block.wt.services

import com.block.wt.progress.ProgressScope
import com.block.wt.progress.asScope
import com.block.wt.ui.Notifications
import com.block.wt.util.PathHelper
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.application.ModalityState
import com.intellij.openapi.application.WriteAction
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.service
import com.intellij.openapi.fileEditor.FileDocumentManager
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.project.Project
import com.intellij.openapi.vcs.changes.VcsDirtyScopeManager
import com.intellij.openapi.vfs.VfsUtil
import com.intellij.openapi.vfs.VirtualFileManager
import git4idea.repo.GitRepositoryManager
import com.intellij.openapi.progress.runBlockingCancellable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.file.Path

@Service(Service.Level.PROJECT)
class SymlinkSwitchService(
    private val project: Project,
    private val cs: CoroutineScope,
) {
    fun switchWorktree(newTarget: Path) {
        ProgressManager.getInstance().run(object : Task.Backgroundable(
            project, "Switching Worktree", false
        ) {
            override fun run(indicator: ProgressIndicator) {
                indicator.isIndeterminate = false
                val scope = indicator.asScope()
                runBlockingCancellable { doSwitch(newTarget, indicator, scope) }
            }
        })
    }

    suspend fun doSwitch(
        newTarget: Path,
        indicator: ProgressIndicator? = null,
        scope: ProgressScope? = null,
    ) {
        val contextService = ContextService.getInstance()
        val config = contextService.getCurrentConfig()
            ?: throw IllegalStateException("No active wt context configured")

        val symlinkPath = config.activeWorktree
        val projectRoot = project.basePath?.let { VfsUtil.findFileByIoFile(java.io.File(it), true) }

        val app = ApplicationManager.getApplication()

        try {
            // Phase 1: Save documents (0%–10%)
            scope?.fraction(0.0)
            scope?.text("Saving documents...")
            indicator?.text = "Saving documents..."
            app.invokeAndWait({
                WriteAction.run<Nothing> {
                    FileDocumentManager.getInstance().saveAllDocuments()
                }
            }, ModalityState.defaultModalityState())

            // Phase 2: Atomic symlink swap (10%–20%)
            scope?.fraction(0.10)
            scope?.text("Swapping symlink...")
            indicator?.text = "Swapping symlink..."
            withContext(Dispatchers.IO) {
                PathHelper.atomicSetSymlink(symlinkPath, newTarget)
            }

            // Phase 3: Reload editors (20%–40%)
            scope?.fraction(0.20)
            scope?.text("Reloading editors...")
            indicator?.text = "Reloading editors..."
            app.invokeAndWait({
                WriteAction.run<Nothing> {
                    val fdm = FileDocumentManager.getInstance()
                    for (openFile in FileEditorManager.getInstance(project).openFiles) {
                        val doc = fdm.getCachedDocument(openFile) ?: continue
                        fdm.reloadFromDisk(doc)
                    }
                }
            }, ModalityState.defaultModalityState())

            // Phase 4: VFS refresh (40%–65%)
            scope?.fraction(0.40)
            scope?.text("Refreshing file system...")
            indicator?.text = "Refreshing file system..."
            if (projectRoot != null) {
                VfsUtil.markDirtyAndRefresh(false, true, true, projectRoot)
            }
            VirtualFileManager.getInstance().asyncRefresh {}

            // Phase 5: Git state (65%–85%)
            scope?.fraction(0.65)
            scope?.text("Updating git state...")
            indicator?.text = "Updating git state..."
            withContext(Dispatchers.IO) {
                val repos = GitRepositoryManager.getInstance(project).repositories
                for (repo in repos) {
                    repo.update()
                }
            }
            VcsDirtyScopeManager.getInstance(project).markEverythingDirty()

            // Phase 6: Refresh list (85%–100%)
            scope?.fraction(0.85)
            scope?.text("Refreshing worktree list...")
            indicator?.text = "Refreshing worktree list..."
            WorktreeService.getInstance(project).refreshWorktreeList()
            scope?.fraction(1.0)

            Notifications.info(
                project,
                "Worktree Switched",
                "Switched to ${newTarget.fileName}",
            )
        } catch (e: Exception) {
            Notifications.error(
                project,
                "Switch Failed",
                "Failed to switch worktree: ${e.message}",
            )
        }
    }

    companion object {
        fun getInstance(project: Project): SymlinkSwitchService = project.service()
    }
}
