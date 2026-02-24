package com.block.wt.ui

import com.block.wt.provision.ProvisionHelper
import com.block.wt.provision.ProvisionMarkerService
import com.block.wt.model.ContextConfig
import com.block.wt.model.WorktreeInfo
import com.block.wt.services.WorktreeService
import com.block.wt.settings.WtPluginSettings
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.progress.runBlockingCancellable
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.ui.CheckBoxList
import com.intellij.ui.components.JBLabel
import com.intellij.ui.components.JBScrollPane
import com.intellij.util.ui.JBUI
import java.awt.BorderLayout
import java.awt.Dimension
import javax.swing.BoxLayout
import javax.swing.JComponent
import javax.swing.JPanel

/**
 * One-time setup dialog shown when a context is first used.
 * Lists all non-provisioned worktrees and lets the user pick which to provision.
 *
 * Results:
 * - OK ("Provision Selected") → provisions checked worktrees, marks context as set up
 * - CANCEL with "Skip" → marks context as set up without provisioning
 * - CANCEL with close button → does nothing, will ask again next time
 */
class ContextSetupDialog(
    private val project: Project,
    private val config: ContextConfig,
    private val worktrees: List<WorktreeInfo>,
) : DialogWrapper(project) {

    private val checkBoxList = CheckBoxList<WorktreeEntry>()
    private var skipped = false

    data class WorktreeEntry(
        val wt: WorktreeInfo,
        val hasMetadata: Boolean,
    ) {
        override fun toString(): String = buildString {
            append(wt.displayName)
            append("  (${wt.shortPath})")
            if (hasMetadata) append("  — has project files, will keep")
            else append("  — no project files, will import from vault")
        }
    }

    init {
        title = "Set Up Context: ${config.name}"
        setOKButtonText("Provision Selected")
        setCancelButtonText("Remind Me Later")
        init()
    }

    override fun createCenterPanel(): JComponent {
        val panel = JPanel(BorderLayout())
        panel.preferredSize = Dimension(600, 350)

        val header = JPanel().apply {
            layout = BoxLayout(this, BoxLayout.Y_AXIS)
            border = JBUI.Borders.emptyBottom(12)

            add(JBLabel("The following worktrees haven't been provisioned by context '${config.name}'."))
            add(JBLabel("Select which ones to provision:").apply {
                border = JBUI.Borders.emptyTop(4)
            })
        }
        panel.add(header, BorderLayout.NORTH)

        // Populate the checkbox list with non-provisioned worktrees
        val unprovisioned = worktrees.filter { !it.isProvisionedByCurrentContext }
        for (wt in unprovisioned) {
            val hasMetadata = ProvisionMarkerService.hasExistingMetadata(wt.path)
            val entry = WorktreeEntry(wt, hasMetadata)
            checkBoxList.addItem(entry, entry.toString(), true)
        }
        panel.add(JBScrollPane(checkBoxList), BorderLayout.CENTER)

        val footer = JBLabel("Worktrees with existing project files will be marked as provisioned without changes. " +
            "Others will have metadata imported from the vault.").apply {
            foreground = JBUI.CurrentTheme.Label.disabledForeground()
            border = JBUI.Borders.emptyTop(8)
        }
        panel.add(footer, BorderLayout.SOUTH)

        return panel
    }

    override fun createLeftSideActions(): Array<javax.swing.Action> {
        val skipAction = object : DialogWrapperAction("Skip Setup") {
            override fun doAction(e: java.awt.event.ActionEvent) {
                skipped = true
                close(CANCEL_EXIT_CODE)
            }
        }
        return arrayOf(skipAction)
    }

    /**
     * Returns true if the user explicitly chose "Skip Setup" (marks context as done).
     * Returns false if the user closed the dialog via X or "Remind Me Later".
     */
    fun wasSkipped(): Boolean = skipped

    /**
     * Returns the checked worktree entries. Only valid after OK.
     */
    fun getSelectedEntries(): List<WorktreeEntry> {
        val selected = mutableListOf<WorktreeEntry>()
        for (i in 0 until checkBoxList.itemsCount) {
            if (checkBoxList.isItemSelected(i)) {
                checkBoxList.getItemAt(i)?.let { selected.add(it) }
            }
        }
        return selected
    }

    companion object {
        /**
         * Shows the context setup dialog if the current context hasn't been set up yet.
         * Called from startup activity or context switch.
         */
        fun showIfNeeded(project: Project, config: ContextConfig, worktrees: List<WorktreeInfo>) {
            val settings = WtPluginSettings.getInstance()
            if (config.name in settings.state.setupCompletedContexts) return

            // Only show if there are non-provisioned worktrees
            val hasUnprovisioned = worktrees.any { !it.isProvisionedByCurrentContext }
            if (!hasUnprovisioned) {
                // All worktrees are already provisioned — mark as done silently
                markSetupComplete(config.name)
                return
            }

            val dialog = ContextSetupDialog(project, config, worktrees)
            if (dialog.showAndGet()) {
                // OK — provision selected worktrees
                val selected = dialog.getSelectedEntries()
                if (selected.isNotEmpty()) {
                    runProvisioning(project, config, selected)
                }
                markSetupComplete(config.name)
            } else if (dialog.wasSkipped()) {
                // Skip — mark as done without provisioning
                markSetupComplete(config.name)
            }
            // else: Remind Me Later / closed — do nothing, will ask again
        }

        private fun markSetupComplete(contextName: String) {
            val settings = WtPluginSettings.getInstance()
            if (contextName !in settings.state.setupCompletedContexts) {
                val newState = settings.state.copy(
                    setupCompletedContexts = (settings.state.setupCompletedContexts + contextName).toMutableList()
                )
                settings.loadState(newState)
            }
        }

        private fun runProvisioning(
            project: Project,
            config: ContextConfig,
            entries: List<WorktreeEntry>,
        ) {
            ProgressManager.getInstance().run(object : Task.Backgroundable(
                project, "Provisioning Worktrees", true
            ) {
                override fun run(indicator: ProgressIndicator) {
                    runBlockingCancellable {
                        for ((i, entry) in entries.withIndex()) {
                            indicator.checkCanceled()
                            indicator.fraction = i.toDouble() / entries.size
                            indicator.text = "Provisioning ${entry.wt.displayName}..."

                            ProvisionHelper.provisionWorktree(
                                project,
                                entry.wt.path,
                                config,
                                keepExistingFiles = entry.hasMetadata,
                                indicator = indicator,
                            )
                        }

                        WorktreeService.getInstance(project).refreshWorktreeList()
                        Notifications.info(
                            project,
                            "Context Setup Complete",
                            "Provisioned ${entries.size} worktree(s) for context '${config.name}'",
                        )
                    }
                }
            })
        }
    }
}
