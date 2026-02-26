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
import com.intellij.openapi.project.Project
import com.intellij.ui.PopupHandler
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
import java.awt.Color
import java.awt.Component
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import javax.swing.JLabel
import javax.swing.JPanel
import javax.swing.SwingConstants
import javax.swing.table.TableCellRenderer

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

        override fun prepareRenderer(renderer: TableCellRenderer, row: Int, column: Int): Component {
            val comp = super.prepareRenderer(renderer, row, column)
            if (!isRowSelected(row)) {
                val wt = tableModel.getWorktreeAt(row)
                if (wt != null && wt.isLinked) {
                    comp.background = linkedRowBackground()
                } else {
                    // Explicitly reset: DefaultTableCellRenderer caches setBackground() calls
                    // in its unselectedBackground field, so the linked row's green tint leaks
                    // to subsequent rows without this reset.
                    comp.background = getBackground()
                }
            }
            return comp
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
        private const val CARD_LOADING = "loading"
    }

    init {
        setupTable()
        setupLoadingState()
        setupEmptyState()
        setupToolbar()
        setupContextLabel()
        setupListeners()
        cardLayout.show(centerPanel, CARD_LOADING)
        observeState()
        // Panel may be created after startup activity completed; re-init to ensure fresh state
        ContextService.getInstance(project).initialize()
        WorktreeService.getInstance(project).refreshWorktreeList()
    }

    override fun getData(dataId: String): Any? {
        if (DATA_KEY.`is`(dataId)) return this
        return null
    }

    private fun setupTable() {
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

    private fun setupLoadingState() {
        val loadingPanel = panel {
            row {
                label("Loading worktree context...")
                    .align(Align.CENTER)
            }
        }.apply {
            border = JBUI.Borders.empty(40, 20)
        }
        centerPanel.add(loadingPanel, CARD_LOADING)
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
        val config = ContextService.getInstance(project).getCurrentConfig()
        updateContextLabelText(config?.name)
        contextLabel.border = javax.swing.BorderFactory.createEmptyBorder(2, 4, 2, 4)

        add(contextLabel, BorderLayout.SOUTH)
    }

    private fun updateContextLabelText(name: String?) {
        contextLabel.text = if (name != null) "  Context: $name" else "  No context"
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
        val contextService = ContextService.getInstance(project)

        cs.launch {
            combine(
                worktreeService.worktrees,
                contextService.config,
                worktreeService.isLoading,
            ) { worktrees, config, isLoading ->
                Triple(worktrees, config, isLoading)
            }.collectLatest { (worktrees, config, isLoading) ->
                // Update worktreesBase for relative paths
                tableModel.worktreesBase = config?.worktreesBase
                tableModel.setWorktrees(worktrees)
                updateContextLabelText(config?.name)

                // Show loading until first refresh completes, then empty or table
                when {
                    isLoading && worktrees.isEmpty() -> cardLayout.show(centerPanel, CARD_LOADING)
                    config == null && worktrees.isEmpty() -> cardLayout.show(centerPanel, CARD_EMPTY)
                    else -> cardLayout.show(centerPanel, CARD_TABLE)
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
        val currentContextName = ContextService.getInstance(project).getCurrentConfig()?.name
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

    private fun linkedRowBackground(): Color {
        val bg = table.background
        val isDark = (bg.red * 0.299 + bg.green * 0.587 + bg.blue * 0.114) < 128
        return if (isDark) {
            Color(bg.red, (bg.green + 30).coerceAtMost(255), bg.blue, bg.alpha)
        } else {
            Color((bg.red * 0.92).toInt(), (bg.green * 0.98).toInt(), (bg.blue * 0.92).toInt(), bg.alpha)
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
