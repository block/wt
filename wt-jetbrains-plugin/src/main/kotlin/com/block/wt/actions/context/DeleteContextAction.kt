package com.block.wt.actions.context

import com.block.wt.actions.WtConfigAction
import com.block.wt.services.ContextService
import com.block.wt.ui.Notifications
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.ui.Messages

class DeleteContextAction : WtConfigAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val config = requireConfig(e) ?: return

        val answer = Messages.showYesNoDialog(
            project,
            "Remove context '${config.name}'?\n\n" +
                "Main repo: ${config.mainRepoRoot}\n" +
                "This will remove wt config, restore the repository to its original location, " +
                "and clean up all context files.\n\n" +
                "Existing worktree directories will be kept.",
            "Remove Context",
            Messages.getWarningIcon(),
        )
        if (answer != Messages.YES) return

        runInBackground(project, "Removing Context") {
            try {
                ContextService.getInstance(project).removeContext(config)
                Notifications.info(project, "Context Removed", "Context '${config.name}' has been removed")
            } catch (ex: Exception) {
                Notifications.error(project, "Remove Failed", ex.message ?: "Unknown error")
            }
        }
    }
}
