package com.block.wt.services

import com.block.wt.git.GitParser
import com.block.wt.model.WorktreeInfo
import com.block.wt.model.WorktreeStatus
import com.block.wt.testutil.FakeAgentDetection
import com.block.wt.testutil.FakeProcessRunner
import com.block.wt.util.ProcessHelper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Path

class WorktreeServiceTest {

    @Test
    fun testParseValidPorcelainOutput() {
        val output = """
            worktree /Users/test/repo
            HEAD abc123def456
            branch refs/heads/main

            worktree /Users/test/worktrees/feature
            HEAD def456abc123
            branch refs/heads/feature/foo

        """.trimIndent()

        val result = GitParser.parsePorcelainOutput(output)
        assertEquals(2, result.size)

        assertEquals(Path.of("/Users/test/repo"), result[0].path)
        assertEquals("main", result[0].branch)
        assertTrue(result[0].isMain)

        assertEquals(Path.of("/Users/test/worktrees/feature"), result[1].path)
        assertEquals("feature/foo", result[1].branch)
        assertFalse(result[1].isMain)
    }

    @Test
    fun testParseEmptyOutputReturnsEmptyList() {
        val result = GitParser.parsePorcelainOutput("")
        assertTrue(result.isEmpty())
    }

    @Test
    fun testParseMalformedOutputReturnsEmptyList() {
        val result = GitParser.parsePorcelainOutput("garbage\ndata\nhere")
        assertTrue(result.isEmpty())
    }

    @Test
    fun testAgentEnrichmentWithActiveAgents() {
        val featurePath = Path.of("/Users/test/worktrees/feature")
        val agentDetection = FakeAgentDetection(
            activeDirs = setOf(featurePath),
            sessionIds = mapOf(featurePath to listOf("session-abc", "session-def")),
        )

        val worktrees = listOf(
            WorktreeInfo(
                path = Path.of("/Users/test/repo"),
                branch = "main",
                head = "abc123",
                isMain = true,
            ),
            WorktreeInfo(
                path = featurePath,
                branch = "feature/foo",
                head = "def456",
            ),
        )

        val enriched = enrichAgentStatusWith(worktrees, agentDetection)

        assertFalse(enriched[0].hasActiveAgent)
        assertTrue(enriched[0].activeAgentSessionIds.isEmpty())

        assertTrue(enriched[1].hasActiveAgent)
        assertEquals(listOf("session-abc", "session-def"), enriched[1].activeAgentSessionIds)
    }

    @Test
    fun testAgentEnrichmentWithNoAgents() {
        val agentDetection = FakeAgentDetection()

        val worktrees = listOf(
            WorktreeInfo(
                path = Path.of("/Users/test/repo"),
                branch = "main",
                head = "abc123",
            ),
        )

        val enriched = enrichAgentStatusWith(worktrees, agentDetection)
        assertFalse(enriched[0].hasActiveAgent)
    }

