package com.block.wt.actions.worktree

import com.block.wt.actions.WtAction
import com.block.wt.provision.ProvisionHelper
import com.block.wt.git.GitBranchHelper
import com.block.wt.services.ContextService
import com.block.wt.services.CreateWorktreeUseCase
import com.block.wt.services.WorktreeService
import com.block.wt.ui.CreateWorktreeDialog
import com.block.wt.ui.Notifications
import com.intellij.openapi.actionSystem.AnActionEvent
import java.nio.file.Path

class CreateWorktreeAction : WtAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return

        val dialog = CreateWorktreeDialog(project)
        if (!dialog.showAndGet()) return

        val branchName = GitBranchHelper.sanitizeBranchName(dialog.branchName)
        val worktreePath = Path.of(dialog.worktreePath)
        val createNewBranch = dialog.createNewBranch

        runInBackground(project, "Creating Worktree") { indicator ->
            val worktreeService = WorktreeService.getInstance(project)
            val contextService = ContextService.getInstance()
            val config = contextService.getCurrentConfig()

            if (createNewBranch && config != null) {
                val useCase = CreateWorktreeUseCase(worktreeService, project)
                useCase.runCreateNewBranchFlow(
                    indicator, config.mainRepoRoot,
                    config.baseBranch, branchName, worktreePath, config,
                )
            } else {
                indicator.text = "Creating worktree..."
                val result = worktreeService.createWorktree(worktreePath, branchName, createNewBranch)

                result.fold(
                    onSuccess = {
                        if (config != null) {
                            ProvisionHelper.provisionWorktree(project, worktreePath, config, indicator = indicator)
                        }
                        worktreeService.refreshWorktreeList()
                        Notifications.info(project, "Worktree Created", "Created worktree at $worktreePath")
                    },
                    onFailure = {
                        Notifications.error(project, "Create Failed", it.message ?: "Unknown error")
                    }
                )
            }
        }
    }
}
