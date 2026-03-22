package com.block.wt.actions.context

import com.block.wt.actions.WtConfigAction
import com.block.wt.git.GitConfigHelper
import com.block.wt.services.ContextService
import com.block.wt.services.MetadataService
import com.block.wt.services.WorktreeService
import com.block.wt.ui.AddContextDialog
import com.block.wt.ui.Notifications
import com.block.wt.util.PathHelper
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.ui.Messages
import java.nio.file.Files

class ReprovisionContextAction : WtConfigAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val config = requireConfig(e) ?: return
        val project = e.project ?: return

        val answer = Messages.showYesNoDialog(
            project,
            "This will remove the current wt configuration for '${config.name}' and let you re-create it.\n" +
                "Existing worktree directories will be kept.\n\n" +
                "Continue?",
            "Re-adopt Context",
            Messages.getQuestionIcon(),
        )
        if (answer != Messages.YES) return

        runInBackground(project, "Re-adopting Context", cancellable = false) { indicator ->
            try {
                indicator.text = "Removing git config..."
                GitConfigHelper.removeAllConfig(config.mainRepoRoot)

                indicator.text = "Removing .conf file..."
                val confFile = PathHelper.reposDir.resolve("${config.name}.conf")
                Files.deleteIfExists(confFile)

                indicator.text = "Removing symlink..."
                if (PathHelper.isSymlink(config.activeWorktree)) {
                    Files.delete(config.activeWorktree)
                }

                ContextService.getInstance(project).reload()
            } catch (ex: Exception) {
                Notifications.error(project, "Re-adopt Failed", ex.message ?: "Unknown error")
                return@runInBackground
            }

            // Open AddContextDialog on EDT for the user to re-create
            com.intellij.openapi.application.ApplicationManager.getApplication().invokeLater {
                val dialog = AddContextDialog(project)
                if (!dialog.showAndGet()) return@invokeLater

                val repoPath = dialog.repoPath ?: return@invokeLater
                val contextName = dialog.contextName
                val baseBranch = dialog.baseBranch
                val activeWorktree = dialog.activeWorktree ?: return@invokeLater
                val mainRepoRoot = dialog.mainRepoRoot ?: return@invokeLater
                val worktreesBase = dialog.worktreesBase ?: return@invokeLater
                val ideaFilesBase = dialog.ideaFilesBase ?: return@invokeLater
                val patterns = dialog.selectedPatterns

                runInBackground(project, "Creating Context", cancellable = false) { indicator2 ->
                    try {
                        indicator2.text = "Creating directories..."
                        Files.createDirectories(worktreesBase)
                        Files.createDirectories(ideaFilesBase)

                        // Migration logic (same as AddContextAction)
                        if (PathHelper.isSymlink(activeWorktree)) {
                            // Already a symlink — skip
                        } else if (Files.isDirectory(activeWorktree)) {
                            if (Files.exists(mainRepoRoot)) {
                                error("${mainRepoRoot} already exists; cannot migrate")
                            }
                            Files.createDirectories(mainRepoRoot.parent)
                            val tempDir = activeWorktree.resolveSibling(
                                ".${activeWorktree.fileName}.wt-migrate-${System.currentTimeMillis()}"
                            )
                            indicator2.text = "Moving repository to temp location..."
                            Files.move(activeWorktree, tempDir)
                            indicator2.text = "Moving to ${mainRepoRoot}..."
                            Files.move(tempDir, mainRepoRoot)
                            indicator2.text = "Creating symlink..."
                            Files.createSymbolicLink(activeWorktree, mainRepoRoot)
                        } else if (!Files.exists(activeWorktree)) {
                            if (Files.isDirectory(mainRepoRoot)) {
                                Files.createSymbolicLink(activeWorktree, mainRepoRoot)
                            }
                        }

                        indicator2.text = "Writing configuration..."
                        val newConfig = com.block.wt.model.ContextConfig(
                            name = contextName,
                            mainRepoRoot = mainRepoRoot,
                            worktreesBase = worktreesBase,
                            activeWorktree = activeWorktree,
                            ideaFilesBase = ideaFilesBase,
                            baseBranch = baseBranch,
                            metadataPatterns = patterns,
                        )
                        ContextService.getInstance(project).addContext(newConfig)

                        if (patterns.isNotEmpty()) {
                            indicator2.text = "Exporting metadata..."
                            MetadataService.exportMetadataStatic(mainRepoRoot, ideaFilesBase, patterns)
                                .onFailure { ex ->
                                    Notifications.warning(project, "Metadata Export Failed", ex.message ?: "Unknown error")
                                }
                        }

                        WorktreeService.getInstance(project).refreshWorktreeList()
                        Notifications.info(project, "Context Re-adopted", "Context '$contextName' re-adopted")
                    } catch (ex: Exception) {
                        Notifications.error(project, "Context Creation Failed", ex.message ?: "Unknown error")
                    }
                }
            }
        }
    }
}
