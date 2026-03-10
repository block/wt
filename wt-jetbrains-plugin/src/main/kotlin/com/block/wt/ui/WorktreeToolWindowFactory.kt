package com.block.wt.ui

import com.block.wt.services.WorktreeService
import com.intellij.openapi.project.DumbAware
import com.intellij.openapi.project.Project
import com.intellij.openapi.util.Disposer
import com.intellij.openapi.wm.ToolWindow
import com.intellij.openapi.wm.ToolWindowFactory
import com.intellij.openapi.wm.ex.ToolWindowManagerListener
import com.intellij.ui.content.ContentFactory

class WorktreeToolWindowFactory : ToolWindowFactory, DumbAware {

    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        val panel = WorktreePanel(project)
        val content = ContentFactory.getInstance().createContent(panel, "", false)
        Disposer.register(content, panel)
        toolWindow.contentManager.addContent(content)

        // Start periodic refresh
        WorktreeService.getInstance(project).startPeriodicRefresh()

        // Refresh worktree list when the tool window becomes visible
        val connection = project.messageBus.connect(content)
        connection.subscribe(
            ToolWindowManagerListener.TOPIC,
            object : ToolWindowManagerListener {
                override fun toolWindowShown(tw: ToolWindow) {
                    if (tw.id == toolWindow.id) {
                        panel.refreshIfStale()
                    }
                }
            },
        )
    }

    override fun shouldBeAvailable(project: Project): Boolean = true
}
