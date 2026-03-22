package com.block.wt.services

import com.block.wt.testutil.TestFileHelper.deleteRecursive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class MetadataServiceVaultSweepTest {

    @Test
    fun testExportSweepsStaleSymlinksForConfiguredPatterns() {
        val dir = Files.createTempDirectory("vault-sweep-test")
        try {
            val source = dir.resolve("repo")
            val vault = dir.resolve("vault")
            Files.createDirectories(source)

            // First export: .idea + .ijwb
            Files.createDirectories(source.resolve(".idea"))
            Files.createFile(source.resolve(".idea").resolve("workspace.xml"))
            Files.createDirectories(source.resolve(".ijwb"))
            Files.createFile(source.resolve(".ijwb").resolve("project.xml"))

            val result1 = MetadataService.exportMetadataStatic(source, vault, listOf(".idea", ".ijwb"))
            assertTrue(result1.isSuccess)
            assertEquals(2, result1.getOrThrow())
            assertTrue(Files.isSymbolicLink(vault.resolve(".idea")))
            assertTrue(Files.isSymbolicLink(vault.resolve(".ijwb")))

            // Remove .ijwb from source, re-export with only .idea
            deleteRecursive(source.resolve(".ijwb"))

            val result2 = MetadataService.exportMetadataStatic(source, vault, listOf(".idea", ".ijwb"))
            assertTrue(result2.isSuccess)
            assertEquals(1, result2.getOrThrow())

            // .idea should still exist, .ijwb should be swept
            assertTrue(Files.isSymbolicLink(vault.resolve(".idea")))
            assertFalse(Files.exists(vault.resolve(".ijwb")))
            assertFalse(Files.isSymbolicLink(vault.resolve(".ijwb")))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testExportSweepsNestedStaleSymlinks() {
        val dir = Files.createTempDirectory("vault-sweep-nested-test")
        try {
            val source = dir.resolve("repo")
            val vault = dir.resolve("vault")
            Files.createDirectories(source)

            // Create nested structure: services/payments/.idea
            Files.createDirectories(source.resolve("services/payments/.idea"))
            Files.createFile(source.resolve("services/payments/.idea").resolve("workspace.xml"))

            val result1 = MetadataService.exportMetadataStatic(source, vault, listOf(".idea"))
            assertTrue(result1.isSuccess)
            assertEquals(1, result1.getOrThrow())
            assertTrue(Files.isSymbolicLink(vault.resolve("services/payments/.idea")))

            // Remove the nested .idea, re-export
            deleteRecursive(source.resolve("services/payments/.idea"))

            val result2 = MetadataService.exportMetadataStatic(source, vault, listOf(".idea"))
            assertTrue(result2.isSuccess)
            assertEquals(0, result2.getOrThrow())

            // Stale symlink should be swept and empty parent dirs cleaned up
            assertFalse(Files.exists(vault.resolve("services/payments/.idea")))
            assertFalse(Files.exists(vault.resolve("services/payments")))
            assertFalse(Files.exists(vault.resolve("services")))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testExportSweepDoesNotRemoveNonPatternFiles() {
        val dir = Files.createTempDirectory("vault-sweep-preserve-test")
        try {
            val source = dir.resolve("repo")
            val vault = dir.resolve("vault")
            Files.createDirectories(source)
            Files.createDirectories(vault)

            // Create a non-pattern file in vault
            Files.writeString(vault.resolve("notes.txt"), "keep me")

            Files.createDirectories(source.resolve(".idea"))

            val result = MetadataService.exportMetadataStatic(source, vault, listOf(".idea"))
            assertTrue(result.isSuccess)

            // Non-pattern file should still exist
            assertTrue(Files.exists(vault.resolve("notes.txt")))
        } finally {
            deleteRecursive(dir)
        }
    }
}
