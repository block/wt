package com.block.wt.git

import com.block.wt.model.ContextConfig
import com.block.wt.util.PathHelper
import com.block.wt.util.ProcessHelper
import java.nio.file.Path

object GitConfigHelper {

    /**
     * Reads wt.* config from git local config (.git/config).
     * Uses `git config --local --get-regexp '^wt\.'` — the same command the shell CLI
     * uses in `wt_read_git_config()` (PR #23).
     * Returns null if wt.enabled is not true or any required key is missing (all-or-nothing).
     * For linked worktrees, reads from the main repo's .git/config (shared via gitdir pointer).
     */
    fun readConfig(repoOrWorktreePath: Path): ContextConfig? {
        val mainGitDir = GitDirResolver.resolveMainGitDir(repoOrWorktreePath) ?: return null
        val mainRepoRoot = mainGitDir.parent

        val result = ProcessHelper.runGit(
            listOf("config", "--local", "--get-regexp", "^wt\\."),
            workingDir = mainRepoRoot,
        )
        if (!result.isSuccess) return null

        // git config lowercases keys: "wt.worktreesbase" not "wt.worktreesBase"
        val values = result.stdout.lines()
            .filter { it.isNotBlank() }
            .associate { line ->
                val spaceIdx = line.indexOf(' ')
                if (spaceIdx < 0) return@associate line.lowercase() to ""
                line.substring(0, spaceIdx).lowercase() to line.substring(spaceIdx + 1)
            }

        if (values["wt.enabled"]?.equals("true", ignoreCase = true) != true) return null

        // All 3 required keys must be present (all-or-nothing, matching shell behavior)
        val worktreesBase = values["wt.worktreesbase"] ?: return null
        val ideaFilesBase = values["wt.ideafilesbase"] ?: return null
        val baseBranch = values["wt.basebranch"] ?: return null

        // Context name: prefer wt.contextName from git config; fall back to dirname derivation
        val name = values["wt.contextname"]
            ?: mainRepoRoot.fileName?.toString()
                ?.removeSuffix("-master")?.removeSuffix("-main")
            ?: return null

        // Optional keys
        val activeWorktreeStr = values["wt.activeworktree"]
        val metadataPatternsStr = values["wt.metadatapatterns"]

        return ContextConfig(
            name = name,
            mainRepoRoot = mainRepoRoot,
            worktreesBase = PathHelper.expandTilde(worktreesBase),
            ideaFilesBase = PathHelper.expandTilde(ideaFilesBase),
            baseBranch = baseBranch,
            activeWorktree = activeWorktreeStr?.let { PathHelper.expandTilde(it) }
                ?: mainRepoRoot,
            metadataPatterns = metadataPatternsStr
                ?.split(" ")?.filter { it.isNotBlank() }
                ?: emptyList(),
        )
    }

    /**
     * Writes wt.* config to git local config (.git/config).
     * Uses individual `git config --local wt.<key> <value>` calls.
     * Both the CLI (via _wt_write_git_config in lib/wt-context-setup) and the plugin
     * write wt.* keys to git local config. The key names and semantics are shared.
     */
    fun writeConfig(repoPath: Path, config: ContextConfig) {
        val mainGitDir = GitDirResolver.resolveMainGitDir(repoPath)
            ?: error("Not a git repo: $repoPath")
        val repoRoot = mainGitDir.parent

        fun gitSet(key: String, value: String) {
            ProcessHelper.runGit(listOf("config", "--local", key, value), workingDir = repoRoot)
        }

        gitSet("wt.enabled", "true")
        gitSet("wt.contextName", config.name)
        gitSet("wt.worktreesBase", config.worktreesBase.toString())
        gitSet("wt.ideaFilesBase", config.ideaFilesBase.toString())
        gitSet("wt.baseBranch", config.baseBranch)
        gitSet("wt.activeWorktree", config.activeWorktree.toString())
        if (config.metadataPatterns.isNotEmpty()) {
            gitSet("wt.metadataPatterns", config.metadataPatterns.joinToString(" "))
        } else {
            // --unset may fail if key doesn't exist — that's fine
            ProcessHelper.runGit(
                listOf("config", "--local", "--unset", "wt.metadataPatterns"),
                workingDir = repoRoot,
            )
        }
    }

    /**
     * Removes all wt.* config keys from git local config.
     * Used by re-provision and delete context actions.
     */
    fun removeAllConfig(repoPath: Path) {
        val mainGitDir = GitDirResolver.resolveMainGitDir(repoPath) ?: return
        val repoRoot = mainGitDir.parent
        // --remove-section may fail if [wt] section doesn't exist — that's fine
        ProcessHelper.runGit(listOf("config", "--local", "--remove-section", "wt"), workingDir = repoRoot)
    }

    /**
     * Quick check: is wt.enabled=true in git local config?
     * Uses `git config --local --get wt.enabled`.
     */
    fun isEnabled(repoOrWorktreePath: Path): Boolean {
        val mainGitDir = GitDirResolver.resolveMainGitDir(repoOrWorktreePath) ?: return false
        return try {
            val result = ProcessHelper.runGit(
                listOf("config", "--local", "--get", "wt.enabled"),
                workingDir = mainGitDir.parent,
            )
            result.isSuccess && result.stdout.trim().equals("true", ignoreCase = true)
        } catch (_: Exception) {
            false
        }
    }
}
