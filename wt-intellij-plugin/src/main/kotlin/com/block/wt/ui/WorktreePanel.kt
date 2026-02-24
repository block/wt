package com.block.wt.ui

import com.block.wt.provision.ProvisionMarkerService
import com.block.wt.provision.ProvisionSwitchHelper
import com.block.wt.model.WorktreeInfo
import com.block.wt.model.WorktreeStatus
import com.block.wt.services.ContextService
import com.block.wt.services.WorktreeService
import com.intellij.openapi.Disposable
import com.intellij.openapi.actionSystem.ActionManager
import com.intellij.openapi.actionSystem.ActionPlaces
import com.intellij.openapi.actionSystem.DataKey
import com.intellij.openapi.actionSystem.DataProvider
import com.intellij.openapi.actionSystem.DefaultActionGroup
import com.intellij.openapi.actionSystem.ex.ActionUtil
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.project.Project
import com.intellij.ui.ClickListener
import com.intellij.ui.PopupHandler
import com.intellij.ui.components.JBLabel
import com.intellij.ui.components.JBScrollPane
import com.intellij.ui.dsl.builder.Align
import com.intellij.ui.dsl.builder.panel
import com.intellij.ui.table.JBTable
import com.intellij.util.ui.JBUI
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import java.awt.BorderLayout
import java.awt.CardLayout
import java.awt.Cursor
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import javax.swing.JLabel
import javax.swing.JPanel
import javax.swing.SwingConstants

class WorktreePanel(private val project: Project) : JPanel(BorderLayout()), DataProvider, Disposable {

    private val tableModel = WorktreeTableModel()
    private val table = object : JBTable(tableModel) {
        override fun getToolTipText(event: MouseEvent): String? {
            val row = rowAtPoint(event.point)
            val col = columnAtPoint(event.point)
            if (row < 0) return super.getToolTipText(event)

            val wt = tableModel.getWorktreeAt(row) ?: return super.getToolTipText(event)

            if (col == WorktreeTableModel.COL_PATH) {
                return wt.path.toString()
            }

            if (col == WorktreeTableModel.COL_STATUS) {
                return buildStatusTooltip(wt)
            }

            if (col == WorktreeTableModel.COL_AGENT && wt.hasActiveAgent) {
                return buildAgentTooltip(wt)
            }

            if (col == WorktreeTableModel.COL_PROVISIONED) {
                return buildProvisionTooltip(wt)
            }

            return super.getToolTipText(event)
        }
    }
    private val contextLabel = JLabel("", SwingConstants.LEFT)
    private val cs = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val cardLayout = CardLayout()
    private val centerPanel = JPanel(cardLayout)

    companion object {
        val DATA_KEY: DataKey<WorktreePanel> = DataKey.create("WtWorktreePanel")
        private const val CARD_TABLE = "table"
        private const val CARD_EMPTY = "empty"
    }

    init {
        setupTable()
        setupEmptyState()
        setupToolbar()
        setupContextLabel()
        setupListeners()
        observeState()
    }

    override fun getData(dataId: String): Any? {
        if (DATA_KEY.`is`(dataId)) return this
        return null
    }

    private fun setupTable() {
        table.columnModel.getColumn(WorktreeTableModel.COL_LINKED).apply {
            minWidth = 16; preferredWidth = 20; maxWidth = 30
        }
        table.columnModel.getColumn(WorktreeTableModel.COL_PATH).apply {
            minWidth = 40; preferredWidth = 200
        }
        table.columnModel.getColumn(WorktreeTableModel.COL_BRANCH).apply {
            minWidth = 40; preferredWidth = 160
        }
        table.columnModel.getColumn(WorktreeTableModel.COL_STATUS).apply {
            minWidth = 30; preferredWidth = 130
        }
        table.columnModel.getColumn(WorktreeTableModel.COL_AGENT).apply {
            minWidth = 20; preferredWidth = 30
        }
        table.columnModel.getColumn(WorktreeTableModel.COL_PROVISIONED).apply {
            minWidth = 20; preferredWidth = 35
        }

        table.autoResizeMode = javax.swing.JTable.AUTO_RESIZE_NEXT_COLUMN
        table.setShowGrid(false)
        table.rowHeight = 24

        // Right-click context menu
        PopupHandler.installPopupMenu(table, "Wt.WorktreeRowContextMenu", "WtWorktreeTablePopup")

        centerPanel.add(JBScrollPane(table), CARD_TABLE)
        add(centerPanel, BorderLayout.CENTER)
    }

