package com.block.wt.testutil

import com.block.wt.agent.AgentDetection
import java.nio.file.Path

class FakeAgentDetection(
    private val activeDirs: Set<Path> = emptySet(),
    private val sessionIds: Map<Path, List<String>> = emptyMap(),
) : AgentDetection {

    override fun detectActiveAgentDirs(): Set<Path> = activeDirs

    override fun detectActiveSessionIds(worktreePath: Path): List<String> =
        sessionIds[worktreePath] ?: emptyList()
}
