package com.block.wt.ui

import com.block.wt.services.ContextService
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.ui.popup.JBPopupFactory
import com.intellij.openapi.ui.popup.ListPopup
import com.intellij.openapi.ui.popup.PopupStep
import com.intellij.openapi.ui.popup.util.BaseListPopupStep

object ContextPopupHelper {

    /**
     * Creates a context-switch popup. Calls [onSwitch] with the selected context name.
     * Optionally includes an "Add Context..." entry at the bottom.
     */
    fun createContextSwitchPopup(
        includeAddContext: Boolean = false,
        onSwitch: (String) -> Unit,
        onAddContext: (() -> Unit)? = null,
    ): ListPopup? {
        val contextService = ContextService.getInstance()
        val contexts = contextService.listContexts()
        if (contexts.isEmpty() && !includeAddContext) return null

        val currentName = contextService.currentContextName.value

        val items = mutableListOf<String>()
        items.addAll(contexts.map { it.name })
        if (includeAddContext && onAddContext != null) {
            if (items.isNotEmpty()) items.add("---")
            items.add("Add Context...")
        }

        val step = object : BaseListPopupStep<String>("Switch Context", items) {
            override fun isSelectable(value: String): Boolean = value != "---"

            override fun onChosen(selectedValue: String, finalChoice: Boolean): PopupStep<*>? {
                if (finalChoice) {
                    ApplicationManager.getApplication().invokeLater {
                        if (selectedValue == "Add Context..." && onAddContext != null) {
                            onAddContext()
                        } else {
                            onSwitch(selectedValue)
                        }
                    }
                }
                return PopupStep.FINAL_CHOICE
            }

            override fun getDefaultOptionIndex(): Int {
                return contexts.indexOfFirst { it.name == currentName }.coerceAtLeast(0)
            }
        }

        return JBPopupFactory.getInstance().createListPopup(step)
    }
}