    private fun setupEmptyState() {
        val emptyPanel = panel {
            row {
                label("No wt context configured")
                    .bold()
                    .align(Align.CENTER)
            }
            row {
                comment("Set up a context to manage git worktrees from the IDE")
                    .align(Align.CENTER)
            }
            row {
                button("Add Context...") {
                    val action = ActionManager.getInstance().getAction("Wt.AddContext")
                    if (action != null) {
                        ActionUtil.invokeAction(action, this@WorktreePanel, ActionPlaces.TOOLWINDOW_CONTENT, null, null)
                    }
                }.align(Align.CENTER)
            }
            row {
                comment("Or run 'wt context add' in the terminal")
                    .align(Align.CENTER)
            }
        }.apply {
            border = JBUI.Borders.empty(40, 20)
        }

        centerPanel.add(emptyPanel, CARD_EMPTY)
    }

    private fun setupToolbar() {
        val actionGroup = ActionManager.getInstance().getAction("Wt.ToolWindowToolbar") as? DefaultActionGroup
            ?: return

        val toolbar = ActionManager.getInstance()
            .createActionToolbar("WtToolWindow", actionGroup, true)
        toolbar.targetComponent = this

        add(toolbar.component, BorderLayout.NORTH)
    }

    private fun setupContextLabel() {
        val config = ContextService.getInstance().getCurrentConfig()
        updateContextLabelText(config?.name)
        contextLabel.border = javax.swing.BorderFactory.createEmptyBorder(2, 4, 2, 4)
        contextLabel.cursor = Cursor.getPredefinedCursor(Cursor.HAND_CURSOR)
        contextLabel.toolTipText = "Click to switch context"

        object : ClickListener() {
            override fun onClick(event: MouseEvent, clickCount: Int): Boolean {
                showContextSwitchPopup()
                return true
            }
        }.installOn(contextLabel)

        add(contextLabel, BorderLayout.SOUTH)
    }

    private fun updateContextLabelText(name: String?) {
        contextLabel.text = if (name != null) "  Context: $name  [switch]" else "  No context  [click to switch]"
    }

    private fun showContextSwitchPopup() {
        val contextService = ContextService.getInstance()

        val popup = ContextPopupHelper.createContextSwitchPopup(
            includeAddContext = true,
            onSwitch = { selectedValue ->
                contextService.switchContext(selectedValue)
                val worktreeService = WorktreeService.getInstance(project)
                worktreeService.refreshWorktreeList()

                // Show setup dialog for the new context if needed
                val newConfig = contextService.getCurrentConfig()
                if (newConfig != null) {
                    cs.launch {
                        val worktrees = worktreeService.listWorktrees()
                        ApplicationManager.getApplication().invokeLater {
                            ContextSetupDialog.showIfNeeded(project, newConfig, worktrees)
                        }
                    }
                }
            },
            onAddContext = {
                val action = ActionManager.getInstance().getAction("Wt.AddContext")
                if (action != null) {
                    ActionUtil.invokeAction(action, this@WorktreePanel, ActionPlaces.TOOLWINDOW_CONTENT, null, null)
                }
            },
        ) ?: return

        popup.showUnderneathOf(contextLabel)
    }

    private fun setupListeners() {
        // Double-click to switch worktree
        table.addMouseListener(object : MouseAdapter() {
            override fun mouseClicked(e: MouseEvent) {
                if (e.clickCount == 2) {
                    val row = table.rowAtPoint(e.point)
                    val wt = tableModel.getWorktreeAt(row) ?: return
                    if (!wt.isLinked) {
                        switchToWorktree(wt)
                    }
                }
            }
        })
    }

