package com.block.wt.services

import com.block.wt.progress.asScope
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
        val scope = indicator.asScope()
        val stashName = "wta-${System.currentTimeMillis()}-${ProcessHandle.current().pid()}"

        val origBranch = worktreeService.getCurrentBranch(mainRepoRoot)
            ?: worktreeService.getCurrentRevision(mainRepoRoot)
            ?: "HEAD"

        try {
            indicator.isIndeterminate = false

            // Step 1: Stash (0%–2%)
            scope.checkCanceled()
            scope.fraction(0.0)
            scope.text("Stashing uncommitted changes...")
            if (worktreeService.hasUncommittedChanges(mainRepoRoot)) {
                worktreeService.stashSave(mainRepoRoot, stashName)
            }

            // Step 2: Checkout (2%–5%)
            scope.checkCanceled()
            scope.fraction(0.02)
            scope.text("Checking out $baseBranch...")
            worktreeService.checkout(mainRepoRoot, baseBranch)

            // Step 3: Pull (5%–45%) — git streams progress via stderr
            scope.checkCanceled()
            scope.fraction(0.05)
            scope.text("Pulling latest changes...")
            val pullScope = scope.sub(0.05, 0.40)
            worktreeService.pullFfOnly(mainRepoRoot) { gitPct ->
                pullScope.fraction(gitPct)
            }

            // Step 4: Create worktree (45%–85%) — no progress signal, bar sits at 45%
            scope.checkCanceled()
            scope.fraction(0.45)
            scope.text("Creating worktree...")
            val result = worktreeService.createWorktree(
                worktreePath, branchName, createNewBranch = true,
            )
            result.getOrThrow()

            // Step 5: Provision (85%–95%)
            scope.fraction(0.85)
            ProvisionHelper.provisionWorktree(
                project, worktreePath, config,
                scope = scope.sub(0.85, 0.10),
            )

            // Step 6: Refresh (95%–100%)
            scope.fraction(0.95)
            scope.text("Refreshing worktree list...")
            scope.text2("")
            worktreeService.refreshWorktreeList()
            scope.fraction(1.0)
            Notifications.info(project, "Worktree Created", "Created worktree '$branchName' at $worktreePath")
        } catch (e: Exception) {
            Notifications.error(project, "Create Failed", e.message ?: "Unknown error")
        } finally {
            scope.text2("")
            scope.text("Restoring original state...")
            val checkoutOk = runCatching { worktreeService.checkout(mainRepoRoot, origBranch) }.isSuccess
            if (checkoutOk) {
                runCatching { worktreeService.stashPop(mainRepoRoot, stashName) }
            }
        }
    }
}
