package com.block.wt.services

import com.block.wt.provision.ProvisionHelper
import com.block.wt.model.ContextConfig
import com.block.wt.ui.Notifications
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.project.Project
import java.nio.file.Path

class CreateWorktreeUseCase(
    private val worktreeService: WorktreeService,
    private val project: Project,
) {
    suspend fun runCreateNewBranchFlow(
        indicator: ProgressIndicator,
        mainRepoRoot: Path,
        baseBranch: String,
        branchName: String,
        worktreePath: Path,
        config: ContextConfig,
    ) {
        val stashName = "wta-${System.currentTimeMillis()}-${ProcessHandle.current().pid()}"

        val origBranch = worktreeService.getCurrentBranch(mainRepoRoot)
            ?: worktreeService.getCurrentRevision(mainRepoRoot)
            ?: "HEAD"

        try {
            indicator.checkCanceled()
            indicator.text = "Stashing uncommitted changes..."
            if (worktreeService.hasUncommittedChanges(mainRepoRoot)) {
                worktreeService.stashSave(mainRepoRoot, stashName)
            }

            indicator.checkCanceled()
            indicator.text = "Checking out $baseBranch..."
            worktreeService.checkout(mainRepoRoot, baseBranch)

            indicator.checkCanceled()
            indicator.text = "Pulling latest changes..."
            worktreeService.pullFfOnly(mainRepoRoot)

            indicator.checkCanceled()
            indicator.text = "Creating worktree..."
            val result = worktreeService.createWorktree(worktreePath, branchName, createNewBranch = true)
            result.getOrThrow()

            indicator.checkCanceled()
            ProvisionHelper.provisionWorktree(project, worktreePath, config, indicator = indicator)

            worktreeService.refreshWorktreeList()
            Notifications.info(project, "Worktree Created", "Created worktree '$branchName' at $worktreePath")
        } catch (e: Exception) {
            Notifications.error(project, "Create Failed", e.message ?: "Unknown error")
        } finally {
            indicator.text = "Restoring original state..."
            val checkoutOk = runCatching { worktreeService.checkout(mainRepoRoot, origBranch) }.isSuccess
            if (checkoutOk) {
                runCatching { worktreeService.stashPop(mainRepoRoot, stashName) }
            }
        }
    }
}
