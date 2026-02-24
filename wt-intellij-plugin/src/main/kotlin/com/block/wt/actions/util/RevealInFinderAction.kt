package com.block.wt.actions.util

import com.block.wt.actions.WtTableAction
import com.intellij.ide.actions.RevealFileAction
import com.intellij.openapi.actionSystem.AnActionEvent

class RevealInFinderAction : WtTableAction() {

    override fun update(e: AnActionEvent) {
        super.update(e)
        e.presentation.text = RevealFileAction.getActionName()
    }

    override fun actionPerformed(e: AnActionEvent) {
        val wt = getSelectedPanel(e)?.getSelectedWorktree() ?: return
        RevealFileAction.openDirectory(wt.path)
    }
}
