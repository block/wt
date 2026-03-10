package com.block.wt.experiment.sessionstats

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.nio.file.Path

class SessionStatsParserTest {

    @get:Rule
    val tmpDir = TemporaryFolder()

    // --- extractString ---

    @Test
    fun testExtractStringBasic() {
        val line = """{"type": "assistant", "model": "claude-opus-4-6"}"""
        assertEquals("assistant", SessionStatsParser.extractString(line, "\"type\""))
        assertEquals("claude-opus-4-6", SessionStatsParser.extractString(line, "\"model\""))
    }

    @Test
    fun testExtractStringNoSpaceAfterColon() {
        val line = """{"type":"user"}"""
        assertEquals("user", SessionStatsParser.extractString(line, "\"type\""))
    }

    @Test
    fun testExtractStringMissing() {
        val line = """{"type": "assistant"}"""
        assertNull(SessionStatsParser.extractString(line, "\"model\""))
    }

    @Test
    fun testExtractStringEscapedQuote() {
        val line = """{"slug": "hello-\"world\""}"""
        // Should extract up to the first unescaped quote
        assertNotNull(SessionStatsParser.extractString(line, "\"slug\""))
    }

    // --- extractLong ---

    @Test
    fun testExtractLongBasic() {
        val line = """{"input_tokens": 1234, "output_tokens": 5678}"""
        assertEquals(1234L, SessionStatsParser.extractLong(line, "\"input_tokens\""))
        assertEquals(5678L, SessionStatsParser.extractLong(line, "\"output_tokens\""))
    }

    @Test
    fun testExtractLongNoSpaceAfterColon() {
        val line = """{"input_tokens":42}"""
        assertEquals(42L, SessionStatsParser.extractLong(line, "\"input_tokens\""))
    }

    @Test
    fun testExtractLongMissing() {
        val line = """{"other": 99}"""
        assertEquals(0L, SessionStatsParser.extractLong(line, "\"input_tokens\""))
    }

    @Test
    fun testExtractLongZero() {
        val line = """{"input_tokens": 0}"""
        assertEquals(0L, SessionStatsParser.extractLong(line, "\"input_tokens\""))
    }

    // --- parseFile ---

    @Test
    fun testParseFileAggregatesCorrectly() {
        val file = tmpDir.newFile("test-session.jsonl")
        file.writeText(buildString {
            appendLine("""{"type":"user","userType":"external","timestamp":"2026-03-10T01:00:00Z"}""")
            appendLine("""{"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":200,"cache_read_input_tokens":300},"content":[{"type":"tool_use"}]},"slug":"test-slug","timestamp":"2026-03-10T01:00:10Z"}""")
            appendLine("""{"type":"user","userType":"external","timestamp":"2026-03-10T01:00:20Z"}""")
            appendLine("""{"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":150,"output_tokens":75,"cache_creation_input_tokens":0,"cache_read_input_tokens":400},"content":[{"type":"tool_use"},{"type":"tool_use"}]},"timestamp":"2026-03-10T01:01:00Z"}""")
            appendLine("""{"type":"system","subtype":"turn_duration","durationMs":30000,"version":"2.1.71","timestamp":"2026-03-10T01:01:05Z"}""")
            appendLine("""{"type":"system","subtype":"turn_duration","durationMs":15000,"timestamp":"2026-03-10T01:02:00Z"}""")
        })

        val stats = SessionStatsParser.parseFile(file.toPath(), "test-session")
        assertNotNull(stats)
        stats!!

        assertEquals("claude-opus-4-6", stats.model)
        assertEquals("test-slug", stats.slug)
        assertEquals("2.1.71", stats.claudeCodeVersion)
        assertEquals(250L, stats.inputTokens)
        assertEquals(125L, stats.outputTokens)
        assertEquals(375L, stats.totalTokens)
        assertEquals(200L, stats.cacheCreationTokens)
        assertEquals(700L, stats.cacheReadTokens)
        assertEquals(2, stats.userTurns)
        assertEquals(2, stats.assistantMessages)
        assertEquals(3, stats.toolUses)
        assertEquals(45000L, stats.totalTurnDurationMs)
        assertEquals("2026-03-10T01:00:00Z", stats.firstTimestamp)
        assertEquals("2026-03-10T01:02:00Z", stats.lastTimestamp)
    }

    @Test
    fun testParseFileEmpty() {
        val file = tmpDir.newFile("empty.jsonl")
        file.writeText("")
        val stats = SessionStatsParser.parseFile(file.toPath(), "empty")
        assertNotNull(stats)
        assertEquals(0, stats!!.userTurns)
        assertEquals(0, stats.assistantMessages)
    }

    @Test
    fun testParseFileNonexistent() {
        val result = SessionStatsParser.parseFile(Path.of("/nonexistent/file.jsonl"), "x")
        assertNull(result)
    }

    // --- SessionStats formatting ---

    @Test
    fun testFormatTokenCount() {
        val stats = makeStats()
        assertEquals("500", stats.formatTokenCount(500))
        assertEquals("1.5k", stats.formatTokenCount(1500))
        assertEquals("2.3M", stats.formatTokenCount(2_300_000))
    }

    @Test
    fun testFormatDuration() {
        val stats = makeStats()
        assertEquals("45s", stats.formatDuration(45_000))
        assertEquals("2m 30s", stats.formatDuration(150_000))
        assertEquals("1h 5m", stats.formatDuration(3_900_000))
    }

    private fun makeStats() = SessionStats(
        sessionId = "test",
        model = null,
        claudeCodeVersion = null,
        slug = null,
        inputTokens = 0,
        outputTokens = 0,
        cacheCreationTokens = 0,
        cacheReadTokens = 0,
        userTurns = 0,
        assistantMessages = 0,
        toolUses = 0,
        totalTurnDurationMs = 0,
        firstTimestamp = null,
        lastTimestamp = null,
    )
}
