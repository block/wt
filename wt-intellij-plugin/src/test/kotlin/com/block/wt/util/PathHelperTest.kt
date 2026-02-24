package com.block.wt.util

import com.block.wt.testutil.TestFileHelper.deleteRecursive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path

class PathHelperTest {

    @Test
    fun testExpandTildeWithSubpath() {
        val result = PathHelper.expandTilde("~/foo/bar")
        val home = System.getProperty("user.home")
        assertEquals(Path.of(home, "foo", "bar"), result)
    }

    @Test
    fun testExpandTildeAlone() {
        val result = PathHelper.expandTilde("~")
        val home = System.getProperty("user.home")
        assertEquals(Path.of(home), result)
    }

    @Test
    fun testExpandTildeAbsolutePath() {
        val result = PathHelper.expandTilde("/absolute/path")
        assertEquals(Path.of("/absolute/path"), result)
    }

    @Test
    fun testAtomicSetSymlinkCreate() {
        val dir = Files.createTempDirectory("pathhelper-test")
        try {
            val link = dir.resolve("link")
            val target = dir.resolve("target")
            Files.createDirectory(target)

            PathHelper.atomicSetSymlink(link, target)

            assertTrue(Files.isSymbolicLink(link))
            assertEquals(target, Files.readSymbolicLink(link))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testAtomicSetSymlinkReplace() {
        val dir = Files.createTempDirectory("pathhelper-test")
        try {
            val link = dir.resolve("link")
            val target1 = dir.resolve("target1")
            val target2 = dir.resolve("target2")
            Files.createDirectory(target1)
            Files.createDirectory(target2)

            PathHelper.atomicSetSymlink(link, target1)
            assertEquals(target1, Files.readSymbolicLink(link))

            // Atomic replace
            PathHelper.atomicSetSymlink(link, target2)
            assertEquals(target2, Files.readSymbolicLink(link))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testAtomicSetSymlinkCleanupOnError() {
        val dir = Files.createTempDirectory("pathhelper-test")
        try {
            val link = dir.resolve("nonexistent-parent/link")

            try {
                PathHelper.atomicSetSymlink(link, dir)
            } catch (_: Exception) {
                // Expected
            }

            // Verify no temp files left behind in parent
            val parentDir = link.parent
            if (Files.isDirectory(parentDir)) {
                val tempFiles = Files.list(parentDir).use { stream ->
                    stream.filter { it.fileName.toString().contains(".tmp") }.count()
                }
                assertEquals(0L, tempFiles)
            }
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testIsSymlink() {
        val dir = Files.createTempDirectory("pathhelper-test")
        try {
            val target = dir.resolve("target")
            Files.createDirectory(target)
            val link = dir.resolve("link")
            Files.createSymbolicLink(link, target)

            assertTrue(PathHelper.isSymlink(link))
            assertFalse(PathHelper.isSymlink(target))
            assertFalse(PathHelper.isSymlink(dir.resolve("nonexistent")))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadSymlink() {
        val dir = Files.createTempDirectory("pathhelper-test")
        try {
            val target = dir.resolve("target")
            Files.createDirectory(target)
            val link = dir.resolve("link")
            Files.createSymbolicLink(link, target)

            val read = PathHelper.readSymlink(link)
            assertNotNull(read)
            assertEquals(target, read)

            // Non-symlink returns null
            val notLink = PathHelper.readSymlink(target)
            assertEquals(null, notLink)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testNormalizeSafe() {
        val dir = Files.createTempDirectory("pathhelper-test")
        try {
            val normalized = PathHelper.normalizeSafe(dir)
            assertNotNull(normalized)
            assertFalse(normalized.toString().contains(".."))
        } finally {
            deleteRecursive(dir)
        }
    }

}
