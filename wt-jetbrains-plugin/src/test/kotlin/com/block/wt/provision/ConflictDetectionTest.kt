package com.block.wt.provision

import com.block.wt.testutil.TestFileHelper.deleteRecursive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class ConflictDetectionTest {

    @Test
    fun testDetectsVaultMetadataConflicts() {
        val dir = Files.createTempDirectory("conflict-detect-test")
        try {
            val vault = dir.resolve("vault")
            val worktree = dir.resolve("worktree")
            Files.createDirectories(vault)
            Files.createDirectories(worktree)

            // Create vault entries as symlinks pointing to real dirs
            val realIdea = dir.resolve("real-idea")
            Files.createDirectories(realIdea)
            Files.createSymbolicLink(vault.resolve(".idea"), realIdea)

            val realIjwb = dir.resolve("real-ijwb")
            Files.createDirectories(realIjwb)
            Files.createSymbolicLink(vault.resolve(".ijwb"), realIjwb)

            // Create conflicting directory in worktree for .idea only
            Files.createDirectories(worktree.resolve(".idea"))

            val conflicts = ProvisionMarkerService.detectConflicts(
                worktree, vault, listOf(".idea", ".ijwb")
            )

            assertEquals(1, conflicts.size)
            assertEquals(".idea", conflicts[0].relativePath)
            assertEquals(ConflictType.METADATA, conflicts[0].type)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testDetectsNestedVaultMetadataConflicts() {
        val dir = Files.createTempDirectory("conflict-nested-test")
        try {
            val vault = dir.resolve("vault")
            val worktree = dir.resolve("worktree")
            Files.createDirectories(vault)
            Files.createDirectories(worktree)

            // Create nested vault entry
            val realIdea = dir.resolve("real-idea")
            Files.createDirectories(realIdea)
            Files.createDirectories(vault.resolve("services/payments"))
            Files.createSymbolicLink(vault.resolve("services/payments/.idea"), realIdea)

            // Create conflicting path in worktree
            Files.createDirectories(worktree.resolve("services/payments/.idea"))

            val conflicts = ProvisionMarkerService.detectConflicts(
                worktree, vault, listOf(".idea")
            )

            assertEquals(1, conflicts.size)
            assertEquals("services/payments/.idea", conflicts[0].relativePath)
            assertEquals(ConflictType.METADATA, conflicts[0].type)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testDetectsBazelRealDirectoryConflicts() {
        val dir = Files.createTempDirectory("conflict-bazel-test")
        try {
            val worktree = dir.resolve("worktree")
            Files.createDirectories(worktree)

            // Create bazel-out as a real directory (not a symlink)
            Files.createDirectories(worktree.resolve("bazel-out"))

            // Create bazel-bin as a symlink (should NOT be a conflict)
            val bazelBinTarget = dir.resolve("bazel-bin-target")
            Files.createDirectories(bazelBinTarget)
            Files.createSymbolicLink(worktree.resolve("bazel-bin"), bazelBinTarget)

            val conflicts = ProvisionMarkerService.detectConflicts(
                worktree, null, emptyList()
            )

            assertEquals(1, conflicts.size)
            assertEquals("bazel-out", conflicts[0].relativePath)
            assertEquals(ConflictType.BAZEL_DIR, conflicts[0].type)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testDetectsNoConflictsWhenClean() {
        val dir = Files.createTempDirectory("conflict-clean-test")
        try {
            val vault = dir.resolve("vault")
            val worktree = dir.resolve("worktree")
            Files.createDirectories(vault)
            Files.createDirectories(worktree)

            // Vault has .idea symlink but worktree does not
            val realIdea = dir.resolve("real-idea")
            Files.createDirectories(realIdea)
            Files.createSymbolicLink(vault.resolve(".idea"), realIdea)

            val conflicts = ProvisionMarkerService.detectConflicts(
                worktree, vault, listOf(".idea")
            )

            assertTrue(conflicts.isEmpty())
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testDetectsNoConflictsWithNullVault() {
        val dir = Files.createTempDirectory("conflict-null-vault-test")
        try {
            val worktree = dir.resolve("worktree")
            Files.createDirectories(worktree)

            val conflicts = ProvisionMarkerService.detectConflicts(
                worktree, null, listOf(".idea")
            )

            assertTrue(conflicts.isEmpty())
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testDetectsBothMetadataAndBazelConflicts() {
        val dir = Files.createTempDirectory("conflict-both-test")
        try {
            val vault = dir.resolve("vault")
            val worktree = dir.resolve("worktree")
            Files.createDirectories(vault)
            Files.createDirectories(worktree)

            // Metadata conflict
            val realIdea = dir.resolve("real-idea")
            Files.createDirectories(realIdea)
            Files.createSymbolicLink(vault.resolve(".idea"), realIdea)
            Files.createDirectories(worktree.resolve(".idea"))

            // Bazel real dir conflict
            Files.createDirectories(worktree.resolve("bazel-out"))

            val conflicts = ProvisionMarkerService.detectConflicts(
                worktree, vault, listOf(".idea")
            )

            assertEquals(2, conflicts.size)
            val types = conflicts.map { it.type }.toSet()
            assertTrue(types.contains(ConflictType.METADATA))
            assertTrue(types.contains(ConflictType.BAZEL_DIR))
        } finally {
            deleteRecursive(dir)
        }
    }
}
