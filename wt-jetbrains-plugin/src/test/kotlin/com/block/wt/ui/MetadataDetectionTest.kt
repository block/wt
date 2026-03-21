package com.block.wt.ui

import com.block.wt.model.MetadataPattern
import com.block.wt.testutil.TestFileHelper.deleteRecursive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.attribute.BasicFileAttributes

/**
 * Tests for the recursive metadata detection logic used in AddContextDialog.
 * Extracted here to avoid IntelliJ platform dependencies.
 */
class MetadataDetectionTest {

    /**
     * Mirrors the walk logic from AddContextDialog.detectAndShowPatterns.
     */
    private fun detectPatterns(repoPath: Path): Set<String> {
        val detected = mutableSetOf<String>()
        val knownNames = MetadataPattern.KNOWN_PATTERNS.map { it.name }.toSet()
        Files.walkFileTree(repoPath, emptySet(), 5, object : SimpleFileVisitor<Path>() {
            override fun preVisitDirectory(dir: Path, attrs: BasicFileAttributes): FileVisitResult {
                val name = dir.fileName?.toString() ?: return FileVisitResult.CONTINUE
                if (name in knownNames && dir != repoPath) {
                    detected.add(name)
                    return FileVisitResult.SKIP_SUBTREE
                }
                return FileVisitResult.CONTINUE
            }
        })
        return detected
    }

    @Test
    fun testDetectsRootLevelMetadata() {
        val dir = Files.createTempDirectory("detect-root")
        try {
            Files.createDirectories(dir.resolve(".idea"))
            Files.createDirectories(dir.resolve(".vscode"))

            val result = detectPatterns(dir)
            assertEquals(setOf(".idea", ".vscode"), result)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testDetectsNestedMetadata() {
        val dir = Files.createTempDirectory("detect-nested")
        try {
            // Nested .idea inside a subproject (depth 2)
            Files.createDirectories(dir.resolve("subproject/.idea"))
            // Root-level .vscode
            Files.createDirectories(dir.resolve(".vscode"))

            val result = detectPatterns(dir)
            assertTrue(".idea should be detected in subproject", ".idea" in result)
            assertTrue(".vscode should be detected at root", ".vscode" in result)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testDetectsMetadataAtMaxDepth() {
        val dir = Files.createTempDirectory("detect-depth")
        try {
            // walkFileTree maxDepth=5 visits directories at relative depth 0..4
            // a/b/c/.idea is at relative depth 4, which is within maxDepth=5
            Files.createDirectories(dir.resolve("a/b/c/.idea"))

            val result = detectPatterns(dir)
            assertTrue(".idea at relative depth 4 should be detected", ".idea" in result)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testIgnoresMetadataBeyondMaxDepth() {
        val dir = Files.createTempDirectory("detect-too-deep")
        try {
            // walkFileTree maxDepth=5 visits directories at relative depth 0..4
            // a/b/c/d/e/.idea is at relative depth 5, which is beyond maxDepth=5
            Files.createDirectories(dir.resolve("a/b/c/d/e/.idea"))

            val result = detectPatterns(dir)
            assertTrue(".idea beyond maxDepth should not be detected", ".idea" !in result)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testDeduplicatesAcrossSubtrees() {
        val dir = Files.createTempDirectory("detect-dedup")
        try {
            // .idea in two different subprojects
            Files.createDirectories(dir.resolve("project-a/.idea"))
            Files.createDirectories(dir.resolve("project-b/.idea"))

            val result = detectPatterns(dir)
            // Set-based detection means .idea appears once
            assertEquals(setOf(".idea"), result)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testEmptyRepoReturnsEmpty() {
        val dir = Files.createTempDirectory("detect-empty")
        try {
            val result = detectPatterns(dir)
            assertTrue("Empty repo should have no patterns", result.isEmpty())
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testSkipsSubtreeOfMatchedPattern() {
        val dir = Files.createTempDirectory("detect-skip")
        try {
            // .ijwb contains .idea inside it — .idea should NOT be detected separately
            // because .ijwb triggers SKIP_SUBTREE
            Files.createDirectories(dir.resolve(".ijwb/.idea"))

            val result = detectPatterns(dir)
            assertTrue(".ijwb should be detected", ".ijwb" in result)
            assertTrue(".idea inside .ijwb should not be detected separately", ".idea" !in result)
        } finally {
            deleteRecursive(dir)
        }
    }
}
