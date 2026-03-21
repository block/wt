package com.block.wt.ui

import com.block.wt.experiment.sessionstats.SessionTooltipBuilder
import com.block.wt.experiment.terminalnav.TerminalNavigator
import com.block.wt.provision.ProvisionMarkerService
import com.block.wt.provision.ProvisionSwitchHelper
import com.block.wt.model.PullRequestInfo
import com.block.wt.model.WorktreeInfo
import com.block.wt.model.WorktreeStatus
import com.block.wt.services.ContextService
import com.block.wt.services.WorktreeService
import com.block.wt.settings.WtPluginSettings
import com.intellij.ide.BrowserUtil
import com.intellij.openapi.Disposable
import com.intellij.openapi.actionSystem.ActionManager
import com.intellij.openapi.actionSystem.ActionPlaces
import com.intellij.openapi.actionSystem.DataKey
import com.intellij.openapi.actionSystem.DataProvider
import com.intellij.openapi.actionSystem.DefaultActionGroup
import com.intellij.openapi.actionSystem.ex.ActionUtil
import com.intellij.openapi.project.Project
import com.intellij.openapi.wm.ToolWindowManager
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
import java.awt.Cursor
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.event.MouseMotionAdapter
import javax.swing.JLabel
import javax.swing.JPanel
import javax.swing.JTextPane
import javax.swing.text.SimpleAttributeSet
import javax.swing.text.StyleConstants
import javax.swing.SwingConstants
import javax.swing.table.DefaultTableCellRenderer
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

            if (col == WorktreeTableModel.COL_AGENT && (wt.hasActiveAgent || wt.agentSessions.isNotEmpty())) {
                return buildAgentTooltip(wt)
            }

            if (col == WorktreeTableModel.COL_PROVISIONED) {
                return buildProvisionTooltip(wt)
            }

            if (col == WorktreeTableModel.COL_PR) {
                return buildPRTooltip(wt)
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
            // PR column: color-code by PR state. Other columns: reset foreground
            // to prevent DefaultTableCellRenderer from leaking the cached color.
            if (column == WorktreeTableModel.COL_PR && !isRowSelected(row)) {
                val wt = tableModel.getWorktreeAt(row)
                if (wt != null) {
                    val prColor = prColumnColor(wt.prInfo)
                    if (prColor != null) comp.foreground = prColor
                }
            } else if (!isRowSelected(row)) {
                comp.foreground = getForeground()
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
            minWidth = 20; preferredWidth = 120
            cellRenderer = MultiLineCellRenderer()
        }
        table.columnModel.getColumn(WorktreeTableModel.COL_PR).apply {
            minWidth = 40; preferredWidth = 80
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
        table.addMouseListener(object : MouseAdapter() {
            override fun mouseClicked(e: MouseEvent) {
                val row = table.rowAtPoint(e.point)
                val col = table.columnAtPoint(e.point)

                // Single-click on Status column → open Commit tool window (active worktree only)
                if (e.clickCount == 1 && col == WorktreeTableModel.COL_STATUS) {
                    val wt = tableModel.getWorktreeAt(row) ?: return
                    if (wt.isLinked && wt.isDirty == true) {
                        activateToolWindow("Commit")
                        return
                    }
                }

                // Single-click on Branch column → open Git log filtered to branch (active worktree only)
                if (e.clickCount == 1 && col == WorktreeTableModel.COL_BRANCH) {
                    val wt = tableModel.getWorktreeAt(row) ?: return
                    if (wt.isLinked) {
                        openGitLogForBranch(wt.branch)
                        return
                    }
                }

                // Single-click on Agent column → navigate to agent terminal
                if (e.clickCount == 1 && col == WorktreeTableModel.COL_AGENT) {
                    val wt = tableModel.getWorktreeAt(row) ?: return
                    if (wt.agentSessions.isNotEmpty() && WtPluginSettings.getInstance().state.agentTerminalNavigation) {
                        val cellRect = table.getCellRect(row, col, true)
                        val yInCell = e.y - cellRect.y
                        handleAgentClick(wt, yInCell, cellRect.height)
                        return
                    }
                }

                // Single-click on PR column → open PR tool (active worktree only)
                if (e.clickCount == 1 && col == WorktreeTableModel.COL_PR) {
                    val wt = tableModel.getWorktreeAt(row) ?: return
                    if (wt.isLinked) {
                        handlePRClick(wt)
                        return
                    }
                }

                // Double-click to switch worktree
                if (e.clickCount == 2) {
                    val wt = tableModel.getWorktreeAt(row) ?: return
                    if (!wt.isLinked) {
                        switchToWorktree(wt)
                    }
                }
            }
        })

        val defaultCursor = Cursor.getDefaultCursor()
        val handCursor = Cursor.getPredefinedCursor(Cursor.HAND_CURSOR)
        table.addMouseMotionListener(object : MouseMotionAdapter() {
            override fun mouseMoved(e: MouseEvent) {
                val row = table.rowAtPoint(e.point)
                val col = table.columnAtPoint(e.point)
                if (row < 0 || col < 0) {
                    table.cursor = defaultCursor
                    return
                }
                val wt = tableModel.getWorktreeAt(row)
                val clickable = when {
                    col == WorktreeTableModel.COL_BRANCH && wt != null && wt.isLinked -> true
                    col == WorktreeTableModel.COL_STATUS && wt != null && wt.isLinked && wt.isDirty == true -> true
                    col == WorktreeTableModel.COL_AGENT && wt != null &&
                        wt.agentSessions.isNotEmpty() &&
                        WtPluginSettings.getInstance().state.agentTerminalNavigation -> true
                    col == WorktreeTableModel.COL_PR && wt != null && wt.isLinked &&
                        wt.prInfo !is PullRequestInfo.NotLoaded -> true
                    else -> false
                }
                table.cursor = if (clickable) handCursor else defaultCursor
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

    private fun handleAgentClick(wt: WorktreeInfo, yInCell: Int, rowHeight: Int) {
        val sessions = wt.agentSessions
        if (sessions.isEmpty()) return
        val index = tableModel.getSessionIndexAtOffset(wt, yInCell, rowHeight)
        val session = sessions.getOrNull(index) ?: sessions.first()
        val pid = session.pid ?: return
        TerminalNavigator.navigateToTerminal(project, pid, session.tty)
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

    private fun buildAgentTooltip(wt: WorktreeInfo): String =
        SessionTooltipBuilder.buildAgentTooltip(wt.agentSessions, wt.activeAgentSessionIds, wt.path)

    private fun buildProvisionTooltip(wt: WorktreeInfo): String {
        if (!wt.isProvisioned) {
            return "Not provisioned \u2014 right-click to provision"
        }

        val adoptedContext = ProvisionMarkerService.readAdoptedContext(wt.path)
            ?: return "Adopted (unknown context)"
        val currentContextName = ContextService.getInstance(project).getCurrentConfig()?.name

        return if (currentContextName != null && adoptedContext != currentContextName) {
            "Adopted by: $adoptedContext (different from current: $currentContextName)"
        } else {
            "Adopted by: $adoptedContext \u2713"
        }
    }

    private fun handlePRClick(wt: WorktreeInfo) {
        when (val pr = wt.prInfo) {
            is PullRequestInfo.Open,
            is PullRequestInfo.Draft,
            is PullRequestInfo.Merged,
            is PullRequestInfo.Closed -> {
                // Try to show the PR for the current branch in the Pull Requests tool window
                val showAction = ActionManager.getInstance().getAction("Github.Pull.Request.Show.In.Toolwindow")
                if (showAction != null) {
                    ActionUtil.invokeAction(showAction, this@WorktreePanel, ActionPlaces.TOOLWINDOW_CONTENT, null, null)
                } else {
                    val url = when (pr) {
                        is PullRequestInfo.Open -> pr.url
                        is PullRequestInfo.Draft -> pr.url
                        is PullRequestInfo.Merged -> pr.url
                        is PullRequestInfo.Closed -> pr.url
                        else -> return
                    }
                    BrowserUtil.browse(url)
                }
            }
            is PullRequestInfo.NoPR -> {
                val createAction = ActionManager.getInstance().getAction("Github.Create.Pull.Request")
                if (createAction != null) {
                    ActionUtil.invokeAction(createAction, this@WorktreePanel, ActionPlaces.TOOLWINDOW_CONTENT, null, null)
                } else {
                    val branch = wt.branch ?: return
                    val slug = WorktreeService.getInstance(project).repoSlug ?: return
                    BrowserUtil.browse("https://github.com/$slug/compare/$branch?expand=1")
                }
            }
            is PullRequestInfo.NotLoaded -> {} // no-op
        }
    }

    private fun openGitLogForBranch(branch: String?) {
        if (branch == null) {
            activateToolWindow("Git")
            return
        }
        try {
            val vcsProjectLog = com.intellij.vcs.log.impl.VcsProjectLog.getInstance(project)
            val branchFilter = com.intellij.vcs.log.visible.filters.VcsLogFilterObject.fromBranch(branch)
            val filterCollection = com.intellij.vcs.log.visible.filters.VcsLogFilterObject.collection(branchFilter)
            vcsProjectLog.openLogTab(filterCollection)
        } catch (_: Exception) {
            // Fallback if VcsLog API not available
            activateToolWindow("Git")
        }
    }

    private fun activateToolWindow(id: String) {
        ToolWindowManager.getInstance(project).getToolWindow(id)?.activate(null)
    }

    private fun prColumnColor(prInfo: PullRequestInfo): Color? = when (prInfo) {
        is PullRequestInfo.Open -> Color(0x2E, 0xA0, 0x43)     // green
        is PullRequestInfo.Draft -> Color(0x88, 0x88, 0x88)     // gray
        is PullRequestInfo.Merged -> Color(0x8B, 0x5C, 0xF6)    // purple
        is PullRequestInfo.Closed -> Color(0xD1, 0x24, 0x2D)    // red
        is PullRequestInfo.NoPR -> Color(0x3B, 0x82, 0xF6)      // blue
        is PullRequestInfo.NotLoaded -> null
    }

    private fun buildPRTooltip(wt: WorktreeInfo): String? = when (val pr = wt.prInfo) {
        is PullRequestInfo.Open -> "<html>PR #${pr.number} (Open)<br>${pr.title}</html>"
        is PullRequestInfo.Draft -> "<html>PR #${pr.number} (Draft)<br>${pr.title}</html>"
        is PullRequestInfo.Merged -> "<html>PR #${pr.number} (Merged)<br>${pr.title}</html>"
        is PullRequestInfo.Closed -> "<html>PR #${pr.number} (Closed)<br>${pr.title}</html>"
        is PullRequestInfo.NoPR -> "Click to create a PR for this branch"
        is PullRequestInfo.NotLoaded -> null
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

    /** Cell renderer that supports newline-separated multi-line text with spacing. */
    private class MultiLineCellRenderer : TableCellRenderer {
        private val textPane = JTextPane().apply {
            isOpaque = true
            border = javax.swing.BorderFactory.createEmptyBorder(4, 4, 4, 4)
            isEditable = false
            val lineSpacing = SimpleAttributeSet()
            StyleConstants.setLineSpacing(lineSpacing, 0.4f)
            styledDocument.setParagraphAttributes(0, 0, lineSpacing, false)
        }
        private val lineSpacingAttr = SimpleAttributeSet().also {
            StyleConstants.setLineSpacing(it, 0.4f)
        }
        private val fallback = DefaultTableCellRenderer()

        override fun getTableCellRendererComponent(
            table: javax.swing.JTable,
            value: Any?,
            isSelected: Boolean,
            hasFocus: Boolean,
            row: Int,
            column: Int,
        ): Component {
            val text = value?.toString() ?: ""
            if (!text.contains("\n")) {
                return fallback.getTableCellRendererComponent(table, value, isSelected, hasFocus, row, column)
            }

            textPane.text = text
            textPane.font = table.font
            // Apply line spacing to all paragraphs
            val doc = textPane.styledDocument
            doc.setParagraphAttributes(0, doc.length, lineSpacingAttr, false)

            if (isSelected) {
                textPane.background = table.selectionBackground
                textPane.foreground = table.selectionForeground
            } else {
                textPane.background = table.background
                textPane.foreground = table.foreground
            }

            // Auto-adjust row height based on content
            val fontMetrics = table.getFontMetrics(table.font)
            val lineCount = text.count { it == '\n' } + 1
            val lineHeight = (fontMetrics.height * 1.4).toInt()
            val desiredHeight = (lineHeight * lineCount + 10).coerceAtLeast(table.rowHeight)
            if (table.getRowHeight(row) < desiredHeight) {
                table.setRowHeight(row, desiredHeight)
            }

            return textPane
        }
    }
}
