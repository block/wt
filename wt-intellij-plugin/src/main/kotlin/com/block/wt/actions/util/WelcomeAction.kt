package com.block.wt.actions.util

import com.block.wt.actions.WtAction
import com.block.wt.ui.WelcomePageHelper
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.fileEditor.impl.HTMLEditorProvider
import com.intellij.ui.jcef.JBCefApp

class WelcomeAction : WtAction() {

    override fun isAvailable(e: AnActionEvent): Boolean =
        e.project != null && JBCefApp.isSupported()

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val html = WelcomePageHelper.buildThemedHtml() ?: return
        HTMLEditorProvider.openEditor(project, "Worktree Manager Welcome", html)
    }
}
