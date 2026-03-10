package com.block.wt.actions.context

import com.block.wt.actions.WtConfigAction
import com.block.wt.git.GitConfigHelper
import com.block.wt.services.ContextService
import com.block.wt.ui.Notifications
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
                "The symlink at ${config.activeWorktree} will be removed.\n" +
                "You may need to move the repo back manually.\n\n" +
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

                indicator.text = "Removing symlink..."
                if (PathHelper.isSymlink(config.activeWorktree)) {
                    Files.delete(config.activeWorktree)
                }

                ContextService.getInstance(project).reload()
                Notifications.info(project, "Context Deleted", "Context '${config.name}' deleted")
            } catch (ex: Exception) {
                Notifications.error(project, "Delete Failed", ex.message ?: "Unknown error")
            }
        }
    }
}
