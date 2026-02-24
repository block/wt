package com.block.wt.settings

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.PersistentStateComponent
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.State
import com.intellij.openapi.components.Storage
import com.intellij.openapi.components.service

@Service(Service.Level.APP)
@State(
    name = "com.block.wt.settings.WtPluginSettings",
    storages = [Storage("WtPluginSettings.xml")]
)
class WtPluginSettings : PersistentStateComponent<WtPluginSettings.State> {

    data class State(
        var showStatusBarWidget: Boolean = true,
        var autoRefreshOnExternalChange: Boolean = true,
        var confirmBeforeSwitch: Boolean = false,
        var confirmBeforeRemove: Boolean = true,
        var statusLoadingEnabled: Boolean = true,
        var autoExportOnShutdown: Boolean = false,
        var debounceDelayMs: Long = 500,
        var promptProvisionOnSwitch: Boolean = true,
        var autoRefreshIntervalSeconds: Int = 30,
        var setupCompletedContexts: MutableList<String> = mutableListOf(),
        var lastWelcomeVersion: String = "",
    )

    @Volatile
    private var state = State()

    override fun getState(): State = state

    override fun loadState(state: State) {
        this.state = state
    }

    companion object {
        fun getInstance(): WtPluginSettings =
            ApplicationManager.getApplication().service()
    }
}
