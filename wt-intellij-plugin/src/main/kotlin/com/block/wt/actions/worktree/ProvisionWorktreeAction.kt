package com.block.wt.actions.worktree

import com.block.wt.actions.WtTableAction
import com.block.wt.progress.asScope
import com.block.wt.provision.ProvisionHelper
import com.block.wt.services.ContextService
import com.block.wt.services.WorktreeService
import com.block.wt.ui.Notifications
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.progress.runBlockingCancellable

class ProvisionWorktreeAction : WtTableAction() {

    override fun update(e: AnActionEvent) {
        val project = e.project
        val wt = getSelectedPanel(e)?.getSelectedWorktree()

        if (project == null || wt == null) {
            e.presentation.isEnabledAndVisible = false
            return
        }

        e.presentation.isEnabled = !wt.isProvisionedByCurrentContext
        e.presentation.isVisible = true
    }

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val wt = getSelectedPanel(e)?.getSelectedWorktree() ?: return

        val config = ContextService.getInstance(project).getCurrentConfig()
        val currentContextName = config?.name

        if (currentContextName == null) {
            Notifications.error(project, "No Context", "No wt context is configured. Add a context first.")
            return
        }

        if (wt.isProvisionedByCurrentContext) {
            Notifications.info(project, "Already Provisioned", "This worktree is already provisioned by '$currentContextName'")
            return
        }

        ProgressManager.getInstance().run(object : Task.Backgroundable(
            project, "Provisioning Worktree", true
        ) {
            override fun run(indicator: com.intellij.openapi.progress.ProgressIndicator) {
                indicator.isIndeterminate = false
                runBlockingCancellable {
                    ProvisionHelper.provisionWorktree(project, wt.path, config, scope = indicator.asScope())
                    WorktreeService.getInstance(project).refreshWorktreeList()
                    Notifications.info(project, "Worktree Provisioned", "Provisioned ${wt.displayName} for context '$currentContextName'")
                }
            }
        })
    }
}
