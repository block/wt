package com.block.wt.actions.context

import com.block.wt.actions.WtAction
import com.block.wt.model.ContextConfig
import com.block.wt.services.ContextService
import com.block.wt.services.MetadataService
import com.block.wt.services.PointerUpdateMode
import com.block.wt.services.WorktreeService
import com.block.wt.ui.AddContextDialog
import com.block.wt.ui.Notifications
import com.block.wt.util.PathHelper
import com.intellij.openapi.actionSystem.AnActionEvent
import java.nio.file.Files

class AddContextAction : WtAction() {

    override fun isAvailable(e: AnActionEvent): Boolean = true

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project

        val dialog = AddContextDialog(project)
        if (!dialog.showAndGet()) return

        val repoPath = dialog.repoPath ?: return
        val contextName = dialog.contextName
        val baseBranch = dialog.baseBranch
        val activeWorktree = dialog.activeWorktree ?: return
        val mainRepoRoot = dialog.mainRepoRoot ?: return
        val worktreesBase = dialog.worktreesBase ?: return
        val ideaFilesBase = dialog.ideaFilesBase ?: return
        val patterns = dialog.selectedPatterns

        runInBackground(project ?: return, "Creating Context", cancellable = false) { indicator ->
            try {
                indicator.text = "Creating directories..."
                Files.createDirectories(worktreesBase)
                Files.createDirectories(ideaFilesBase)

                // Migration: move repo to mainRepoRoot, create symlink at activeWorktree
                // Matches shell's _wt_migrate_repo()
                if (PathHelper.isSymlink(activeWorktree)) {
                    // Already a symlink — previously set up, skip migration
                } else if (Files.isDirectory(activeWorktree)) {
                    if (Files.exists(mainRepoRoot)) {
                        error("${mainRepoRoot} already exists; cannot migrate")
                    }
                    Files.createDirectories(mainRepoRoot.parent)

                    // Use temp dir for safety (handles nested paths like ~/java -> ~/java/.wt/...)
                    val tempDir = activeWorktree.resolveSibling(
                        ".${activeWorktree.fileName}.wt-migrate-${System.currentTimeMillis()}"
                    )
                    indicator.text = "Moving repository to temp location..."
                    Files.move(activeWorktree, tempDir)

                    indicator.text = "Moving to ${mainRepoRoot}..."
                    Files.move(tempDir, mainRepoRoot)

                    indicator.text = "Creating symlink..."
                    Files.createSymbolicLink(activeWorktree, mainRepoRoot)

                    // Update pre-existing worktree .git pointers to use the physical base path
                    // Only update unadopted worktrees — adopted ones already have correct physical paths
                    ContextService.getInstance(project).updateWorktreePointers(mainRepoRoot, PointerUpdateMode.UNADOPTED_ONLY)
                } else if (!Files.exists(activeWorktree)) {
                    // Neither exists — create symlink if mainRepoRoot exists
                    if (Files.isDirectory(mainRepoRoot)) {
                        Files.createSymbolicLink(activeWorktree, mainRepoRoot)
                    }
                }

                indicator.text = "Writing configuration..."
                val config = ContextConfig(
                    name = contextName,
                    mainRepoRoot = mainRepoRoot,
                    worktreesBase = worktreesBase,
                    activeWorktree = activeWorktree,
                    ideaFilesBase = ideaFilesBase,
                    baseBranch = baseBranch,
                    metadataPatterns = patterns,
                )
                ContextService.getInstance(project).addContext(config)

                if (patterns.isNotEmpty()) {
                    indicator.text = "Exporting metadata..."
                    MetadataService.exportMetadataStatic(mainRepoRoot, ideaFilesBase, patterns)
                        .onFailure { ex ->
                            Notifications.warning(project, "Metadata Export Failed", ex.message ?: "Unknown error")
                        }
                }

                WorktreeService.getInstance(project).refreshWorktreeList()
                Notifications.info(project, "Context Created", "Context '$contextName' created")
            } catch (ex: Exception) {
                Notifications.error(project, "Context Creation Failed", ex.message ?: "Unknown error")
            }
        }
    }
}
