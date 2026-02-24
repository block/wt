package com.block.wt.actions.context

import com.block.wt.actions.WtAction
import com.block.wt.model.ContextConfig
import com.block.wt.services.ContextService
import com.block.wt.services.MetadataService
import com.block.wt.services.WorktreeService
import com.block.wt.ui.AddContextDialog
import com.block.wt.ui.Notifications
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
        val worktreesBase = dialog.worktreesBase ?: return
        val ideaFilesBase = dialog.ideaFilesBase ?: return
        val patterns = dialog.selectedPatterns

        runInBackground(project ?: return, "Creating Context", cancellable = false) { indicator ->
            try {
                indicator.text = "Creating directories..."
                Files.createDirectories(worktreesBase)
                Files.createDirectories(ideaFilesBase)
                Files.createDirectories(activeWorktree.parent)

                if (!Files.exists(activeWorktree) && Files.isDirectory(repoPath)) {
                    indicator.text = "Creating symlink..."
                    Files.createSymbolicLink(activeWorktree, repoPath)
                }

                indicator.text = "Writing configuration..."
                val config = ContextConfig(
                    name = contextName,
                    mainRepoRoot = repoPath,
                    worktreesBase = worktreesBase,
                    activeWorktree = activeWorktree,
                    ideaFilesBase = ideaFilesBase,
                    baseBranch = baseBranch,
                    metadataPatterns = patterns,
                )
                ContextService.getInstance().addContext(config)
                ContextService.getInstance().switchContext(contextName)

                if (patterns.isNotEmpty()) {
                    indicator.text = "Exporting metadata..."
                    MetadataService.exportMetadataStatic(repoPath, ideaFilesBase, patterns)
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
