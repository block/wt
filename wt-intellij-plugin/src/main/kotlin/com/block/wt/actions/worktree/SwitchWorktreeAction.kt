package com.block.wt.actions.worktree

import com.block.wt.actions.WtConfigAction
import com.block.wt.provision.ProvisionSwitchHelper
import com.block.wt.services.WorktreeService
import com.block.wt.ui.WorktreePanel
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.ui.popup.JBPopupFactory
import com.intellij.openapi.ui.popup.PopupStep
import com.intellij.openapi.ui.popup.util.BaseListPopupStep

class SwitchWorktreeAction : WtConfigAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return

        // If invoked from the table with a selected row, use that directly
        val selected = e.getData(WorktreePanel.DATA_KEY)?.getSelectedWorktree()
        if (selected != null && !selected.isLinked) {
            ProvisionSwitchHelper.switchWithProvisionPrompt(project, selected)
            return
        }

        val worktreeService = WorktreeService.getInstance(project)

        runInBackground(project, "Loading Worktrees") {
            val worktrees = worktreeService.listWorktrees()
            if (worktrees.isEmpty()) return@runInBackground

            val displayNames = worktrees.map { wt ->
                buildString {
                    if (wt.isLinked) append("* ")
                    append(wt.displayName)
                    if (wt.isMain) append(" [main]")
                }
            }

            ApplicationManager.getApplication().invokeLater {
                val step = object : BaseListPopupStep<String>("Switch Worktree", displayNames) {
                    override fun onChosen(selectedValue: String, finalChoice: Boolean): PopupStep<*>? {
                        if (finalChoice) {
                            val index = displayNames.indexOf(selectedValue)
                            val wt = worktrees.getOrNull(index) ?: return PopupStep.FINAL_CHOICE
                            if (!wt.isLinked) {
                                ProvisionSwitchHelper.switchWithProvisionPrompt(project, wt)
                            }
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
}
