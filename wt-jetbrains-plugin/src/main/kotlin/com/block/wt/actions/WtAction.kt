package com.block.wt.actions

import com.block.wt.services.ContextService
import com.block.wt.model.ContextConfig
import com.block.wt.ui.WorktreePanel
import com.intellij.openapi.actionSystem.ActionUpdateThread
import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.project.DumbAware
import com.intellij.openapi.project.Project
import com.intellij.openapi.progress.runBlockingCancellable

/**
 * Base action for all wt plugin actions. Provides DumbAware, BGT update thread,
 * and a `runInBackground` template method for background work with coroutine bridging.
 */
abstract class WtAction : AnAction(), DumbAware {
    override fun getActionUpdateThread() = ActionUpdateThread.BGT

    override fun update(e: AnActionEvent) {
        e.presentation.isEnabledAndVisible = isAvailable(e)
    }

    protected open fun isAvailable(e: AnActionEvent): Boolean =
        e.project != null

    protected fun runInBackground(
        project: Project,
        title: String,
        cancellable: Boolean = true,
        action: suspend (ProgressIndicator) -> Unit,
    ) {
        ProgressManager.getInstance().run(object : Task.Backgroundable(project, title, cancellable) {
            override fun run(indicator: ProgressIndicator) {
                runBlockingCancellable { action(indicator) }
            }
        })
    }
}

/**
 * Base action for actions that require a configured wt context.
 * Greyed out when no context is auto-detected for the current project.
 */
abstract class WtConfigAction : WtAction() {
    override fun isAvailable(e: AnActionEvent): Boolean {
        val project = e.project ?: return false
        return ContextService.getInstance(project).getCurrentConfig() != null
    }

    protected fun requireConfig(e: AnActionEvent): ContextConfig? {
        val project = e.project ?: return null
        return ContextService.getInstance(project).getCurrentConfig()
    }
}

/**
 * Base action for actions that operate on a selected table row.
 * Uses EDT for update() since reading table selection requires Swing thread.
 */
abstract class WtTableAction : AnAction(), DumbAware {
    override fun getActionUpdateThread() = ActionUpdateThread.EDT

    override fun update(e: AnActionEvent) {
        e.presentation.isEnabledAndVisible = getSelectedPanel(e)?.getSelectedWorktree() != null
    }

    protected fun getSelectedPanel(e: AnActionEvent): WorktreePanel? =
        e.getData(WorktreePanel.DATA_KEY)
}
