package com.block.wt.ui

import com.block.wt.model.PullRequestInfo
import com.block.wt.model.WorktreeInfo
import com.block.wt.model.WorktreeStatus
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.file.Path

class WorktreeTableModelTest {

    private fun makeWt(
        branch: String = "feature",
        status: WorktreeStatus = WorktreeStatus.NotLoaded,
        prInfo: PullRequestInfo = PullRequestInfo.NotLoaded,
        isMain: Boolean = false,
        isProvisioned: Boolean = false,
        isProvisionedByCurrentContext: Boolean = false,
        activeAgentSessionIds: List<String> = emptyList(),
    ) = WorktreeInfo(
        path = Path.of("/worktrees/feature"),
        branch = branch,
        head = "abc123",
        isMain = isMain,
        status = status,
        prInfo = prInfo,
        isProvisioned = isProvisioned,
        isProvisionedByCurrentContext = isProvisionedByCurrentContext,
        activeAgentSessionIds = activeAgentSessionIds,
    )

    private fun getValueAt(wt: WorktreeInfo, col: Int): Any? {
        val model = WorktreeTableModel()
        model.worktreesBase = Path.of("/worktrees")
        model.setWorktrees(listOf(wt))
        return model.getValueAt(0, col)
    }

    // --- formatStatus ---

    @Test
    fun testFormatStatusNotLoaded() {
        assertEquals("", getValueAt(makeWt(), WorktreeTableModel.COL_STATUS))
    }

    @Test
    fun testFormatStatusClean() {
        val status = WorktreeStatus.Loaded(0, 0, 0, 0, null, null)
        assertEquals("", getValueAt(makeWt(status = status), WorktreeTableModel.COL_STATUS))
    }

    @Test
    fun testFormatStatusAllCountsNonZero() {
        val status = WorktreeStatus.Loaded(staged = 3, modified = 2, untracked = 5, conflicts = 1, ahead = 4, behind = 6)
        val result = getValueAt(makeWt(status = status), WorktreeTableModel.COL_STATUS) as String
        assertEquals("\u26A01 \u25CF3 \u27312 \u20265 \u21914 \u21936", result)
    }

    @Test
    fun testFormatStatusStagedOnly() {
        val status = WorktreeStatus.Loaded(staged = 2, modified = 0, untracked = 0, conflicts = 0, ahead = null, behind = null)
        assertEquals("\u25CF2", getValueAt(makeWt(status = status), WorktreeTableModel.COL_STATUS))
    }

    @Test
    fun testFormatStatusAheadBehindOnly() {
        val status = WorktreeStatus.Loaded(staged = 0, modified = 0, untracked = 0, conflicts = 0, ahead = 3, behind = 1)
        assertEquals("\u21913 \u21931", getValueAt(makeWt(status = status), WorktreeTableModel.COL_STATUS))
    }

    @Test
    fun testFormatStatusZeroAheadBehindNotShown() {
        val status = WorktreeStatus.Loaded(staged = 0, modified = 0, untracked = 0, conflicts = 0, ahead = 0, behind = 0)
        assertEquals("", getValueAt(makeWt(status = status), WorktreeTableModel.COL_STATUS))
    }

    // --- formatPR ---

    @Test
    fun testFormatPRNotLoaded() {
        assertEquals("", getValueAt(makeWt(), WorktreeTableModel.COL_PR))
    }

    @Test
    fun testFormatPRNoPR() {
        assertEquals("Create PR", getValueAt(makeWt(prInfo = PullRequestInfo.NoPR), WorktreeTableModel.COL_PR))
    }

    @Test
    fun testFormatPROpen() {
        val pr = PullRequestInfo.Open(42, "https://github.com/o/r/pull/42", "Fix bug")
        assertEquals("#42", getValueAt(makeWt(prInfo = pr), WorktreeTableModel.COL_PR))
    }

    @Test
    fun testFormatPRDraft() {
        val pr = PullRequestInfo.Draft(10, "url", "WIP")
        assertEquals("#10", getValueAt(makeWt(prInfo = pr), WorktreeTableModel.COL_PR))
    }

    @Test
    fun testFormatPRMerged() {
        val pr = PullRequestInfo.Merged(5, "url", "Done")
        assertEquals("#5", getValueAt(makeWt(prInfo = pr), WorktreeTableModel.COL_PR))
    }

    @Test
    fun testFormatPRClosed() {
        val pr = PullRequestInfo.Closed(7, "url", "Nope")
        assertEquals("#7", getValueAt(makeWt(prInfo = pr), WorktreeTableModel.COL_PR))
    }

    // --- getValueAt column coverage ---

    @Test
    fun testColumnPath() {
        assertEquals("feature", getValueAt(makeWt(), WorktreeTableModel.COL_PATH))
    }

    @Test
    fun testColumnBranch() {
        assertEquals("feature", getValueAt(makeWt(), WorktreeTableModel.COL_BRANCH))
    }

    @Test
    fun testColumnBranchMain() {
        assertEquals("main [main]", getValueAt(makeWt(branch = "main", isMain = true), WorktreeTableModel.COL_BRANCH))
    }

    @Test
    fun testColumnAgentNoAgent() {
        assertEquals("", getValueAt(makeWt(), WorktreeTableModel.COL_AGENT))
    }

    @Test
    fun testColumnAgentWithSessions() {
        val wt = makeWt(activeAgentSessionIds = listOf("session-abc-def-123", "session-xyz-456-789"))
        val result = getValueAt(wt, WorktreeTableModel.COL_AGENT) as String
        assertTrue(result.contains("session-"))
        assertTrue(result.contains(", "))
    }

    @Test
    fun testColumnAgentTruncatesSessionIds() {
        val wt = makeWt(activeAgentSessionIds = listOf("abcdefghijklmnop"))
        val result = getValueAt(wt, WorktreeTableModel.COL_AGENT) as String
        assertTrue(result.contains("abcdefgh"))
        assertFalse(result.contains("ijklmnop"))
    }

    @Test
    fun testColumnProvisionedByContext() {
        val wt = makeWt(isProvisioned = true, isProvisionedByCurrentContext = true)
        assertEquals("\u2713", getValueAt(wt, WorktreeTableModel.COL_PROVISIONED))
    }

    @Test
    fun testColumnProvisionedByOtherContext() {
        val wt = makeWt(isProvisioned = true, isProvisionedByCurrentContext = false)
        assertEquals("~", getValueAt(wt, WorktreeTableModel.COL_PROVISIONED))
    }

    @Test
    fun testColumnNotProvisioned() {
        assertEquals("", getValueAt(makeWt(), WorktreeTableModel.COL_PROVISIONED))
    }

    private fun assertTrue(condition: Boolean) = org.junit.Assert.assertTrue(condition)
    private fun assertFalse(condition: Boolean) = org.junit.Assert.assertFalse(condition)
}
