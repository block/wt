package com.block.wt.services

import com.block.wt.progress.ProgressScope
import com.block.wt.progress.asScope
import com.block.wt.ui.Notifications
import com.block.wt.util.PathHelper
import com.intellij.codeInsight.daemon.DaemonCodeAnalyzer
import com.intellij.ide.projectView.ProjectView
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
import com.intellij.openapi.roots.ex.ProjectRootManagerEx
import com.intellij.openapi.vcs.ProjectLevelVcsManager
import com.intellij.openapi.vcs.changes.VcsDirtyScopeManager
import com.intellij.openapi.vfs.LocalFileSystem
import com.intellij.openapi.vfs.VfsUtil
import com.intellij.psi.PsiDocumentManager
import com.intellij.psi.PsiManager
import com.intellij.ui.EditorNotifications
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
        val contextService = ContextService.getInstance(project)
        val config = contextService.getCurrentConfig()
        if (config == null) {
            Notifications.error(project, "No Context", "No active wt context detected for this project")
            return
        }

        val symlinkPath = config.activeWorktree

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

            // Phase 3: VFS refresh (20%–45%)
            // Poke VFS at all relevant paths so it re-reads the symlink entry and rescans the new target tree
            scope?.fraction(0.20)
            scope?.text("Refreshing file system...")
            indicator?.text = "Refreshing file system..."
            val localFileSystem = LocalFileSystem.getInstance()
            val refreshPaths = buildRefreshPaths(symlinkPath, newTarget, config.mainRepoRoot)
            withContext(Dispatchers.IO) {
                localFileSystem.refreshNioFiles(refreshPaths, false, true, null)
            }
            val projectRoot = localFileSystem.refreshAndFindFileByNioFile(symlinkPath)
                ?: project.basePath?.let { localFileSystem.refreshAndFindFileByNioFile(Path.of(it)) }
            if (projectRoot != null) {
                VfsUtil.markDirtyAndRefresh(false, true, true, projectRoot)
                // Refresh .git so git4idea reads the new gitdir pointer in Phase 5
                projectRoot.findChild(".git")?.let { VfsUtil.markDirtyAndRefresh(false, true, true, it) }
            }

            // Phase 4: Reload editors and project state (45%–65%)
            // Propagate VFS changes into documents, PSI, Project View, and daemon
            scope?.fraction(0.45)
            scope?.text("Reloading editors and project state...")
            indicator?.text = "Reloading editors and project state..."
            app.invokeAndWait({
                val fdm = FileDocumentManager.getInstance()
                val psiDocManager = PsiDocumentManager.getInstance(project)
                val psiManager = PsiManager.getInstance(project)
                val openFiles = FileEditorManager.getInstance(project).openFiles

                WriteAction.run<Nothing> {
                    for (openFile in openFiles) {
                        openFile.refresh(false, false)
                    }
                    for (openFile in openFiles) {
                        val doc = fdm.getCachedDocument(openFile) ?: continue
                        fdm.reloadFromDisk(doc)
                        psiDocManager.getCachedPsiFile(doc)?.let(psiManager::reloadFromDisk)
                    }
                }

                psiDocManager.commitAllDocuments()
                if (openFiles.isNotEmpty()) {
                    psiDocManager.reparseFiles(openFiles.toList(), true)
                }
                psiManager.dropPsiCaches()

                // Fire synthetic roots-changed event so indexer and module system see the new tree
                WriteAction.run<Nothing> {
                    ProjectRootManagerEx.getInstanceEx(project).makeRootsChange({}, false, true)
                }

                ProjectView.getInstance(project).refresh()
                EditorNotifications.getInstance(project).updateAllNotifications()
                DaemonCodeAnalyzer.getInstance(project).restart("wt symlink switch")
            }, ModalityState.defaultModalityState())

            // Phase 5: Git state (65%–85%)
            // Re-set VCS mappings to force git4idea to re-read the .git file's new gitdir pointer
            scope?.fraction(0.65)
            scope?.text("Updating git state...")
            indicator?.text = "Updating git state..."
            app.invokeAndWait({
                val vcsManager = ProjectLevelVcsManager.getInstance(project)
                vcsManager.setDirectoryMappings(vcsManager.directoryMappings.toList())
            }, ModalityState.defaultModalityState())
            withContext(Dispatchers.IO) {
                val repos = GitRepositoryManager.getInstance(project).repositories
                for (repo in repos) {
                    repo.update()
                }
            }
            VcsDirtyScopeManager.getInstance(project).markEverythingDirty()
            projectRoot?.let { VcsDirtyScopeManager.getInstance(project).rootDirty(it) }

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

    private fun buildRefreshPaths(
        symlinkPath: Path,
        newTarget: Path,
        mainRepoRoot: Path?,
    ): Set<Path> = buildSet {
        add(symlinkPath)
        add(symlinkPath.resolve(".git"))
        add(newTarget)
        add(newTarget.resolve(".git"))
        project.basePath?.let { basePath ->
            add(Path.of(basePath))
            add(Path.of(basePath).resolve(".git"))
        }
        mainRepoRoot?.let {
            add(it)
            add(it.resolve(".git"))
        }
    }

    companion object {
        fun getInstance(project: Project): SymlinkSwitchService = project.service()
    }
}
