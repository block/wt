package com.block.wt.actions.util

import com.block.wt.actions.WtTableAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.ide.CopyPasteManager
import java.awt.datatransfer.StringSelection

class CopyWorktreePathAction : WtTableAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val wt = getSelectedPanel(e)?.getSelectedWorktree() ?: return
        CopyPasteManager.getInstance().setContents(StringSelection(wt.path.toString()))
    }
}
