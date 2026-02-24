package com.block.wt.services

import com.block.wt.testutil.TestFileHelper.deleteRecursive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path

class MetadataServiceTest {

    @Test
    fun testDeduplicateNested() {
        // Use a standalone test for the deduplication logic
        val paths = listOf(
            Path.of("/repo/.ijwb"),
            Path.of("/repo/.ijwb/.idea"),
            Path.of("/repo/.vscode"),
            Path.of("/repo/subdir/.idea"),
        )

        val result = deduplicateNested(paths)

        assertEquals(3, result.size)
        assertTrue(result.contains(Path.of("/repo/.ijwb")))
        assertTrue(result.contains(Path.of("/repo/.vscode")))
        assertTrue(result.contains(Path.of("/repo/subdir/.idea")))
        // .ijwb/.idea should be removed because it's nested under .ijwb
        assertTrue(!result.contains(Path.of("/repo/.ijwb/.idea")))
    }

    @Test
    fun testDeduplicateNestedEmpty() {
        assertEquals(emptyList<Path>(), deduplicateNested(emptyList()))
    }

    @Test
    fun testDeduplicateNestedSingle() {
        val paths = listOf(Path.of("/repo/.idea"))
        assertEquals(paths, deduplicateNested(paths))
    }

    @Test
    fun testCopyDirectoryStructure() {
        val sourceDir = Files.createTempDirectory("meta-source")
        val targetDir = Files.createTempDirectory("meta-target")
        try {
            // Create source structure
            val subDir = sourceDir.resolve("subdir")
            Files.createDirectory(subDir)
            Files.writeString(sourceDir.resolve("file1.txt"), "content1")
            Files.writeString(subDir.resolve("file2.txt"), "content2")

            // Copy
            copyDirectory(sourceDir, targetDir)

            // Verify
            assertTrue(Files.exists(targetDir.resolve("file1.txt")))
            assertTrue(Files.exists(targetDir.resolve("subdir/file2.txt")))
            assertEquals("content1", Files.readString(targetDir.resolve("file1.txt")))
            assertEquals("content2", Files.readString(targetDir.resolve("subdir/file2.txt")))
        } finally {
            deleteRecursive(sourceDir)
            deleteRecursive(targetDir)
        }
    }

    // Standalone implementations of the logic for testing without IntelliJ platform
    private fun deduplicateNested(paths: List<Path>): List<Path> {
        val sorted = paths.sortedBy { it.nameCount }
        val kept = mutableListOf<Path>()
        for (path in sorted) {
            val isNested = kept.any { path.startsWith(it) }
            if (!isNested) {
                kept.add(path)
            }
        }
        return kept
    }

    private fun copyDirectory(source: Path, target: Path) {
        Files.walkFileTree(source, object : java.nio.file.SimpleFileVisitor<Path>() {
            override fun preVisitDirectory(dir: Path, attrs: java.nio.file.attribute.BasicFileAttributes): java.nio.file.FileVisitResult {
                val targetDir = target.resolve(source.relativize(dir))
                Files.createDirectories(targetDir)
                return java.nio.file.FileVisitResult.CONTINUE
            }

            override fun visitFile(file: Path, attrs: java.nio.file.attribute.BasicFileAttributes): java.nio.file.FileVisitResult {
                val targetFile = target.resolve(source.relativize(file))
                Files.copy(file, targetFile, java.nio.file.StandardCopyOption.REPLACE_EXISTING)
                return java.nio.file.FileVisitResult.CONTINUE
            }
        })
    }

}
