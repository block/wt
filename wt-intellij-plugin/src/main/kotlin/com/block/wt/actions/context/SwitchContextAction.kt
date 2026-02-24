package com.block.wt.actions.context

import com.block.wt.actions.WtAction
import com.block.wt.services.ContextService
import com.block.wt.services.WorktreeService
import com.block.wt.ui.ContextPopupHelper
import com.block.wt.ui.Notifications
import com.intellij.openapi.actionSystem.AnActionEvent

class SwitchContextAction : WtAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val contextService = ContextService.getInstance()

        if (contextService.listContexts().isEmpty()) {
            Notifications.warning(project, "No Contexts", "No wt contexts found in ~/.wt/repos/")
            return
        }

        val popup = ContextPopupHelper.createContextSwitchPopup(
            onSwitch = { selectedValue ->
                runInBackground(project, "Switching Context") {
                    contextService.switchContext(selectedValue)
                    WorktreeService.getInstance(project).refreshWorktreeList()
                    Notifications.info(project, "Context Switched", "Switched to context: $selectedValue")
                }
            },
        ) ?: return

        popup.showCenteredInCurrentWindow(project)
    }
}
