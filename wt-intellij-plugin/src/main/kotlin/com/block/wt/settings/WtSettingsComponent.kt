package com.block.wt.settings

import com.intellij.ui.dsl.builder.bindIntValue
import com.intellij.ui.dsl.builder.bindSelected
import com.intellij.ui.dsl.builder.panel
import javax.swing.JComponent
import javax.swing.JPanel

class WtSettingsComponent {

    private val settings = WtPluginSettings.getInstance()
    private var showStatusBar = settings.state.showStatusBarWidget
    private var autoRefresh = settings.state.autoRefreshOnExternalChange
    private var confirmSwitch = settings.state.confirmBeforeSwitch
    private var confirmRemove = settings.state.confirmBeforeRemove
    private var statusLoading = settings.state.statusLoadingEnabled
    private var promptProvision = settings.state.promptProvisionOnSwitch
    private var autoRefreshInterval = settings.state.autoRefreshIntervalSeconds

    val panel: JPanel = panel {
        group("General") {
            row {
                checkBox("Show context widget in status bar")
                    .bindSelected(::showStatusBar)
            }
            row {
                checkBox("Auto-refresh on external changes (CLI usage)")
                    .bindSelected(::autoRefresh)
            }
            row {
                checkBox("Load status indicators (dirty, ahead/behind) asynchronously")
                    .bindSelected(::statusLoading)
                    .comment("Disable to speed up worktree list loading for repos with many worktrees")
            }
            row {
                checkBox("Prompt to provision when switching to non-provisioned worktrees")
                    .bindSelected(::promptProvision)
                    .comment("Shows Provision & Switch / Switch Only / Cancel dialog")
            }
            row("Auto-refresh interval (seconds, 0 to disable):") {
                spinner(0..600, 5)
                    .bindIntValue(::autoRefreshInterval)
                    .comment("Periodically refreshes the worktree list to detect external changes")
            }
        }
        group("Confirmations") {
            row {
                checkBox("Confirm before switching worktrees")
                    .bindSelected(::confirmSwitch)
            }
            row {
                checkBox("Confirm before removing worktrees")
                    .bindSelected(::confirmRemove)
            }
        }
    }

    fun getComponent(): JComponent = panel

    fun isModified(): Boolean {
        return showStatusBar != settings.state.showStatusBarWidget ||
            autoRefresh != settings.state.autoRefreshOnExternalChange ||
            confirmSwitch != settings.state.confirmBeforeSwitch ||
            confirmRemove != settings.state.confirmBeforeRemove ||
            statusLoading != settings.state.statusLoadingEnabled ||
            promptProvision != settings.state.promptProvisionOnSwitch ||
            autoRefreshInterval != settings.state.autoRefreshIntervalSeconds
    }

    fun apply() {
        settings.loadState(settings.state.copy(
            showStatusBarWidget = showStatusBar,
            autoRefreshOnExternalChange = autoRefresh,
            confirmBeforeSwitch = confirmSwitch,
            confirmBeforeRemove = confirmRemove,
            statusLoadingEnabled = statusLoading,
            promptProvisionOnSwitch = promptProvision,
            autoRefreshIntervalSeconds = autoRefreshInterval,
        ))
    }

    fun reset() {
        showStatusBar = settings.state.showStatusBarWidget
        autoRefresh = settings.state.autoRefreshOnExternalChange
        confirmSwitch = settings.state.confirmBeforeSwitch
        confirmRemove = settings.state.confirmBeforeRemove
        statusLoading = settings.state.statusLoadingEnabled
        promptProvision = settings.state.promptProvisionOnSwitch
        autoRefreshInterval = settings.state.autoRefreshIntervalSeconds
    }
}
