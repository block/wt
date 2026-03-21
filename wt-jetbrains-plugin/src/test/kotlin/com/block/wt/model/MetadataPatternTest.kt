package com.block.wt.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MetadataPatternTest {

    @Test
    fun testKnownPatternsHasExactly20Entries() {
        assertEquals(20, MetadataPattern.KNOWN_PATTERNS.size)
    }

    @Test
    fun testKnownPatternsNamesAreUnique() {
        val names = MetadataPattern.KNOWN_PATTERNS.map { it.name }
        assertEquals(names.size, names.toSet().size)
    }

    @Test
    fun testKnownPatternsOrderMatchesCli() {
        val expectedOrder = listOf(
            ".idea", ".run", ".fleet",
            ".ijwb", ".aswb", ".clwb", ".bazelbsp", ".bazelproject", ".bsp",
            ".xcodeproj", ".xcworkspace", ".swiftpm", "xcuserdata",
            ".vscode",
            ".metals", ".bloop",
            ".eclipse", ".settings", ".project", ".classpath",
        )
        val actualNames = MetadataPattern.KNOWN_PATTERNS.map { it.name }
        assertEquals(expectedOrder, actualNames)
    }

    @Test
    fun testBazelIdePatternsSubsetOfKnownPatterns() {
        val knownNames = MetadataPattern.KNOWN_PATTERNS.map { it.name }.toSet()
        for (bazelPattern in MetadataPattern.BAZEL_IDE_PATTERNS) {
            assertTrue(
                "BAZEL_IDE_PATTERNS entry '$bazelPattern' should be in KNOWN_PATTERNS",
                bazelPattern in knownNames,
            )
        }
    }
}