    @Test
    fun testFakeProcessRunnerReturnsConfiguredResponses() {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "worktree", "list", "--porcelain") to ProcessHelper.ProcessResult(
                    exitCode = 0,
                    stdout = "worktree /test\nHEAD abc123\nbranch refs/heads/main\n",
                    stderr = "",
                ),
            ),
        )

        val result = runner.runGit(listOf("worktree", "list", "--porcelain"))
        assertTrue(result.isSuccess)
        assertTrue(result.stdout.contains("worktree /test"))
    }

    @Test
    fun testFakeProcessRunnerReturnsFailureForUnknownCommands() {
        val runner = FakeProcessRunner()
        val result = runner.runGit(listOf("unknown", "command"))
        assertFalse(result.isSuccess)
    }

    // --- parseGitStatusOutput tests ---

    private fun makeWt() = WorktreeInfo(
        path = Path.of("/test/wt"),
        branch = "feature",
        head = "abc123",
    )

    private fun parseStatus(output: String): WorktreeStatus.Loaded {
        val result = parseGitStatus(makeWt(), output)
        return result.status as WorktreeStatus.Loaded
    }

    @Test
    fun testParseGitStatusEmpty() {
        val status = parseStatus("")
        assertEquals(0, status.staged)
        assertEquals(0, status.modified)
        assertEquals(0, status.untracked)
        assertEquals(0, status.conflicts)
        assertNull(status.ahead)
        assertNull(status.behind)
    }

    @Test
    fun testParseGitStatusAheadOnly() {
        val status = parseStatus("## main...origin/main [ahead 3]\n")
        assertEquals(3, status.ahead)
        assertNull(status.behind)
    }

    @Test
    fun testParseGitStatusBehindOnly() {
        val status = parseStatus("## main...origin/main [behind 2]\n")
        assertNull(status.ahead)
        assertEquals(2, status.behind)
    }

    @Test
    fun testParseGitStatusAheadAndBehind() {
        val status = parseStatus("## main...origin/main [ahead 1, behind 2]\n")
        assertEquals(1, status.ahead)
        assertEquals(2, status.behind)
    }

    @Test
    fun testParseGitStatusNoTrackingInfo() {
        val status = parseStatus("## main\n")
        assertNull(status.ahead)
        assertNull(status.behind)
    }

    @Test
    fun testParseGitStatusStagedFiles() {
        val output = """
            ## main...origin/main
            M  staged.txt
            A  added.txt
            D  deleted.txt
            R  renamed.txt
            C  copied.txt
        """.trimIndent()
        val status = parseStatus(output)
        assertEquals(5, status.staged)
        assertEquals(0, status.modified)
    }

    @Test
    fun testParseGitStatusModifiedUnstaged() {
        val output = """
            ## main...origin/main
             M unstaged.txt
             D deleted-unstaged.txt
        """.trimIndent()
        val status = parseStatus(output)
        assertEquals(0, status.staged)
        assertEquals(2, status.modified)
    }

    @Test
    fun testParseGitStatusUntracked() {
        val output = """
            ## main
            ?? file1.txt
            ?? file2.txt
        """.trimIndent()
        val status = parseStatus(output)
        assertEquals(2, status.untracked)
    }

    @Test
    fun testParseGitStatusConflicts() {
        val output = """
            ## main...origin/main
            UU both-modified.txt
            AA both-added.txt
            DD both-deleted.txt
            AU added-by-us.txt
            UA added-by-them.txt
            DU deleted-by-us.txt
            UD deleted-by-them.txt
        """.trimIndent()
        val status = parseStatus(output)
        assertEquals(7, status.conflicts)
        assertEquals(0, status.staged)
    }

    @Test
    fun testParseGitStatusMixed() {
        val output = """
            ## feature...origin/feature [ahead 2, behind 1]
            M  staged.txt
             M unstaged.txt
            ?? untracked.txt
            UU conflict.txt
        """.trimIndent()
        val status = parseStatus(output)
        assertEquals(1, status.staged)
        assertEquals(1, status.modified)
        assertEquals(1, status.untracked)
        assertEquals(1, status.conflicts)
        assertEquals(2, status.ahead)
        assertEquals(1, status.behind)
    }

    @Test
    fun testParseGitStatusBothStagedAndModified() {
        // MM = staged in index, modified in working tree
        val output = """
            ## main
            MM file.txt
        """.trimIndent()
        val status = parseStatus(output)
        assertEquals(1, status.staged)
        assertEquals(1, status.modified)
    }

    /**
     * Mirrors WorktreeService.enrichAgentStatus using a given AgentDetection.
     * Allows testing agent enrichment without a Project/service.
     */
    private fun enrichAgentStatusWith(
        worktrees: List<WorktreeInfo>,
        agentDetection: FakeAgentDetection,
    ): List<WorktreeInfo> {
        val agentDirs = agentDetection.detectActiveAgentDirs()
        return worktrees.map { wt ->
            val hasAgent = agentDirs.any { agentDir ->
                agentDir == wt.path
            }
            val sessionIds = if (hasAgent) agentDetection.detectActiveSessionIds(wt.path) else emptyList()
            wt.copy(activeAgentSessionIds = sessionIds)
        }
    }
}
