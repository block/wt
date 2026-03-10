package com.block.wt.actions.util

import com.block.wt.actions.WtConfigAction
import com.block.wt.services.WorktreeService
import com.block.wt.ui.Notifications
import com.block.wt.ui.WorktreePanel
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.wm.ToolWindowManager
import org.jetbrains.plugins.terminal.TerminalToolWindowManager

class OpenInTerminalAction : WtConfigAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return

        val selectedPath = e.getData(WorktreePanel.DATA_KEY)?.getSelectedWorktree()?.path
            ?: run {
                val worktreeService = WorktreeService.getInstance(project)
                val worktrees = worktreeService.worktrees.value
                worktrees.firstOrNull { it.isLinked }?.path
                    ?: project.basePath?.let { java.nio.file.Path.of(it) }
            }
            ?: return

        try {
            val terminalWindow = ToolWindowManager.getInstance(project).getToolWindow("Terminal")
            if (terminalWindow != null) {
                terminalWindow.activate {
                    val projectRoot = project.basePath
                    if (projectRoot != null && selectedPath.toString() != projectRoot) {
                        try {
                            val manager = TerminalToolWindowManager.getInstance(project)
                            @Suppress("DEPRECATION")
                            manager.createLocalShellWidget(selectedPath.toString(), selectedPath.fileName?.toString() ?: "Terminal")
                        } catch (_: Throwable) {
                            // Fallback: just activate the terminal window (user can cd manually)
                        }
                    }
                }
            } else {
                Notifications.warning(project, "Terminal", "Terminal tool window is not available")
            }
        } catch (ex: Exception) {
            Notifications.error(project, "Open Terminal", "Failed to open terminal: ${ex.message}")
        }
    }
}
