package com.block.wt.provision

import com.block.wt.testutil.TestFileHelper.deleteRecursive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
            Files.createDirectory(dir.resolve(".git"))
            assertFalse(ProvisionMarkerService.isProvisioned(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testWriteAndReadAdoptionMarker() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))

            val result = ProvisionMarkerService.writeAdoptionMarker(dir, "java")
            assertTrue(result.isSuccess)
            assertTrue(ProvisionMarkerService.isProvisioned(dir))
            assertTrue(ProvisionMarkerService.isProvisionedByContext(dir, "java"))
            assertFalse(ProvisionMarkerService.isProvisionedByContext(dir, "kotlin"))

            val context = ProvisionMarkerService.readAdoptedContext(dir)
            assertEquals("java", context)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testWriteOverwritesPreviousContext() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))

            ProvisionMarkerService.writeAdoptionMarker(dir, "java")
            ProvisionMarkerService.writeAdoptionMarker(dir, "kotlin")

            val context = ProvisionMarkerService.readAdoptedContext(dir)
            assertEquals("kotlin", context)
            assertTrue(ProvisionMarkerService.isProvisionedByContext(dir, "kotlin"))
            assertFalse(ProvisionMarkerService.isProvisionedByContext(dir, "java"))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReProvisionSameContextIsIdempotent() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))

            ProvisionMarkerService.writeAdoptionMarker(dir, "java")
            ProvisionMarkerService.writeAdoptionMarker(dir, "java")

            assertEquals("java", ProvisionMarkerService.readAdoptedContext(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testRemoveAdoptionMarkerDeletesFile() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))
            ProvisionMarkerService.writeAdoptionMarker(dir, "java")
            assertTrue(ProvisionMarkerService.isProvisioned(dir))

            val result = ProvisionMarkerService.removeAdoptionMarker(dir)
            assertTrue(result.isSuccess)
            assertFalse(ProvisionMarkerService.isProvisioned(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testRemoveNonexistentMarkerSucceeds() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            Files.createDirectory(dir.resolve(".git"))
            assertTrue(ProvisionMarkerService.removeAdoptionMarker(dir).isSuccess)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testFallbackReadFromLegacyJson() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            val gitDir = dir.resolve(".git")
            Files.createDirectory(gitDir)

            // Write legacy JSON marker
            Files.writeString(
                gitDir.resolve("wt-provisioned"),
                """{"current": "go", "provisions": [{"context": "go"}]}"""
            )

            assertTrue(ProvisionMarkerService.isProvisioned(dir))
            assertEquals("go", ProvisionMarkerService.readAdoptedContext(dir))
            assertTrue(ProvisionMarkerService.isProvisionedByContext(dir, "go"))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testWriteCleanUpLegacyJson() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            val gitDir = dir.resolve(".git")
            Files.createDirectory(gitDir)

            // Create legacy marker
            val legacyPath = gitDir.resolve("wt-provisioned")
            Files.writeString(legacyPath, """{"current":"old"}""")
            assertTrue(Files.exists(legacyPath))

            // Write new marker — should clean up legacy
            ProvisionMarkerService.writeAdoptionMarker(dir, "java")
            assertFalse(Files.exists(legacyPath))
            assertEquals("java", ProvisionMarkerService.readAdoptedContext(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testRemoveCleanUpLegacyJson() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            val gitDir = dir.resolve(".git")
            Files.createDirectory(gitDir)

            // Create legacy marker
            val legacyPath = gitDir.resolve("wt-provisioned")
            Files.writeString(legacyPath, """{"current":"old"}""")

            ProvisionMarkerService.removeAdoptionMarker(dir)
            assertFalse(Files.exists(legacyPath))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testEmptyAdoptedFileBackwardCompat() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            val gitDir = dir.resolve(".git")
            Files.createDirectory(gitDir)
            val wtDir = gitDir.resolve("wt")
            Files.createDirectories(wtDir)

            // Old CLI format: empty file
            Files.writeString(wtDir.resolve("adopted"), "")

            assertTrue(ProvisionMarkerService.isProvisioned(dir))
            // Empty content returns null — no context info
            assertNull(ProvisionMarkerService.readAdoptedContext(dir))
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

            val result = ProvisionMarkerService.writeAdoptionMarker(worktree, "test-context")
            assertTrue(result.isSuccess)
            assertTrue(Files.exists(gitWorktreeDir.resolve("wt").resolve("adopted")))
            assertTrue(ProvisionMarkerService.isProvisionedByContext(worktree, "test-context"))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testCrossToolCliFormatReadByPlugin() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            val gitDir = dir.resolve(".git")
            Files.createDirectory(gitDir)
            val wtDir = gitDir.resolve("wt")
            Files.createDirectories(wtDir)

            // Write in CLI format: context name followed by newline
            Files.writeString(wtDir.resolve("adopted"), "java\n")

            assertTrue(ProvisionMarkerService.isProvisioned(dir))
            assertEquals("java", ProvisionMarkerService.readAdoptedContext(dir))
            assertTrue(ProvisionMarkerService.isProvisionedByContext(dir, "java"))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testLegacyJsonWithNoCurrentFieldReturnsNull() {
        val dir = Files.createTempDirectory("provision-test")
        try {
            val gitDir = dir.resolve(".git")
            Files.createDirectory(gitDir)

            // Legacy JSON without "current" field
            Files.writeString(gitDir.resolve("wt-provisioned"), """{"provisions": []}""")

            assertTrue(ProvisionMarkerService.isProvisioned(dir))
            assertNull(ProvisionMarkerService.readAdoptedContext(dir))
        } finally {
            deleteRecursive(dir)
        }
    }
}
