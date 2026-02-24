package com.block.wt.actions.util

import com.block.wt.actions.WtAction
import com.block.wt.services.WorktreeService
import com.intellij.openapi.actionSystem.AnActionEvent

class RefreshWorktreeListAction : WtAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        WorktreeService.getInstance(project).refreshWorktreeList()
    }
}
