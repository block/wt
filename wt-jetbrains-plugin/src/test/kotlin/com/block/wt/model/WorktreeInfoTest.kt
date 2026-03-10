package com.block.wt.model

import com.block.wt.git.GitBranchHelper
import com.block.wt.git.GitParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Path

class WorktreeInfoTest {

    @Test
    fun testParsePorcelainBasic() {
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

        val main = result[0]
        assertEquals(Path.of("/Users/test/repo"), main.path)
        assertEquals("main", main.branch)
        assertEquals("abc123def456", main.head)
        assertTrue(main.isMain)

        val feature = result[1]
        assertEquals(Path.of("/Users/test/worktrees/feature"), feature.path)
        assertEquals("feature/foo", feature.branch)
        assertFalse(feature.isMain)
    }

    @Test
    fun testParsePorcelainDetachedHead() {
        val output = """
            worktree /Users/test/repo
            HEAD abc123
            branch refs/heads/main

            worktree /Users/test/worktrees/detached
            HEAD def456
            detached

        """.trimIndent()

        val result = GitParser.parsePorcelainOutput(output)
        assertEquals(2, result.size)

        val detached = result[1]
        assertNull(detached.branch)
        assertEquals("def456", detached.head)
    }

    @Test
    fun testParsePorcelainPrunable() {
        val output = """
            worktree /Users/test/repo
            HEAD abc123
            branch refs/heads/main

            worktree /Users/test/worktrees/old
            HEAD def456
            branch refs/heads/old-branch
            prunable

        """.trimIndent()

        val result = GitParser.parsePorcelainOutput(output)
        assertEquals(2, result.size)
        assertTrue(result[1].isPrunable)
    }

    @Test
    fun testParsePorcelainEmpty() {
        val result = GitParser.parsePorcelainOutput("")
        assertTrue(result.isEmpty())
    }

    @Test
    fun testParsePorcelainWithLinkedWorktree() {
        val output = """
            worktree /Users/test/repo
            HEAD abc123
            branch refs/heads/main

            worktree /Users/test/worktrees/feature
            HEAD def456
            branch refs/heads/feature

        """.trimIndent()

        val result = GitParser.parsePorcelainOutput(
            output,
            linkedWorktreePath = Path.of("/Users/test/worktrees/feature")
        )
        assertEquals(2, result.size)
        assertFalse(result[0].isLinked)
        assertTrue(result[1].isLinked)
    }

    @Test
    fun testDisplayName() {
        val withBranch = WorktreeInfo(
            path = Path.of("/test"),
            branch = "feature/foo",
            head = "abc123",
        )
        assertEquals("feature/foo", withBranch.displayName)

        val detached = WorktreeInfo(
            path = Path.of("/test2"),
            branch = null,
            head = "abc123def456",
        )
        assertEquals("abc123de", detached.displayName)
    }

    @Test
    fun testHasActiveAgentDerived() {
        val noAgent = WorktreeInfo(
            path = Path.of("/test"),
            branch = "main",
            head = "abc123",
        )
        assertFalse(noAgent.hasActiveAgent)

        val withAgent = WorktreeInfo(
            path = Path.of("/test2"),
            branch = "main",
            head = "abc123",
            activeAgentSessionIds = listOf("session-1", "session-2"),
        )
        assertTrue(withAgent.hasActiveAgent)
    }

    @Test
    fun testIsDirtyWithNotLoaded() {
        val wt = WorktreeInfo(
            path = Path.of("/test"),
            branch = "main",
            head = "abc123",
        )
        assertNull(wt.isDirty)
    }

    @Test
    fun testIsDirtyWithCleanStatus() {
        val wt = WorktreeInfo(
            path = Path.of("/test"),
            branch = "main",
            head = "abc123",
            status = WorktreeStatus.Loaded(
                staged = 0, modified = 0, untracked = 0, conflicts = 0,
                ahead = null, behind = null,
            ),
        )
        assertEquals(false, wt.isDirty)
    }

    @Test
    fun testIsDirtyWithDirtyStatus() {
        val wt = WorktreeInfo(
            path = Path.of("/test"),
            branch = "main",
            head = "abc123",
            status = WorktreeStatus.Loaded(
                staged = 2, modified = 1, untracked = 0, conflicts = 0,
                ahead = null, behind = null,
            ),
        )
        assertEquals(true, wt.isDirty)
    }

    @Test
    fun testWorktreeStatusLoadedIsDirty() {
        val clean = WorktreeStatus.Loaded(staged = 0, modified = 0, untracked = 0, conflicts = 0, ahead = null, behind = null)
        assertFalse(clean.isDirty)

        val dirty = WorktreeStatus.Loaded(staged = 1, modified = 0, untracked = 0, conflicts = 0, ahead = null, behind = null)
        assertTrue(dirty.isDirty)
    }

    @Test
    fun testSanitizeBranchName() {
        assertEquals("feature/foo", GitBranchHelper.sanitizeBranchName("feature/foo"))
        assertEquals("simple", GitBranchHelper.sanitizeBranchName("  simple  "))
    }

    @Test(expected = IllegalArgumentException::class)
    fun testSanitizeBranchNamePathTraversal() {
        GitBranchHelper.sanitizeBranchName("../evil")
    }

    @Test(expected = IllegalArgumentException::class)
    fun testSanitizeBranchNameBlank() {
        GitBranchHelper.sanitizeBranchName("  ")
    }

    @Test(expected = IllegalArgumentException::class)
    fun testSanitizeBranchNameDash() {
        GitBranchHelper.sanitizeBranchName("-flag")
    }

    @Test(expected = IllegalArgumentException::class)
    fun testSanitizeBranchNameDashWithLeadingWhitespace() {
        GitBranchHelper.sanitizeBranchName(" -flag")
    }

    @Test
    fun testWorktreePathForBranch() {
        val base = Path.of("/worktrees")
        assertEquals(
            Path.of("/worktrees/feature-foo"),
            GitBranchHelper.worktreePathForBranch(base, "feature/foo")
        )
        assertEquals(
            Path.of("/worktrees/simple"),
            GitBranchHelper.worktreePathForBranch(base, "simple")
        )
    }
}
