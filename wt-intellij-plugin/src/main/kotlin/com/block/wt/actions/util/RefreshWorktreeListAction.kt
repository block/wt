package com.block.wt.actions.util

import com.block.wt.actions.WtConfigAction
import com.block.wt.services.WorktreeService
import com.intellij.openapi.actionSystem.AnActionEvent

class RefreshWorktreeListAction : WtConfigAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        WorktreeService.getInstance(project).refreshWorktreeList()
    }
}
