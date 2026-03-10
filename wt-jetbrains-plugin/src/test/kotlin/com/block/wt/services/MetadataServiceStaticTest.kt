package com.block.wt.services

import com.block.wt.testutil.TestFileHelper.deleteRecursive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path

class MetadataServiceStaticTest {

    @Test
    fun testExportCreatesSymlinksInVault() {
        val dir = Files.createTempDirectory("metadata-test")
        try {
            val source = dir.resolve("repo")
            val vault = dir.resolve("vault")
            Files.createDirectories(source)

            // Create metadata directories
            Files.createDirectories(source.resolve(".idea"))
            Files.createFile(source.resolve(".idea").resolve("workspace.xml"))
            Files.createDirectories(source.resolve(".vscode"))
            Files.createFile(source.resolve(".vscode").resolve("settings.json"))

            val result = MetadataService.exportMetadataStatic(source, vault, listOf(".idea", ".vscode"))
            assertTrue(result.isSuccess)
            assertEquals(2, result.getOrThrow())

            // Vault should contain symlinks
            assertTrue(Files.isSymbolicLink(vault.resolve(".idea")))
            assertTrue(Files.isSymbolicLink(vault.resolve(".vscode")))

            // Symlinks should point to the source directories
            assertEquals(source.resolve(".idea"), Files.readSymbolicLink(vault.resolve(".idea")))
            assertEquals(source.resolve(".vscode"), Files.readSymbolicLink(vault.resolve(".vscode")))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testExportWithNoMatchingPatternsReturnsZero() {
        val dir = Files.createTempDirectory("metadata-test")
        try {
            val source = dir.resolve("repo")
            val vault = dir.resolve("vault")
            Files.createDirectories(source)

            val result = MetadataService.exportMetadataStatic(source, vault, listOf(".idea"))
            assertTrue(result.isSuccess)
            assertEquals(0, result.getOrThrow())
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testExportReplacesExistingSymlinks() {
        val dir = Files.createTempDirectory("metadata-test")
        try {
            val source = dir.resolve("repo")
            val vault = dir.resolve("vault")
            Files.createDirectories(source)
            Files.createDirectories(vault)
            Files.createDirectories(source.resolve(".idea"))

            // Create an existing symlink pointing somewhere else
            val oldTarget = dir.resolve("old-target")
            Files.createDirectories(oldTarget)
            Files.createSymbolicLink(vault.resolve(".idea"), oldTarget)

            val result = MetadataService.exportMetadataStatic(source, vault, listOf(".idea"))
            assertTrue(result.isSuccess)
            assertEquals(1, result.getOrThrow())

            // Symlink should now point to the new source
            assertEquals(source.resolve(".idea"), Files.readSymbolicLink(vault.resolve(".idea")))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testExportCreatesVaultDirectoryIfNotExists() {
        val dir = Files.createTempDirectory("metadata-test")
        try {
            val source = dir.resolve("repo")
            val vault = dir.resolve("vault").resolve("nested")
            Files.createDirectories(source)
            Files.createDirectories(source.resolve(".idea"))

            val result = MetadataService.exportMetadataStatic(source, vault, listOf(".idea"))
            assertTrue(result.isSuccess)
            assertTrue(Files.isDirectory(vault))
        } finally {
            deleteRecursive(dir)
        }
    }

}
