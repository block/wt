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

    @Test
    fun testImportHierarchicalVault() {
        val dir = Files.createTempDirectory("import-hierarchical")
        try {
            val vault = dir.resolve("vault")
            val target = dir.resolve("target")
            Files.createDirectories(vault)
            Files.createDirectories(target)

            // Create real metadata directories
            val topIdea = dir.resolve("real-top-idea")
            Files.createDirectories(topIdea)
            Files.writeString(topIdea.resolve("workspace.xml"), "top-content")

            val nestedIdea = dir.resolve("real-nested-idea")
            Files.createDirectories(nestedIdea)
            Files.writeString(nestedIdea.resolve("workspace.xml"), "nested-content")

            // Create vault structure with symlinks
            // vault/.idea -> real-top-idea
            Files.createSymbolicLink(vault.resolve(".idea"), topIdea)
            // vault/services/payments/.idea -> real-nested-idea
            Files.createDirectories(vault.resolve("services/payments"))
            Files.createSymbolicLink(vault.resolve("services/payments/.idea"), nestedIdea)

            val result = MetadataService.importMetadataStatic(vault, target, listOf(".idea"))
            assertTrue(result.isSuccess)
            assertEquals(2, result.getOrThrow())

            // Verify both imported to correct target paths
            assertTrue(Files.exists(target.resolve(".idea/workspace.xml")))
            assertEquals("top-content", Files.readString(target.resolve(".idea/workspace.xml")))
            assertTrue(Files.exists(target.resolve("services/payments/.idea/workspace.xml")))
            assertEquals("nested-content", Files.readString(target.resolve("services/payments/.idea/workspace.xml")))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testImportFlatVaultBackwardCompat() {
        val dir = Files.createTempDirectory("import-flat")
        try {
            val vault = dir.resolve("vault")
            val target = dir.resolve("target")
            Files.createDirectories(vault)
            Files.createDirectories(target)

            // Create real metadata directory
            val realIdea = dir.resolve("real-idea")
            Files.createDirectories(realIdea)
            Files.writeString(realIdea.resolve("workspace.xml"), "content")

            // Create vault with top-level symlink
            Files.createSymbolicLink(vault.resolve(".idea"), realIdea)

            // Empty patterns = backward compat (match symlinks)
            val result = MetadataService.importMetadataStatic(vault, target)
            assertTrue(result.isSuccess)
            assertEquals(1, result.getOrThrow())

            assertTrue(Files.exists(target.resolve(".idea/workspace.xml")))
            assertEquals("content", Files.readString(target.resolve(".idea/workspace.xml")))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testImportPatternFiltering() {
        val dir = Files.createTempDirectory("import-filter")
        try {
            val vault = dir.resolve("vault")
            val target = dir.resolve("target")
            Files.createDirectories(vault)
            Files.createDirectories(target)

            // Create real metadata directories
            val realIdea = dir.resolve("real-idea")
            Files.createDirectories(realIdea)
            Files.writeString(realIdea.resolve("workspace.xml"), "idea-content")

            val realVscode = dir.resolve("real-vscode")
            Files.createDirectories(realVscode)
            Files.writeString(realVscode.resolve("settings.json"), "vscode-content")

            // Both in vault as symlinks
            Files.createSymbolicLink(vault.resolve(".idea"), realIdea)
            Files.createSymbolicLink(vault.resolve(".vscode"), realVscode)

            // Only import .idea
            val result = MetadataService.importMetadataStatic(vault, target, listOf(".idea"))
            assertTrue(result.isSuccess)
            assertEquals(1, result.getOrThrow())

            assertTrue(Files.exists(target.resolve(".idea/workspace.xml")))
            assertTrue(!Files.exists(target.resolve(".vscode")))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testImportBrokenSymlinkCleanup() {
        val dir = Files.createTempDirectory("import-broken")
        try {
            val vault = dir.resolve("vault")
            val target = dir.resolve("target")
            Files.createDirectories(vault)
            Files.createDirectories(target)

            // Create a broken symlink pointing to non-existent directory
            val brokenTarget = dir.resolve("does-not-exist")
            Files.createSymbolicLink(vault.resolve(".idea"), brokenTarget)

            // Also create a valid one
            val realVscode = dir.resolve("real-vscode")
            Files.createDirectories(realVscode)
            Files.writeString(realVscode.resolve("settings.json"), "content")
            Files.createSymbolicLink(vault.resolve(".vscode"), realVscode)

            val result = MetadataService.importMetadataStatic(vault, target, listOf(".idea", ".vscode"))
            assertTrue(result.isSuccess)
            assertEquals(1, result.getOrThrow())

            // Broken symlink should be deleted
            assertTrue(!Files.exists(vault.resolve(".idea")))
            assertTrue(!Files.isSymbolicLink(vault.resolve(".idea")))

            // Valid one should be imported
            assertTrue(Files.exists(target.resolve(".vscode/settings.json")))
        } finally {
            deleteRecursive(dir)
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
