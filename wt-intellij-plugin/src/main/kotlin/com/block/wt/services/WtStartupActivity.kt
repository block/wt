package com.block.wt.services

import com.block.wt.settings.WtPluginSettings
import com.block.wt.ui.ContextSetupDialog
import com.block.wt.ui.WelcomePageHelper
import com.intellij.ide.plugins.PluginManagerCore
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.extensions.PluginId
import com.intellij.openapi.fileEditor.impl.HTMLEditorProvider
import com.intellij.openapi.project.Project
import com.intellij.openapi.startup.ProjectActivity
import com.intellij.ui.jcef.JBCefApp

class WtStartupActivity : ProjectActivity {
    override suspend fun execute(project: Project) {
        // Initialize context service (project-level, auto-detects context)
        ContextService.getInstance(project).initialize()

        // Start watching for external changes
        ExternalChangeWatcher.getInstance(project).startWatching()

        // Initial worktree list load
        val worktreeService = WorktreeService.getInstance(project)
        worktreeService.refreshWorktreeList()

        // Show context setup dialog if this context hasn't been set up yet
        val config = ContextService.getInstance(project).getCurrentConfig()
        if (config != null) {
            val worktrees = worktreeService.listWorktrees()
            ApplicationManager.getApplication().invokeLater {
                ContextSetupDialog.showIfNeeded(project, config, worktrees)
            }
        }

        // Show welcome tab on first install or version update
        showWelcomeTabIfNeeded(project)
    }

    private fun showWelcomeTabIfNeeded(project: Project) {
        val currentVersion = PluginManagerCore.getPlugin(PluginId.getId("com.block.wt"))?.version ?: return
        val settings = WtPluginSettings.getInstance()
        if (settings.state.lastWelcomeVersion == currentVersion) return
        if (!JBCefApp.isSupported()) return

        settings.state.lastWelcomeVersion = currentVersion

        ApplicationManager.getApplication().invokeLater {
            val html = WelcomePageHelper.buildThemedHtml() ?: return@invokeLater
            HTMLEditorProvider.openEditor(project, "Worktree Manager Welcome", html)
        }
    }
}
