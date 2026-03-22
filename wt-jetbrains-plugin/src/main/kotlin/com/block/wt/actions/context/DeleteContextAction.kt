package com.block.wt.actions.context

import com.block.wt.actions.WtConfigAction
import com.block.wt.git.GitConfigHelper
import com.block.wt.services.ContextService
import com.block.wt.ui.Notifications
import com.block.wt.util.ConfigFileHelper
import com.block.wt.util.PathHelper
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.ui.Messages
import java.nio.file.Files

class DeleteContextAction : WtConfigAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val config = requireConfig(e) ?: return
        val project = e.project ?: return

        val answer = Messages.showYesNoDialog(
            project,
            "Delete context '${config.name}'?\n\n" +
                "Your repository lives at ${config.mainRepoRoot}.\n" +
                "It will be moved back to ${config.activeWorktree}.\n\n" +
                "Existing worktree directories will be kept.",
            "Delete Context",
            Messages.getWarningIcon(),
        )
        if (answer != Messages.YES) return

        runInBackground(project, "Deleting Context", cancellable = false) { indicator ->
            try {
                indicator.text = "Removing git config..."
                GitConfigHelper.removeAllConfig(config.mainRepoRoot)

                indicator.text = "Removing .conf file..."
                val confFile = PathHelper.reposDir.resolve("${config.name}.conf")
                Files.deleteIfExists(confFile)

                // Reverse repo migration: move main repo back to symlink location
                indicator.text = "Restoring repository to original location..."
                val activeWorktree = config.activeWorktree
                val mainRepoRoot = config.mainRepoRoot

                if (PathHelper.isSymlink(activeWorktree)) {
                    val linkTarget = PathHelper.readSymlink(activeWorktree)
                    val resolvedTarget = if (linkTarget != null) {
                        if (linkTarget.isAbsolute) linkTarget
                        else activeWorktree.parent.resolve(linkTarget)
                    } else null

                    val resolvedRepo = PathHelper.normalizeSafe(mainRepoRoot)
                    val resolvedLink = if (resolvedTarget != null) PathHelper.normalizeSafe(resolvedTarget) else null

                    if (resolvedLink != null && resolvedLink == resolvedRepo) {
                        // Symlink points to main repo — reverse the migration
                        Files.delete(activeWorktree)
                        Files.move(mainRepoRoot, activeWorktree)
                    } else {
                        // Symlink points elsewhere — just remove it
                        Files.delete(activeWorktree)
                    }
                } else if (Files.exists(activeWorktree)) {
                    // Not a symlink — leave it alone
                    Notifications.warning(project, "Context Delete",
                        "${activeWorktree.fileName} is not a symlink — repository not moved")
                }

                ContextService.getInstance(project).reload()

                val currentName = ConfigFileHelper.readCurrentContext()
                if (currentName == config.name) {
                    val remaining = ContextService.getInstance(project).contexts.value
                    if (remaining.isNotEmpty()) {
                        ConfigFileHelper.writeCurrentContext(remaining.first().name)
                    } else {
                        Files.deleteIfExists(PathHelper.currentFile)
                    }
                }

                Notifications.info(project, "Context Deleted", "Context '${config.name}' deleted")
            } catch (ex: Exception) {
                Notifications.error(project, "Delete Failed", ex.message ?: "Unknown error")
            }
        }
    }
}
