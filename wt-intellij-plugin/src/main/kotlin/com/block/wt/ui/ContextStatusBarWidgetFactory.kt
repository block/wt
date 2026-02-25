package com.block.wt.ui

import com.block.wt.services.ContextService
import com.block.wt.services.WorktreeService
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.popup.ListPopup
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

class ContextStatusBarWidgetFactory : StatusBarWidgetFactory {

    override fun getId(): String = "WtContextWidget"

    override fun getDisplayName(): String = "Worktree Context"

    override fun isAvailable(project: Project): Boolean = true

    override fun createWidget(project: Project): StatusBarWidget {
        return ContextStatusBarWidget(project)
    }

    override fun canBeEnabledOn(statusBar: StatusBar): Boolean = true
}

private class ContextStatusBarWidget(
    private val project: Project,
) : StatusBarWidget, StatusBarWidget.MultipleTextValuesPresentation {

    private var statusBar: StatusBar? = null
    private val cs = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun ID(): String = "WtContextWidget"

    override fun install(statusBar: StatusBar) {
        this.statusBar = statusBar

        cs.launch {
            ContextService.getInstance().currentContextName.collectLatest {
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
        val name = ContextService.getInstance().currentContextName.value
        return "worktree context: ${name ?: "(none)"}"
    }

    override fun getTooltipText(): String = "Current wt context. Click to switch."

    override fun getPopup(): ListPopup? {
        return ContextPopupHelper.createContextSwitchPopup(
            onSwitch = { selectedValue ->
                ContextService.getInstance().switchContext(selectedValue)
                WorktreeService.getInstance(project).refreshWorktreeList()
                statusBar?.updateWidget(ID())
            },
        )
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun getClickConsumer(): Consumer<MouseEvent>? = null
}
