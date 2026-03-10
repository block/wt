package com.block.wt.experiment.sessiondetection

import com.block.wt.testutil.FakeAgentDetection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Path

class EnhancedAgentDetectorTest {

    private val worktreePath = Path.of("/Users/test/worktrees/feature")

    // --- JSON parsing tests ---

    @Test
    fun testExtractJsonLong() {
        val detector = createDetector()
        val json = """{"pid": 12345, "other": "value"}"""
        assertEquals(12345L, detector.extractJsonLong(json, "pid"))
    }

    @Test
    fun testExtractJsonLongMissing() {
        val detector = createDetector()
        val json = """{"other": "value"}"""
        assertNull(detector.extractJsonLong(json, "pid"))
    }

    @Test
    fun testExtractJsonLongWithSpaces() {
        val detector = createDetector()
        val json = """{ "pid" : 42 }"""
        assertEquals(42L, detector.extractJsonLong(json, "pid"))
    }

    @Test
    fun testExtractJsonStringArray() {
        val detector = createDetector()
        val json = """{"workspaceFolders": ["/Users/test/worktrees/feature", "/another/path"]}"""
        val result = detector.extractJsonStringArray(json, "workspaceFolders")
        assertEquals(listOf("/Users/test/worktrees/feature", "/another/path"), result)
    }

    @Test
    fun testExtractJsonStringArrayEmpty() {
        val detector = createDetector()
        val json = """{"workspaceFolders": []}"""
        val result = detector.extractJsonStringArray(json, "workspaceFolders")
        assertTrue(result.isEmpty())
    }

    @Test
    fun testExtractJsonStringArrayMissing() {
        val detector = createDetector()
        val json = """{"other": "value"}"""
        val result = detector.extractJsonStringArray(json, "workspaceFolders")
        assertTrue(result.isEmpty())
    }

    // --- Threshold constants ---

    @Test
    fun testActiveWriteThreshold() {
        assertEquals(60_000L, EnhancedAgentDetector.ACTIVE_WRITE_THRESHOLD_MS)
    }

    @Test
    fun testIdleThreshold() {
        assertEquals(600_000L, EnhancedAgentDetector.IDLE_THRESHOLD_MS)
    }


    // --- TTY resolution ---

    @Test
    fun testResolveTtysEmptyPids() {
        val detector = createDetector()
        val result = detector.doResolveTtys(emptySet())
        assertTrue(result.isEmpty())
    }

    // --- Delegate passthrough ---

    @Test
    fun testDelegatesDetectActiveAgentDirs() {
        val fakeDirs = setOf(worktreePath)
        val fake = FakeAgentDetection(activeDirs = fakeDirs)
        val detector = EnhancedAgentDetector(fake)
        assertEquals(fakeDirs, detector.detectActiveAgentDirs())
    }

    @Test
    fun testDelegatesDetectActiveSessionIds() {
        val fakeSessionIds = mapOf(worktreePath to listOf("session-1"))
        val fake = FakeAgentDetection(sessionIds = fakeSessionIds)
        val detector = EnhancedAgentDetector(fake)
        assertEquals(listOf("session-1"), detector.detectActiveSessionIds(worktreePath))
    }

    // --- Lock file PID detection edge cases ---

    @Test
    fun testDetectLockFilePidsNonexistentDir() {
        val detector = createDetector()
        // ~/.claude/ide/ likely doesn't exist in test env — should return empty
        val result = detector.doDetectLockFilePids(Path.of("/nonexistent/worktree"))
        assertTrue(result.isEmpty())
    }

    private fun createDetector(): EnhancedAgentDetector {
        return EnhancedAgentDetector(FakeAgentDetection())
    }
}
