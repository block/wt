package com.block.wt.git

import java.nio.file.Files
import java.nio.file.Path

object GitDirResolver {

    /**
     * Resolves the git directory for a worktree path.
     * For main worktrees this is `<path>/.git/`, for linked worktrees it follows
     * the `.git` file pointer (e.g. `gitdir: /path/to/.git/worktrees/<name>`).
     */
    fun resolveGitDir(worktreePath: Path): Path? {
        val dotGit = worktreePath.resolve(".git")
        return when {
            Files.isDirectory(dotGit) -> dotGit
            Files.isRegularFile(dotGit) -> try {
                // Linked worktree: .git is a file containing "gitdir: <path>"
                val content = Files.readString(dotGit).trim()
                if (!content.startsWith("gitdir: ")) return null
                val gitDirStr = content.removePrefix("gitdir: ")
                val gitDir = Path.of(gitDirStr)
                if (gitDir.isAbsolute) gitDir else worktreePath.resolve(gitDir).normalize()
            } catch (_: Exception) {
                null
            }
            else -> null
        }
    }
}
