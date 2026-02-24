package com.block.wt.util

import com.block.wt.model.ContextConfig
import com.block.wt.testutil.TestFileHelper.deleteRecursive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path

class ConfigFileHelperTest {

    @Test
    fun testReadConfig() {
        val dir = Files.createTempDirectory("config-test")
        try {
            val confFile = dir.resolve("java.conf")
            Files.writeString(
                confFile,
                """
                WT_MAIN_REPO_ROOT="/Users/test/java-master"
                WT_WORKTREES_BASE="/Users/test/.wt/repos/java/worktrees"
                WT_ACTIVE_WORKTREE="/Users/test/java"
                WT_IDEA_FILES_BASE="/Users/test/.wt/repos/java/idea-files"
                WT_BASE_BRANCH="master"
                WT_METADATA_PATTERNS=".bazelbsp .ijwb .vscode .run .idea"
                """.trimIndent()
            )

            val config = ConfigFileHelper.readConfig(confFile)
            assertNotNull(config)
            assertEquals("java", config!!.name)
            assertEquals(Path.of("/Users/test/java-master"), config.mainRepoRoot)
            assertEquals(Path.of("/Users/test/.wt/repos/java/worktrees"), config.worktreesBase)
            assertEquals(Path.of("/Users/test/java"), config.activeWorktree)
            assertEquals(Path.of("/Users/test/.wt/repos/java/idea-files"), config.ideaFilesBase)
            assertEquals("master", config.baseBranch)
            assertEquals(listOf(".bazelbsp", ".ijwb", ".vscode", ".run", ".idea"), config.metadataPatterns)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigWithDoubleQuotes() {
        val dir = Files.createTempDirectory("config-test")
        try {
            val confFile = dir.resolve("test.conf")
            Files.writeString(
                confFile,
                """
                WT_MAIN_REPO_ROOT="/path/with spaces/repo"
                WT_WORKTREES_BASE="/path/worktrees"
                WT_ACTIVE_WORKTREE="/path/active"
                WT_IDEA_FILES_BASE="/path/vault"
                WT_BASE_BRANCH="main"
                WT_METADATA_PATTERNS=".idea"
                """.trimIndent()
            )

            val config = ConfigFileHelper.readConfig(confFile)
            assertNotNull(config)
            assertEquals(Path.of("/path/with spaces/repo"), config!!.mainRepoRoot)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigMissingFile() {
        val config = ConfigFileHelper.readConfig(Path.of("/nonexistent/path.conf"))
        assertNull(config)
    }

    @Test
    fun testReadConfigMissingRequiredField() {
        val dir = Files.createTempDirectory("config-test")
        try {
            val confFile = dir.resolve("bad.conf")
            Files.writeString(
                confFile,
                """
                WT_BASE_BRANCH="main"
                """.trimIndent()
            )

            val config = ConfigFileHelper.readConfig(confFile)
            assertNull(config)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testWriteAndReadRoundTrip() {
        val dir = Files.createTempDirectory("config-test")
        try {
            val confFile = dir.resolve("roundtrip.conf")

            val original = ContextConfig(
                name = "roundtrip",
                mainRepoRoot = Path.of("/Users/test/repo"),
                worktreesBase = Path.of("/Users/test/worktrees"),
                activeWorktree = Path.of("/Users/test/active"),
                ideaFilesBase = Path.of("/Users/test/vault"),
                baseBranch = "main",
                metadataPatterns = listOf(".idea", ".vscode"),
            )

            ConfigFileHelper.writeConfig(confFile, original)
            val read = ConfigFileHelper.readConfig(confFile)

            assertNotNull(read)
            assertEquals(original.mainRepoRoot, read!!.mainRepoRoot)
            assertEquals(original.worktreesBase, read.worktreesBase)
            assertEquals(original.activeWorktree, read.activeWorktree)
            assertEquals(original.ideaFilesBase, read.ideaFilesBase)
            assertEquals(original.baseBranch, read.baseBranch)
            assertEquals(original.metadataPatterns, read.metadataPatterns)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testWriteConfigEmptyPatterns() {
        val dir = Files.createTempDirectory("config-test")
        try {
            val confFile = dir.resolve("empty.conf")

            val config = ContextConfig(
                name = "empty",
                mainRepoRoot = Path.of("/repo"),
                worktreesBase = Path.of("/wt"),
                activeWorktree = Path.of("/active"),
                ideaFilesBase = Path.of("/vault"),
                baseBranch = "main",
                metadataPatterns = emptyList(),
            )

            ConfigFileHelper.writeConfig(confFile, config)
            val read = ConfigFileHelper.readConfig(confFile)
            assertNotNull(read)
            assertEquals(emptyList<String>(), read!!.metadataPatterns)
        } finally {
            deleteRecursive(dir)
        }
    }

}
