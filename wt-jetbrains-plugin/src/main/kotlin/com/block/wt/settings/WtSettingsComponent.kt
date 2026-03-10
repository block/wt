package com.block.wt.settings

import com.intellij.openapi.ui.DialogPanel
import com.intellij.ui.dsl.builder.bindIntValue
import com.intellij.ui.dsl.builder.bindSelected
import com.intellij.ui.dsl.builder.panel
import javax.swing.JComponent

class WtSettingsComponent {

    private val settings = WtPluginSettings.getInstance()

    val panel: DialogPanel = panel {
        group("General") {
            row {
                checkBox("Show context widget in status bar")
                    .bindSelected(settings.state::showStatusBarWidget)
            }
            row {
                checkBox("Auto-refresh on external changes (CLI usage)")
                    .bindSelected(settings.state::autoRefreshOnExternalChange)
            }
            row {
                checkBox("Load status indicators (dirty, ahead/behind) asynchronously")
                    .bindSelected(settings.state::statusLoadingEnabled)
                    .comment("Disable to speed up worktree list loading for repos with many worktrees")
            }
            row {
                checkBox("Prompt to provision when switching to non-provisioned worktrees")
                    .bindSelected(settings.state::promptProvisionOnSwitch)
                    .comment("Shows Provision & Switch / Switch Only / Cancel dialog")
            }
            row("Auto-refresh interval (seconds, 0 to disable):") {
                spinner(0..600, 5)
                    .bindIntValue(settings.state::autoRefreshIntervalSeconds)
                    .comment("Periodically refreshes the worktree list to detect external changes")
            }
        }
        group("Experiments") {
            row {
                checkBox("Enhanced agent session detection (lifecycle states, lock file validation)")
                    .bindSelected(settings.state::enhancedSessionDetection)
            }
            row {
                checkBox("Navigate to agent terminal on click (macOS)")
                    .bindSelected(settings.state::agentTerminalNavigation)
            }
        }
        group("Confirmations") {
            row {
                checkBox("Confirm before switching worktrees")
                    .bindSelected(settings.state::confirmBeforeSwitch)
            }
            row {
                checkBox("Confirm before removing worktrees")
                    .bindSelected(settings.state::confirmBeforeRemove)
            }
        }
    }

    fun getComponent(): JComponent = panel

    fun isModified(): Boolean = panel.isModified()

    fun apply() {
        panel.apply()
    }

    fun reset() {
        panel.reset()
    }
}
