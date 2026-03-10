package com.block.wt.services

import com.block.wt.model.PullRequestInfo
import com.block.wt.model.WorktreeInfo
import com.block.wt.testutil.FakeProcessRunner
import com.block.wt.util.ProcessHelper
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Path

class PullRequestLoaderTest {

    // --- parseRepoSlug tests ---

    private val loader = PullRequestLoader(FakeProcessRunner())

    @Test
    fun testParseRepoSlugSshWithGit() {
        assertEquals("owner/repo", loader.parseRepoSlug("git@github.com:owner/repo.git"))
    }

    @Test
    fun testParseRepoSlugSshWithoutGit() {
        assertEquals("owner/repo", loader.parseRepoSlug("git@github.com:owner/repo"))
    }

    @Test
    fun testParseRepoSlugHttpsWithGit() {
        assertEquals("owner/repo", loader.parseRepoSlug("https://github.com/owner/repo.git"))
    }

    @Test
    fun testParseRepoSlugHttpsWithoutGit() {
        assertEquals("owner/repo", loader.parseRepoSlug("https://github.com/owner/repo"))
    }

    @Test
    fun testParseRepoSlugHttp() {
        assertEquals("owner/repo", loader.parseRepoSlug("http://github.com/owner/repo"))
    }

    @Test
    fun testParseRepoSlugUnrecognized() {
        assertNull(loader.parseRepoSlug("not-a-url"))
    }

    @Test
    fun testParseRepoSlugEmpty() {
        assertNull(loader.parseRepoSlug(""))
    }

    // --- loadPRInfo tests ---

    private fun makeWt(
        branch: String? = "feature",
        isMain: Boolean = false,
    ) = WorktreeInfo(
        path = Path.of("/test/wt"),
        branch = branch,
        head = "abc123",
        isMain = isMain,
    )

    private fun ghCommand(branch: String) = listOf(
        "gh", "pr", "list", "--head", branch, "--state", "all",
        "--json", "number,url,title,state,isDraft", "--limit", "1",
    )

    @Test
    fun testLoadPRInfoNullBranch() = runBlocking {
        val loader = PullRequestLoader(FakeProcessRunner())
        val result = loader.loadPRInfo(makeWt(branch = null))
        assertEquals(PullRequestInfo.NoPR, result)
    }

    @Test
    fun testLoadPRInfoMainBranch() = runBlocking {
        val loader = PullRequestLoader(FakeProcessRunner())
        val result = loader.loadPRInfo(makeWt(isMain = true))
        assertEquals(PullRequestInfo.NoPR, result)
    }

    @Test
    fun testLoadPRInfoOpenPR() = runBlocking {
        val json = """[{"number":42,"url":"https://github.com/o/r/pull/42","title":"Fix bug","state":"OPEN","isDraft":false}]"""
        val runner = FakeProcessRunner(
            responses = mapOf(ghCommand("feature") to ProcessHelper.ProcessResult(0, json, "")),
        )
        val result = PullRequestLoader(runner).loadPRInfo(makeWt())
        assertTrue(result is PullRequestInfo.Open)
        assertEquals(42, (result as PullRequestInfo.Open).number)
        assertEquals("Fix bug", result.title)
    }

    @Test
    fun testLoadPRInfoDraftPR() = runBlocking {
        val json = """[{"number":10,"url":"https://github.com/o/r/pull/10","title":"WIP","state":"OPEN","isDraft":true}]"""
        val runner = FakeProcessRunner(
            responses = mapOf(ghCommand("feature") to ProcessHelper.ProcessResult(0, json, "")),
        )
        val result = PullRequestLoader(runner).loadPRInfo(makeWt())
        assertTrue(result is PullRequestInfo.Draft)
    }

    @Test
    fun testLoadPRInfoMergedPR() = runBlocking {
        val json = """[{"number":5,"url":"https://github.com/o/r/pull/5","title":"Done","state":"MERGED","isDraft":false}]"""
        val runner = FakeProcessRunner(
            responses = mapOf(ghCommand("feature") to ProcessHelper.ProcessResult(0, json, "")),
        )
        val result = PullRequestLoader(runner).loadPRInfo(makeWt())
        assertTrue(result is PullRequestInfo.Merged)
    }

    @Test
    fun testLoadPRInfoClosedPR() = runBlocking {
        val json = """[{"number":7,"url":"https://github.com/o/r/pull/7","title":"Nope","state":"CLOSED","isDraft":false}]"""
        val runner = FakeProcessRunner(
            responses = mapOf(ghCommand("feature") to ProcessHelper.ProcessResult(0, json, "")),
        )
        val result = PullRequestLoader(runner).loadPRInfo(makeWt())
        assertTrue(result is PullRequestInfo.Closed)
    }

    @Test
    fun testLoadPRInfoEmptyArray() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(ghCommand("feature") to ProcessHelper.ProcessResult(0, "[]", "")),
        )
        val result = PullRequestLoader(runner).loadPRInfo(makeWt())
        assertEquals(PullRequestInfo.NoPR, result)
    }

    @Test
    fun testLoadPRInfoGhFailure() = runBlocking {
        val runner = FakeProcessRunner(
            responses = mapOf(ghCommand("feature") to ProcessHelper.ProcessResult(1, "", "error")),
        )
        val result = PullRequestLoader(runner).loadPRInfo(makeWt())
        assertEquals(PullRequestInfo.NotLoaded, result)
    }
}
