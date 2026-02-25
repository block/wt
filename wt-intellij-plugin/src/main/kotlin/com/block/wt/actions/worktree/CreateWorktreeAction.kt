package com.block.wt.actions.worktree

import com.block.wt.actions.WtAction
import com.block.wt.progress.asScope
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
                indicator.isIndeterminate = false
                val scope = indicator.asScope()

                // Step 1: Create worktree (0%–85%) — no progress signal
                scope.fraction(0.0)
                scope.text("Creating worktree...")
                val result = worktreeService.createWorktree(
                    worktreePath, branchName, createNewBranch,
                )

                result.fold(
                    onSuccess = {
                        // Step 2: Provision (85%–95%)
                        scope.fraction(0.85)
                        if (config != null) {
                            ProvisionHelper.provisionWorktree(
                                project, worktreePath, config,
                                scope = scope.sub(0.85, 0.10),
                            )
                        }
                        // Step 3: Refresh (95%–100%)
                        scope.fraction(0.95)
                        scope.text("Refreshing worktree list...")
                        scope.text2("")
                        worktreeService.refreshWorktreeList()
                        scope.fraction(1.0)
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
