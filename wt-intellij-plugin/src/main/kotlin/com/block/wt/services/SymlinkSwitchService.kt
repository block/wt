package com.block.wt.services

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
                runBlockingCancellable { doSwitch(newTarget, indicator) }
            }
        })
    }

    suspend fun doSwitch(newTarget: Path, indicator: ProgressIndicator? = null) {
        val contextService = ContextService.getInstance()
        val config = contextService.getCurrentConfig()
            ?: throw IllegalStateException("No active wt context configured")

        val symlinkPath = config.activeWorktree
        val projectRoot = project.basePath?.let { VfsUtil.findFileByIoFile(java.io.File(it), false) }
            ?: throw IllegalStateException("Cannot determine project root")

        val app = ApplicationManager.getApplication()

        try {
            // Phase 1: Pre-swap — save all documents inside a write-safe context
            indicator?.text = "Saving documents..."
            app.invokeAndWait({
                WriteAction.run<Nothing> {
                    FileDocumentManager.getInstance().saveAllDocuments()
                }
            }, ModalityState.defaultModalityState())

            // Phase 2: Atomic symlink swap
            indicator?.text = "Swapping symlink..."
            withContext(Dispatchers.IO) {
                PathHelper.atomicSetSymlink(symlinkPath, newTarget)
            }

            // Phase 3: Suppress file cache conflict dialogs — reload open docs
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

            // Phase 4: Full VFS refresh
            indicator?.text = "Refreshing file system..."
            VfsUtil.markDirtyAndRefresh(false, true, true, projectRoot)
            VirtualFileManager.getInstance().asyncRefresh {}

            // Phase 5: Git state refresh — repo.update() asserts background thread
            indicator?.text = "Updating git state..."
            withContext(Dispatchers.IO) {
                val repos = GitRepositoryManager.getInstance(project).repositories
                for (repo in repos) {
                    repo.update()
                }
            }
            VcsDirtyScopeManager.getInstance(project).markEverythingDirty()

            // Update tool window
            WorktreeService.getInstance(project).refreshWorktreeList()

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
