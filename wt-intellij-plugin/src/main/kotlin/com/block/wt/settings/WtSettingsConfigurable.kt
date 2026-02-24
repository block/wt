package com.block.wt.settings

import com.intellij.openapi.options.Configurable
import javax.swing.JComponent

class WtSettingsConfigurable : Configurable {

    private var component: WtSettingsComponent? = null

    override fun getDisplayName(): String = "Worktree Manager"

    override fun createComponent(): JComponent {
        component = WtSettingsComponent()
        return component!!.getComponent()
    }

    override fun isModified(): Boolean = component?.isModified() == true

    override fun apply() {
        component?.apply()
    }

    override fun reset() {
        component?.reset()
    }

    override fun disposeUIResources() {
        component = null
    }
}
