package com.block.wt.provision

import com.block.wt.testutil.TestFileHelper.deleteRecursive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path

class ProvisionMarkerServiceTest {

    @Test
    fun testIsProvisionedReturnsFalseWhenNoGitDir() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            assertFalse(ProvisionMarkerService.isProvisioned(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testIsProvisionedReturnsFalseWhenNoMarker() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            // Create a .git directory (main worktree style)
            Files.createDirectory(dir.resolve(".git"))
            assertFalse(ProvisionMarkerService.isProvisioned(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testWriteAndReadProvisionMarker() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))

            val result = ProvisionMarkerService.writeProvisionMarker(dir, "java")
            assertTrue(result.isSuccess)
            assertTrue(ProvisionMarkerService.isProvisioned(dir))
            assertTrue(ProvisionMarkerService.isProvisionedByContext(dir, "java"))
            assertFalse(ProvisionMarkerService.isProvisionedByContext(dir, "kotlin"))

            val marker = ProvisionMarkerService.readProvisionMarker(dir)
            assertNotNull(marker)
            assertEquals("java", marker!!.current)
            assertEquals(1, marker.provisions.size)
            assertEquals("java", marker.provisions[0].context)
            assertEquals("intellij-plugin", marker.provisions[0].provisionedBy)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testWriteMultipleContextsPreservesHistory() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))

            ProvisionMarkerService.writeProvisionMarker(dir, "java")
            ProvisionMarkerService.writeProvisionMarker(dir, "kotlin")

            val marker = ProvisionMarkerService.readProvisionMarker(dir)
            assertNotNull(marker)
            assertEquals("kotlin", marker!!.current)
            assertEquals(2, marker.provisions.size)

            val contexts = marker.provisions.map { it.context }.toSet()
            assertTrue(contexts.contains("java"))
            assertTrue(contexts.contains("kotlin"))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReProvisionSameContextUpdatesEntry() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))

            ProvisionMarkerService.writeProvisionMarker(dir, "java")
            ProvisionMarkerService.writeProvisionMarker(dir, "java")

            val marker = ProvisionMarkerService.readProvisionMarker(dir)
            assertNotNull(marker)
            assertEquals("java", marker!!.current)
            assertEquals(1, marker.provisions.size)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testRemoveProvisionMarkerDeletesFile() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))
            ProvisionMarkerService.writeProvisionMarker(dir, "java")
            assertTrue(ProvisionMarkerService.isProvisioned(dir))

            val result = ProvisionMarkerService.removeProvisionMarker(dir)
            assertTrue(result.isSuccess)
            assertFalse(ProvisionMarkerService.isProvisioned(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testRemoveSpecificContextKeepsOthers() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))
            ProvisionMarkerService.writeProvisionMarker(dir, "java")
            ProvisionMarkerService.writeProvisionMarker(dir, "kotlin")

            val result = ProvisionMarkerService.removeProvisionMarker(dir, "java")
            assertTrue(result.isSuccess)

            val marker = ProvisionMarkerService.readProvisionMarker(dir)
            assertNotNull(marker)
            assertEquals(1, marker!!.provisions.size)
            assertEquals("kotlin", marker.provisions[0].context)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testRemoveCurrentContextUpdatesCurrent() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))
            ProvisionMarkerService.writeProvisionMarker(dir, "java")
            ProvisionMarkerService.writeProvisionMarker(dir, "kotlin")

            // "kotlin" is current, remove it
            ProvisionMarkerService.removeProvisionMarker(dir, "kotlin")

            val marker = ProvisionMarkerService.readProvisionMarker(dir)
            assertNotNull(marker)
            assertEquals("java", marker!!.current)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testRemoveLastContextDeletesFile() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))
            ProvisionMarkerService.writeProvisionMarker(dir, "java")

            ProvisionMarkerService.removeProvisionMarker(dir, "java")
            assertFalse(ProvisionMarkerService.isProvisioned(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testRemoveNonexistentMarkerReturnsTrue() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))
            assertTrue(ProvisionMarkerService.removeProvisionMarker(dir).isSuccess)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadIncompleteJsonReturnsNull() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            val gitDir = dir.resolve(".git")
            Files.createDirectory(gitDir)

            // Empty JSON object — Gson sets non-null fields to null via Unsafe
            Files.writeString(gitDir.resolve("wt-provisioned"), "{}")
            assertNull(ProvisionMarkerService.readProvisionMarker(dir))

            // Missing provisions field
            Files.writeString(gitDir.resolve("wt-provisioned"), """{"current":"test"}""")
            assertNull(ProvisionMarkerService.readProvisionMarker(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadMalformedJsonReturnsNull() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            val gitDir = dir.resolve(".git")
            Files.createDirectory(gitDir)
            Files.writeString(gitDir.resolve("wt-provisioned"), "not valid json")

            assertNull(ProvisionMarkerService.readProvisionMarker(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testHasExistingMetadata() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            assertFalse(ProvisionMarkerService.hasExistingMetadata(dir))

            Files.createDirectory(dir.resolve(".idea"))
            assertTrue(ProvisionMarkerService.hasExistingMetadata(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testLinkedWorktreeGitFile() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            // Simulate a linked worktree: .git is a file pointing to a gitdir
            val gitWorktreeDir = dir.resolve("gitworktrees").resolve("mybranch")
            Files.createDirectories(gitWorktreeDir)

            val worktree = dir.resolve("worktree")
            Files.createDirectory(worktree)
            Files.writeString(worktree.resolve(".git"), "gitdir: ${gitWorktreeDir}")

            val result = ProvisionMarkerService.writeProvisionMarker(worktree, "test-context")
            assertTrue(result.isSuccess)
            assertTrue(Files.exists(gitWorktreeDir.resolve("wt-provisioned")))
            assertTrue(ProvisionMarkerService.isProvisionedByContext(worktree, "test-context"))
        } finally {
            deleteRecursive(dir)
        }
    }

}
