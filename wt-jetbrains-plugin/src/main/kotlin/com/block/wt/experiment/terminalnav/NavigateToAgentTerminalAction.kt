package com.block.wt.experiment.terminalnav

import com.block.wt.actions.WtConfigAction
import com.block.wt.settings.WtPluginSettings
import com.block.wt.ui.WorktreePanel
import com.intellij.openapi.actionSystem.AnActionEvent

/**
 * Context menu action: navigates to the terminal hosting the selected worktree's agent.
 * Hidden when the terminal navigation experiment is disabled or no agent sessions exist.
 */
class NavigateToAgentTerminalAction : WtConfigAction() {

    override fun isAvailable(e: AnActionEvent): Boolean {
        if (!super.isAvailable(e)) return false
        if (!WtPluginSettings.getInstance().state.agentTerminalNavigation) return false
        val wt = e.getData(WorktreePanel.DATA_KEY)?.getSelectedWorktree() ?: return false
        return wt.agentSessions.any { it.pid != null }
    }

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val wt = e.getData(WorktreePanel.DATA_KEY)?.getSelectedWorktree() ?: return
        val session = wt.agentSessions.firstOrNull { it.pid != null } ?: return
        val pid = session.pid ?: return
        TerminalNavigator.navigateToTerminal(project, pid, session.tty)
    }
}
