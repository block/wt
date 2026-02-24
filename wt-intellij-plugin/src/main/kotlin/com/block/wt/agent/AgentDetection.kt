package com.block.wt.agent

import java.nio.file.Path

/**
 * Interface for detecting active Claude agent sessions.
 * Production implementation uses lsof and filesystem scanning;
 * test implementation returns canned responses.
 */
interface AgentDetection {
    fun detectActiveAgentDirs(): Set<Path>
    fun detectActiveSessionIds(worktreePath: Path): List<String>
}
