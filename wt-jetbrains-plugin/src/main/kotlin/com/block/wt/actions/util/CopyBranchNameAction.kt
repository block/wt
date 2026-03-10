package com.block.wt.actions.util

import com.block.wt.actions.WtTableAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.ide.CopyPasteManager
import java.awt.datatransfer.StringSelection

class CopyBranchNameAction : WtTableAction() {

    override fun update(e: AnActionEvent) {
        val wt = getSelectedPanel(e)?.getSelectedWorktree()
        e.presentation.isEnabledAndVisible = wt?.branch != null
    }

    override fun actionPerformed(e: AnActionEvent) {
        val wt = getSelectedPanel(e)?.getSelectedWorktree() ?: return
        val branch = wt.branch ?: return
        CopyPasteManager.getInstance().setContents(StringSelection(branch))
    }
}
