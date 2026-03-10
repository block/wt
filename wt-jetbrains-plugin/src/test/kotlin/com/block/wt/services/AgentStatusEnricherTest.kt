package com.block.wt.services

import com.block.wt.model.WorktreeInfo
import com.block.wt.testutil.FakeAgentDetection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Path

class AgentStatusEnricherTest {

    private val featurePath = Path.of("/worktrees/feature")
    private val mainPath = Path.of("/worktrees/main")

    private fun makeWt(path: Path = featurePath, branch: String = "feature") = WorktreeInfo(
        path = path,
        branch = branch,
        head = "abc123",
    )

    @Test
    fun testEnrichWithSessionIds() {
        val detection = FakeAgentDetection(
            activeDirs = setOf(featurePath),
            sessionIds = mapOf(featurePath to listOf("session-1", "session-2")),
        )
        val enricher = AgentStatusEnricher(detection)
        val result = enricher.enrich(listOf(makeWt()))

        assertTrue(result[0].hasActiveAgent)
        assertEquals(listOf("session-1", "session-2"), result[0].activeAgentSessionIds)
    }

    @Test
    fun testEnrichRunningProcessNoSessions() {
        // Process detected via lsof but no recent session files
        val detection = FakeAgentDetection(
            activeDirs = setOf(featurePath),
            sessionIds = emptyMap(), // no sessions returned
        )
        val enricher = AgentStatusEnricher(detection)
        val result = enricher.enrich(listOf(makeWt()))

        assertTrue(result[0].hasActiveAgent)
        assertEquals(listOf("(running)"), result[0].activeAgentSessionIds)
    }

    @Test
    fun testEnrichNoProcessNoSessions() {
        val detection = FakeAgentDetection()
        val enricher = AgentStatusEnricher(detection)
        val result = enricher.enrich(listOf(makeWt()))

        assertFalse(result[0].hasActiveAgent)
        assertTrue(result[0].activeAgentSessionIds.isEmpty())
    }

    @Test
    fun testEnrichMultipleWorktrees() {
        val detection = FakeAgentDetection(
            activeDirs = setOf(featurePath),
            sessionIds = mapOf(featurePath to listOf("sess-1")),
        )
        val enricher = AgentStatusEnricher(detection)
        val result = enricher.enrich(listOf(
            makeWt(path = mainPath, branch = "main"),
            makeWt(path = featurePath, branch = "feature"),
        ))

        assertFalse(result[0].hasActiveAgent)
        assertTrue(result[1].hasActiveAgent)
        assertEquals(listOf("sess-1"), result[1].activeAgentSessionIds)
    }
}
