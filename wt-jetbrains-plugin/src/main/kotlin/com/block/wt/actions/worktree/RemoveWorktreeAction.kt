package com.block.wt.actions.worktree

import com.block.wt.actions.WtConfigAction
import com.block.wt.model.WorktreeInfo
import com.block.wt.progress.RemovalProgress
import com.block.wt.progress.asScope
import com.block.wt.services.ContextService
import com.block.wt.services.SymlinkSwitchService
import com.block.wt.services.WorktreeService
import com.block.wt.settings.WtPluginSettings
import com.block.wt.ui.Notifications
import com.block.wt.ui.WorktreePanel
import com.block.wt.util.normalizeSafe
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.Messages
import com.intellij.openapi.ui.popup.JBPopupFactory
import com.intellij.openapi.ui.popup.PopupStep
import com.intellij.openapi.ui.popup.util.BaseListPopupStep

class RemoveWorktreeAction : WtConfigAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val worktreeService = WorktreeService.getInstance(project)

        // If invoked from the table with a selected row, use that directly
        val selected = e.getData(WorktreePanel.DATA_KEY)?.getSelectedWorktree()
        if (selected != null && !selected.isMain) {
            confirmAndRemove(project, selected, worktreeService)
            return
        }

        runInBackground(project, "Loading Worktrees") {
            val worktrees = worktreeService.listWorktrees()
            val removable = worktrees.filter { !it.isMain }
            if (removable.isEmpty()) {
                Notifications.info(project, "No Worktrees", "No removable worktrees found (main worktree cannot be removed)")
                return@runInBackground
            }

            val displayNames = removable.map { wt ->
                buildString {
                    if (wt.isLinked) append("* ")
                    append(wt.displayName)
                    append(" (${wt.shortPath})")
                }
            }

            ApplicationManager.getApplication().invokeLater {
                val step = object : BaseListPopupStep<String>("Remove Worktree", displayNames) {
                    override fun onChosen(selectedValue: String, finalChoice: Boolean): PopupStep<*>? {
                        if (finalChoice) {
                            val index = displayNames.indexOf(selectedValue)
                            val wt = removable.getOrNull(index) ?: return PopupStep.FINAL_CHOICE
                            confirmAndRemove(project, wt, worktreeService)
                        }
                        return PopupStep.FINAL_CHOICE
                    }
                }

                JBPopupFactory.getInstance()
                    .createListPopup(step)
                    .showCenteredInCurrentWindow(project)
            }
        }
    }

    private fun confirmAndRemove(project: Project, wt: WorktreeInfo, worktreeService: WorktreeService) {
        val config = ContextService.getInstance(project).getCurrentConfig()
        if (config != null && wt.path.normalizeSafe() == config.mainRepoRoot.normalizeSafe()) {
            Notifications.error(project, "Cannot Remove", "Cannot remove the main repository worktree")
            return
        }

        val needsConfirmation = WtPluginSettings.getInstance().state.confirmBeforeRemove || wt.isDirty == true

        if (needsConfirmation) {
            val message = buildString {
                append("Remove worktree '${wt.displayName}' at ${wt.path}?")
                if (wt.isDirty == true) {
                    append("\n\nWARNING: This worktree has uncommitted changes!")
                }
                if (wt.isLinked) {
                    append("\n\nThis is the currently linked worktree. The symlink will be switched to main.")
                }
            }

            val answer = Messages.showYesNoDialog(project, message, "Remove Worktree", Messages.getWarningIcon())
            if (answer != Messages.YES) return
        }

        runInBackground(project, "Removing Worktree", cancellable = false) { indicator ->
            indicator.isIndeterminate = false
            val scope = indicator.asScope()

            if (wt.isLinked && config != null) {
                scope.fraction(0.0)
                scope.text("Switching to main worktree...")
                SymlinkSwitchService.getInstance(project).doSwitch(
                    config.mainRepoRoot, indicator,
                    scope = scope.sub(0.0, 0.05),
                )
            }

            scope.fraction(0.05)
            scope.text("Removing worktree...")
            val force = wt.isDirty == true
            val result = RemovalProgress.removeWithProgress(
                scope.sub(0.05, 0.90), wt.path, worktreeService, force,
            )

            result.fold(
                onSuccess = {
                    scope.fraction(0.95)
                    scope.text("Refreshing worktree list...")
                    worktreeService.refreshWorktreeList()
                    scope.fraction(1.0)
                    Notifications.info(project, "Worktree Removed", "Removed ${wt.displayName}")
                },
                onFailure = { ex ->
                    Notifications.error(project, "Remove Failed", ex.message ?: "Unknown error")
                },
            )
        }
    }
}
