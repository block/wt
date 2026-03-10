package com.block.wt.agent

import java.nio.file.Files
import java.nio.file.Path

/** Shared resolution of Claude Code session directories and files. */
object ClaudeSessionPaths {

    private const val CLAUDE_PROJECTS_DIR = ".claude/projects"
    private val NON_ALNUM = Regex("[^a-zA-Z0-9]")

    /** Returns the Claude projects dir for [worktreePath], or null if it doesn't exist. */
    fun resolveProjectDir(worktreePath: Path): Path? {
        val projectsDir = Path.of(System.getProperty("user.home")).resolve(CLAUDE_PROJECTS_DIR)
        if (!Files.isDirectory(projectsDir)) return null
        val encoded = NON_ALNUM.replace(worktreePath.toString(), "-")
        val dir = projectsDir.resolve(encoded)
        return if (Files.isDirectory(dir)) dir else null
    }

    /** Returns the `.jsonl` session file for [sessionId], or null if not found. */
    fun resolveSessionFile(worktreePath: Path, sessionId: String): Path? {
        val dir = resolveProjectDir(worktreePath) ?: return null
        val file = dir.resolve("$sessionId.jsonl")
        return if (Files.isRegularFile(file)) file else null
    }
}
