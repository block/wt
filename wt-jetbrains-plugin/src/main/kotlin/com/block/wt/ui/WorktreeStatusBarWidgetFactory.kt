package com.block.wt.ui

import com.block.wt.model.WorktreeInfo
import com.block.wt.provision.ProvisionSwitchHelper
import com.block.wt.services.WorktreeService
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.popup.JBPopupFactory
import com.intellij.openapi.ui.popup.ListPopup
import com.intellij.openapi.ui.popup.PopupStep
import com.intellij.openapi.ui.popup.util.BaseListPopupStep
import com.intellij.openapi.wm.StatusBar
import com.intellij.openapi.wm.StatusBarWidget
import com.intellij.openapi.wm.StatusBarWidgetFactory
import com.intellij.util.Consumer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.awt.event.MouseEvent

class WorktreeStatusBarWidgetFactory : StatusBarWidgetFactory {

    override fun getId(): String = "WtWorktreeWidget"

    override fun getDisplayName(): String = "Active Worktree"

    override fun isAvailable(project: Project): Boolean = true

    override fun createWidget(project: Project): StatusBarWidget {
        return WorktreeStatusBarWidget(project)
    }

    override fun canBeEnabledOn(statusBar: StatusBar): Boolean = true
}

private class WorktreeStatusBarWidget(
    private val project: Project,
) : StatusBarWidget, StatusBarWidget.MultipleTextValuesPresentation {

    private var statusBar: StatusBar? = null
    private val cs = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun ID(): String = "WtWorktreeWidget"

    override fun install(statusBar: StatusBar) {
        this.statusBar = statusBar

        cs.launch {
            WorktreeService.getInstance(project).worktrees.collectLatest {
                statusBar.updateWidget(ID())
            }
        }
    }

    override fun dispose() {
        cs.cancel()
        statusBar = null
    }

    override fun getPresentation(): StatusBarWidget.WidgetPresentation = this

    override fun getSelectedValue(): String? {
        val linked = WorktreeService.getInstance(project).worktrees.value
            .firstOrNull { it.isLinked }
        return "active worktree: ${linked?.displayName ?: "(none)"}"
    }

    override fun getTooltipText(): String = "Active worktree. Click to switch."

    override fun getPopup(): ListPopup? {
        val worktreeService = WorktreeService.getInstance(project)
        val worktrees = worktreeService.worktrees.value
        if (worktrees.isEmpty()) return null

        val displayNames = worktrees.map { wt ->
            buildString {
                if (wt.isLinked) append("* ")
                append(wt.displayName)
                if (wt.isMain) append(" [main]")
            }
        }

        val step = object : BaseListPopupStep<String>("Switch Worktree", displayNames) {
            override fun getDefaultOptionIndex(): Int {
                return worktrees.indexOfFirst { it.isLinked }.coerceAtLeast(0)
            }

            override fun onChosen(selectedValue: String, finalChoice: Boolean): PopupStep<*>? {
                if (finalChoice) {
                    val index = displayNames.indexOf(selectedValue)
                    val wt = worktrees.getOrNull(index) ?: return PopupStep.FINAL_CHOICE
                    if (!wt.isLinked) {
                        ApplicationManager.getApplication().invokeLater {
                            ProvisionSwitchHelper.switchWithProvisionPrompt(project, wt)
                        }
                    }
                }
                return PopupStep.FINAL_CHOICE
            }
        }

        return JBPopupFactory.getInstance().createListPopup(step)
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun getClickConsumer(): Consumer<MouseEvent>? = null
}
