package com.block.wt.actions.worktree

import com.block.wt.actions.WtAction
import com.block.wt.progress.RemovalProgress
import com.block.wt.progress.asScope
import com.block.wt.services.WorktreeService
import com.block.wt.ui.Notifications
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.ui.Messages
import com.intellij.openapi.progress.runBlockingCancellable

class RemoveMergedAction : WtAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val worktreeService = WorktreeService.getInstance(project)

        runInBackground(project, "Finding Merged Worktrees") { indicator ->
            indicator.text = "Checking merged branches..."

            val worktrees = worktreeService.listWorktrees()
            val mergedBranches = worktreeService.getMergedBranches().toSet()

            val mergedWorktrees = worktrees.filter { wt ->
                !wt.isMain && !wt.isLinked && wt.branch in mergedBranches
            }

            if (mergedWorktrees.isEmpty()) {
                Notifications.info(project, "No Merged Worktrees", "No worktrees with merged branches found")
                return@runInBackground
            }

            val dirtyWorktrees = mergedWorktrees.filter { wt ->
                worktreeService.hasUncommittedChanges(wt.path)
            }

            val cleanWorktrees = mergedWorktrees - dirtyWorktrees.toSet()

            val message = buildString {
                append("Remove ${cleanWorktrees.size} merged worktree(s)?")
                for (wt in cleanWorktrees) {
                    append("\n  - ${wt.displayName} (${wt.shortPath})")
                }
                if (dirtyWorktrees.isNotEmpty()) {
                    append("\n\nSkipping ${dirtyWorktrees.size} dirty worktree(s):")
                    for (wt in dirtyWorktrees) {
                        append("\n  - ${wt.displayName} (${wt.shortPath}) [dirty]")
                    }
                }
            }

            com.intellij.openapi.application.ApplicationManager.getApplication().invokeLater {
                val answer = Messages.showYesNoDialog(
                    project, message, "Remove Merged Worktrees", Messages.getWarningIcon()
                )

                if (answer == Messages.YES) {
                    ProgressManager.getInstance().run(object : Task.Backgroundable(
                        project, "Removing Merged Worktrees", false
                    ) {
                        override fun run(indicator: ProgressIndicator) {
                            runBlockingCancellable {
                                indicator.isIndeterminate = false
                                val scope = indicator.asScope()
                                var removed = 0
                                var failed = 0

                                for ((i, wt) in cleanWorktrees.withIndex()) {
                                    val wtStart = i.toDouble() / cleanWorktrees.size * 0.95
                                    val wtSize = 0.95 / cleanWorktrees.size
                                    val wtScope = scope.sub(wtStart, wtSize)

                                    scope.text("Removing ${wt.displayName}...")
                                    val result = RemovalProgress.removeWithProgress(
                                        wtScope, wt.path, worktreeService,
                                    )
                                    if (result.isSuccess) removed++ else failed++
                                }

                                scope.fraction(0.95)
                                scope.text("Refreshing worktree list...")
                                scope.text2("")
                                worktreeService.refreshWorktreeList()
                                scope.fraction(1.0)

                                val msg = buildString {
                                    append("Removed $removed worktree(s)")
                                    if (failed > 0) append(", $failed failed")
                                    if (dirtyWorktrees.isNotEmpty()) {
                                        append(", ${dirtyWorktrees.size} skipped (dirty)")
                                    }
                                }
                                Notifications.info(project, "Merged Worktrees Removed", msg)
                            }
                        }
                    })
                }
            }
        }
    }
}