    private fun observeState() {
        val worktreeService = WorktreeService.getInstance(project)
        val contextService = ContextService.getInstance()

        cs.launch {
            combine(
                worktreeService.worktrees,
                contextService.currentContextName,
            ) { worktrees, contextName ->
                Pair(worktrees, contextName)
            }.collectLatest { (worktrees, contextName) ->
                // Update worktreesBase for relative paths
                val config = contextService.getCurrentConfig()
                tableModel.worktreesBase = config?.worktreesBase
                tableModel.setWorktrees(worktrees)
                updateContextLabelText(contextName)

                // Show empty state or table
                if (contextName == null && worktrees.isEmpty()) {
                    cardLayout.show(centerPanel, CARD_EMPTY)
                } else {
                    cardLayout.show(centerPanel, CARD_TABLE)
                }
            }
        }
    }

    private fun switchToWorktree(wt: WorktreeInfo) {
        ProvisionSwitchHelper.switchWithProvisionPrompt(project, wt)
    }

    fun getSelectedWorktree(): WorktreeInfo? {
        val row = table.selectedRow
        return if (row >= 0) tableModel.getWorktreeAt(row) else null
    }

    private fun buildStatusTooltip(wt: WorktreeInfo): String? {
        val status = wt.status
        if (status !is WorktreeStatus.Loaded) return null

        val lines = mutableListOf<String>()
        if (status.staged > 0) lines.add("Staged: ${status.staged}")
        if (status.modified > 0) lines.add("Modified: ${status.modified}")
        if (status.untracked > 0) lines.add("Untracked: ${status.untracked}")
        if (status.conflicts > 0) lines.add("Conflicts: ${status.conflicts}")
        status.ahead?.let { if (it > 0) lines.add("Ahead: $it") }
        status.behind?.let { if (it > 0) lines.add("Behind: $it") }

        if (lines.isEmpty()) return "Clean"
        return "<html>${lines.joinToString("<br>")}</html>"
    }

    private fun buildAgentTooltip(wt: WorktreeInfo): String {
        val ids = wt.activeAgentSessionIds
        return when {
            ids.size == 1 -> "<html>Claude agent active<br>Session: ${ids[0]}</html>"
            ids.size > 1 -> "<html>${ids.size} active sessions:<br>${ids.joinToString("<br>") { "&nbsp;&nbsp;$it" }}</html>"
            else -> "Claude agent active"
        }
    }

    private fun buildProvisionTooltip(wt: WorktreeInfo): String {
        if (!wt.isProvisioned) {
            return "Not provisioned \u2014 right-click to provision"
        }

        val marker = ProvisionMarkerService.readProvisionMarker(wt.path) ?: return "Provisioned"
        val currentContextName = ContextService.getInstance().getCurrentConfig()?.name
        val otherContexts = marker.provisions
            .map { it.context }
            .filter { it != marker.current }

        return buildString {
            append("Current: ${marker.current}")
            if (marker.current == currentContextName) {
                append(" (this context)")
            }

            if (otherContexts.isNotEmpty()) {
                append(" | Also provisioned by: ")
                append(otherContexts.joinToString(", ") { name ->
                    if (name == currentContextName) "$name (this context)" else name
                })
            } else if (currentContextName != null && marker.current != currentContextName) {
                append(" | Not provisioned by this context")
            }
        }
    }

    /**
     * Refreshes the worktree list if at least 2 seconds have passed since the last refresh.
     * Used for tool window focus events to avoid rapid re-refreshes.
     */
    fun refreshIfStale() {
        val worktreeService = WorktreeService.getInstance(project)
        if (System.currentTimeMillis() - worktreeService.lastRefreshTime > 2000) {
            worktreeService.refreshWorktreeList()
        }
    }

    override fun dispose() {
        cs.cancel()
    }
}
