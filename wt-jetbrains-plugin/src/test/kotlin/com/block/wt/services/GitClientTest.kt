package com.block.wt.services

import com.block.wt.testutil.FakeProcessRunner
import com.block.wt.util.ProcessHelper.ProcessResult
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Path

class GitClientTest {

    private val wtPath = Path.of("/test/wt")
    private val repoRoot = Path.of("/test/repo")

    // --- getMergedBranches ---

    @Test
    fun testGetMergedBranchesParsesBranchOutput() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "branch", "--merged", "main") to ProcessResult(
                    0,
                    "  feature/done\n  bugfix/fixed\n* main\n  other\n",
                    "",
                ),
            ),
        )
        val client = GitClient(runner)
        val result = client.getMergedBranches(repoRoot, "main")
        assertEquals(listOf("feature/done", "bugfix/fixed", "other"), result)
    }

    @Test
    fun testGetMergedBranchesFiltersBaseBranch() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "branch", "--merged", "main") to ProcessResult(0, "  main\n  feature\n", ""),
            ),
        )
        val client = GitClient(runner)
        val result = client.getMergedBranches(repoRoot, "main")
        assertEquals(listOf("feature"), result)
    }

    @Test
    fun testGetMergedBranchesStripsCurrentBranchMarker() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "branch", "--merged", "main") to ProcessResult(0, "* current\n  other\n", ""),
            ),
        )
        val client = GitClient(runner)
        val result = client.getMergedBranches(repoRoot, "main")
        assertEquals(listOf("current", "other"), result)
    }

    @Test
    fun testGetMergedBranchesReturnsEmptyOnFailure() = runBlocking {
        val client = GitClient(FakeProcessRunner())
        val result = client.getMergedBranches(repoRoot, "main")
        assertTrue(result.isEmpty())
    }

    @Test
    fun testGetMergedBranchesFiltersBlankLines() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "branch", "--merged", "main") to ProcessResult(0, "  feature\n\n  other\n\n", ""),
            ),
        )
        val client = GitClient(runner)
        val result = client.getMergedBranches(repoRoot, "main")
        assertEquals(listOf("feature", "other"), result)
    }

    // --- stashPop ---

    @Test
    fun testStashPopFindsStashByName() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "stash", "list") to ProcessResult(
                    0,
                    "stash@{0}: On main: unrelated\nstash@{1}: On main: wt-save-feature\nstash@{2}: On main: other\n",
                    "",
                ),
                listOf("git", "stash", "pop", "stash@{1}") to ProcessResult(0, "", ""),
            ),
        )
        val client = GitClient(runner)
        val result = client.stashPop(wtPath, "wt-save-feature")
        assertTrue(result.isSuccess)
    }

    @Test
    fun testStashPopFindsStashAtIndex0() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "stash", "list") to ProcessResult(
                    0,
                    "stash@{0}: On main: wt-save-feature\n",
                    "",
                ),
                listOf("git", "stash", "pop", "stash@{0}") to ProcessResult(0, "", ""),
            ),
        )
        val client = GitClient(runner)
        val result = client.stashPop(wtPath, "wt-save-feature")
        assertTrue(result.isSuccess)
    }

    @Test
    fun testStashPopReturnsSuccessWhenNotFound() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "stash", "list") to ProcessResult(0, "stash@{0}: On main: other\n", ""),
            ),
        )
        val client = GitClient(runner)
        val result = client.stashPop(wtPath, "wt-save-feature")
        assertTrue(result.isSuccess)
    }

    @Test
    fun testStashPopReturnsSuccessWhenStashListEmpty() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "stash", "list") to ProcessResult(0, "", ""),
            ),
        )
        val client = GitClient(runner)
        val result = client.stashPop(wtPath, "wt-save-feature")
        assertTrue(result.isSuccess)
    }

    @Test
    fun testStashPopReturnsFailureWhenListFails() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "stash", "list") to ProcessResult(1, "", "fatal: error"),
            ),
        )
        val client = GitClient(runner)
        val result = client.stashPop(wtPath, "wt-save-feature")
        assertTrue(result.isFailure)
    }

    @Test
    fun testStashPopReturnsFailureWhenPopFails() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "stash", "list") to ProcessResult(
                    0,
                    "stash@{0}: On main: wt-save-feature\n",
                    "",
                ),
                listOf("git", "stash", "pop", "stash@{0}") to ProcessResult(1, "", "CONFLICT"),
            ),
        )
        val client = GitClient(runner)
        val result = client.stashPop(wtPath, "wt-save-feature")
        assertTrue(result.isFailure)
    }

    // --- getCurrentBranch ---

    @Test
    fun testGetCurrentBranchReturnsBranchName() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "rev-parse", "--abbrev-ref", "HEAD") to ProcessResult(0, "feature/foo\n", ""),
            ),
        )
        val client = GitClient(runner)
        assertEquals("feature/foo", client.getCurrentBranch(wtPath))
    }

    @Test
    fun testGetCurrentBranchReturnsNullOnBlankOutput() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "rev-parse", "--abbrev-ref", "HEAD") to ProcessResult(0, "  \n", ""),
            ),
        )
        val client = GitClient(runner)
        assertNull(client.getCurrentBranch(wtPath))
    }

    @Test
    fun testGetCurrentBranchReturnsNullOnFailure() = runBlocking {
        val client = GitClient(FakeProcessRunner())
        assertNull(client.getCurrentBranch(wtPath))
    }

    // --- hasUncommittedChanges ---

    @Test
    fun testHasUncommittedChangesReturnsTrueWhenDirty() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "status", "--porcelain") to ProcessResult(0, " M file.txt\n", ""),
            ),
        )
        val client = GitClient(runner)
        assertTrue(client.hasUncommittedChanges(wtPath))
    }

    @Test
    fun testHasUncommittedChangesReturnsFalseWhenClean() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(
                listOf("git", "status", "--porcelain") to ProcessResult(0, "", ""),
            ),
        )
        val client = GitClient(runner)
        assertFalse(client.hasUncommittedChanges(wtPath))
    }

    @Test
    fun testHasUncommittedChangesReturnsFalseOnFailure() = runBlocking {
        val client = GitClient(FakeProcessRunner())
        assertFalse(client.hasUncommittedChanges(wtPath))
    }
}
