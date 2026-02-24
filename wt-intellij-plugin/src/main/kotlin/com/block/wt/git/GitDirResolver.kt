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

    /**
     * Resolves the main `.git` directory for a path (repo or linked worktree).
     * For a main repo, returns `<path>/.git`.
     * For a linked worktree (where gitdir points to `.git/worktrees/<name>`),
     * walks up from the worktree-specific git dir to find the `.git` parent.
     */
    fun resolveMainGitDir(path: Path): Path? {
        val gitDir = resolveGitDir(path) ?: return null
        // If it's already the main .git directory, return it
        if (gitDir.fileName?.toString() == ".git") return gitDir
        // For linked worktrees, gitDir is like .git/worktrees/<name>
        // Walk up to find the .git directory
        var dir = gitDir
        while (dir.parent != null) {
            if (dir.fileName?.toString() == ".git") return dir
            dir = dir.parent
        }
        return null
    }
}
