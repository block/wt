package com.block.wt.services

import com.block.wt.model.PullRequestInfo
import com.block.wt.model.WorktreeInfo
import com.block.wt.util.ProcessRunner
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.intellij.openapi.diagnostic.Logger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.file.Path

/**
 * Loads GitHub PR info for worktree branches via the `gh` CLI.
 */
class PullRequestLoader(private val processRunner: ProcessRunner) {

    private val log = Logger.getInstance(PullRequestLoader::class.java)
    private val gson = Gson()

    private data class GhPrEntry(
        val number: Int = 0,
        val url: String = "",
        val title: String = "",
        val state: String = "",
        val isDraft: Boolean = false,
    )

    suspend fun loadPRInfo(wt: WorktreeInfo): PullRequestInfo = withContext(Dispatchers.IO) {
        val branch = wt.branch ?: return@withContext PullRequestInfo.NoPR
        if (wt.isMain) return@withContext PullRequestInfo.NoPR

        try {
            val result = processRunner.run(
                listOf("gh", "pr", "list", "--head", branch, "--state", "all", "--json", "number,url,title,state,isDraft", "--limit", "1"),
                workingDir = wt.path,
            )
            if (!result.isSuccess) {
                log.debug("gh pr list failed for branch $branch: ${result.stderr.trim()}")
                return@withContext PullRequestInfo.NotLoaded
            }

            val output = result.stdout.trim()
            if (output == "[]" || output.isEmpty()) {
                return@withContext PullRequestInfo.NoPR
            }

            val listType = object : TypeToken<List<GhPrEntry>>() {}.type
            val entries: List<GhPrEntry> = gson.fromJson(output, listType)
            val pr = entries.firstOrNull() ?: return@withContext PullRequestInfo.NoPR

            when {
                pr.isDraft -> PullRequestInfo.Draft(pr.number, pr.url, pr.title)
                pr.state.equals("OPEN", ignoreCase = true) -> PullRequestInfo.Open(pr.number, pr.url, pr.title)
                pr.state.equals("MERGED", ignoreCase = true) -> PullRequestInfo.Merged(pr.number, pr.url, pr.title)
                pr.state.equals("CLOSED", ignoreCase = true) -> PullRequestInfo.Closed(pr.number, pr.url, pr.title)
                else -> PullRequestInfo.Open(pr.number, pr.url, pr.title)
            }
        } catch (e: Exception) {
            log.debug("Failed to load PR info for branch $branch", e)
            PullRequestInfo.NotLoaded
        }
    }

    fun detectRepoSlug(repoRoot: Path): String? {
        try {
            val result = processRunner.runGit(listOf("remote", "get-url", "origin"), workingDir = repoRoot)
            if (!result.isSuccess) return null
            return parseRepoSlug(result.stdout.trim())
        } catch (e: Exception) {
            log.debug("Failed to detect repo slug", e)
            return null
        }
    }

    internal fun parseRepoSlug(remoteUrl: String): String? {
        // SSH: git@github.com:owner/repo.git
        val sshMatch = Regex("""git@[^:]+:(.+?)(?:\.git)?$""").find(remoteUrl)
        if (sshMatch != null) return sshMatch.groupValues[1]

        // HTTPS: https://github.com/owner/repo.git
        val httpsMatch = Regex("""https?://[^/]+/(.+?)(?:\.git)?$""").find(remoteUrl)
        if (httpsMatch != null) return httpsMatch.groupValues[1]

        return null
    }
}
