package com.block.wt.ui

import com.block.wt.model.WorktreeInfo
import com.block.wt.model.WorktreeStatus
import java.nio.file.Path
import javax.swing.table.AbstractTableModel

class WorktreeTableModel : AbstractTableModel() {

    private var worktrees: List<WorktreeInfo> = emptyList()
    var worktreesBase: Path? = null

    companion object {
        const val COL_LINKED = 0
        const val COL_PATH = 1
        const val COL_BRANCH = 2
        const val COL_STATUS = 3
        const val COL_AGENT = 4
        const val COL_PROVISIONED = 5

        val COLUMN_NAMES = arrayOf("", "Path", "Branch", "Status", "Agent", "Provisioned")
    }

    fun setWorktrees(newWorktrees: List<WorktreeInfo>) {
        worktrees = newWorktrees
        fireTableDataChanged()
    }

    fun getWorktreeAt(row: Int): WorktreeInfo? {
        return worktrees.getOrNull(row)
    }

    override fun getRowCount(): Int = worktrees.size

    override fun getColumnCount(): Int = COLUMN_NAMES.size

    override fun getColumnName(column: Int): String = COLUMN_NAMES[column]

    override fun getColumnClass(columnIndex: Int): Class<*> = String::class.java

    override fun getValueAt(rowIndex: Int, columnIndex: Int): Any? {
        val wt = worktrees.getOrNull(rowIndex) ?: return null
        return when (columnIndex) {
            COL_LINKED -> if (wt.isLinked) "*" else ""
            COL_PATH -> wt.relativePath(worktreesBase)
            COL_BRANCH -> buildString {
                append(wt.displayName)
                if (wt.isMain) append(" [main]")
            }
            COL_STATUS -> formatStatus(wt)
            COL_AGENT -> if (wt.hasActiveAgent) {
                "\uD83E\uDD16 " + wt.activeAgentSessionIds.joinToString(", ") { it.take(8) }
            } else ""
            COL_PROVISIONED -> when {
                wt.isProvisionedByCurrentContext -> "✓"
                wt.isProvisioned -> "~"
                else -> ""
            }
            else -> null
        }
    }

    private fun formatStatus(wt: WorktreeInfo): String {
        val status = wt.status
        if (status !is WorktreeStatus.Loaded) return ""

        val parts = mutableListOf<String>()

        // Local changes: ⚠conflicts ●staged ✱modified …untracked
        if (status.conflicts > 0) parts.add("\u26A0${status.conflicts}")
        if (status.staged > 0) parts.add("\u25CF${status.staged}")
        if (status.modified > 0) parts.add("\u2731${status.modified}")
        if (status.untracked > 0) parts.add("\u2026${status.untracked}")

        // Remote tracking: ↑ahead ↓behind
        status.ahead?.let { if (it > 0) parts.add("↑$it") }
        status.behind?.let { if (it > 0) parts.add("↓$it") }

        return parts.joinToString(" ")
    }
}
