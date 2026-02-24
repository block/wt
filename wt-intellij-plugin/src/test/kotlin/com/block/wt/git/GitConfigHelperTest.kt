package com.block.wt.git

import com.block.wt.model.ContextConfig
import com.block.wt.testutil.TestFileHelper.deleteRecursive
import com.block.wt.util.ProcessHelper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path

class GitConfigHelperTest {

    private fun createTempGitRepo(): Path {
        val dir = Files.createTempDirectory("gitconfig-test")
        ProcessHelper.runGit(listOf("init"), workingDir = dir)
        return dir
    }

    private fun setWtConfig(repoDir: Path, enabled: Boolean = true, extra: Map<String, String> = emptyMap()) {
        ProcessHelper.runGit(
            listOf("config", "--local", "wt.enabled", enabled.toString()),
            workingDir = repoDir,
        )
        for ((key, value) in extra) {
            ProcessHelper.runGit(
                listOf("config", "--local", "wt.$key", value),
                workingDir = repoDir,
            )
        }
    }

    @Test
    fun testReadConfigReturnsContextConfigWhenAllRequiredKeysPresent() {
        val dir = createTempGitRepo()
        try {
            setWtConfig(
                dir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt/worktrees",
                    "ideaFilesBase" to "/tmp/wt/idea-files",
                    "baseBranch" to "main",
                ),
            )

            val config = GitConfigHelper.readConfig(dir)
            assertNotNull(config)
            assertEquals(Path.of("/tmp/wt/worktrees"), config!!.worktreesBase)
            assertEquals(Path.of("/tmp/wt/idea-files"), config.ideaFilesBase)
            assertEquals("main", config.baseBranch)
            assertEquals(dir, config.mainRepoRoot)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigReturnsNullWhenEnabledIsFalse() {
        val dir = createTempGitRepo()
        try {
            setWtConfig(
                dir,
                enabled = false,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "ideaFilesBase" to "/tmp/idea",
                    "baseBranch" to "main",
                ),
            )

            val config = GitConfigHelper.readConfig(dir)
            assertNull(config)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigReturnsNullWhenEnabledIsMissing() {
        val dir = createTempGitRepo()
        try {
            // Don't set wt.enabled at all
            val config = GitConfigHelper.readConfig(dir)
            assertNull(config)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigReturnsNullWhenRequiredKeyMissing() {
        val dir = createTempGitRepo()
        try {
            // Missing ideaFilesBase
            setWtConfig(
                dir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "baseBranch" to "main",
                ),
            )

            val config = GitConfigHelper.readConfig(dir)
            assertNull(config)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigReturnsNullForNonGitDirectory() {
        val dir = Files.createTempDirectory("gitconfig-test-nogit")
        try {
            val config = GitConfigHelper.readConfig(dir)
            assertNull(config)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigHandlesOptionalActiveWorktree() {
        val dir = createTempGitRepo()
        try {
            setWtConfig(
                dir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "ideaFilesBase" to "/tmp/idea",
                    "baseBranch" to "main",
                    "activeWorktree" to "/tmp/active",
                ),
            )

            val config = GitConfigHelper.readConfig(dir)
            assertNotNull(config)
            assertEquals(Path.of("/tmp/active"), config!!.activeWorktree)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigDefaultsActiveWorktreeToMainRepoRoot() {
        val dir = createTempGitRepo()
        try {
            setWtConfig(
                dir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "ideaFilesBase" to "/tmp/idea",
                    "baseBranch" to "main",
                ),
            )

            val config = GitConfigHelper.readConfig(dir)
            assertNotNull(config)
            // activeWorktree defaults to mainRepoRoot when absent
            assertEquals(dir, config!!.activeWorktree)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigHandlesMetadataPatterns() {
        val dir = createTempGitRepo()
        try {
            setWtConfig(
                dir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "ideaFilesBase" to "/tmp/idea",
                    "baseBranch" to "main",
                    "metadataPatterns" to ".idea .ijwb .vscode",
                ),
            )

            val config = GitConfigHelper.readConfig(dir)
            assertNotNull(config)
            assertEquals(listOf(".idea", ".ijwb", ".vscode"), config!!.metadataPatterns)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigDefaultsEmptyMetadataPatterns() {
        val dir = createTempGitRepo()
        try {
            setWtConfig(
                dir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "ideaFilesBase" to "/tmp/idea",
                    "baseBranch" to "main",
                ),
            )

            val config = GitConfigHelper.readConfig(dir)
            assertNotNull(config)
            assertEquals(emptyList<String>(), config!!.metadataPatterns)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testWriteConfigSetsAllKeys() {
        val dir = createTempGitRepo()
        try {
            val config = ContextConfig(
                name = "test",
                mainRepoRoot = dir,
                worktreesBase = Path.of("/tmp/wt"),
                ideaFilesBase = Path.of("/tmp/idea"),
                baseBranch = "main",
                activeWorktree = Path.of("/tmp/active"),
                metadataPatterns = listOf(".idea", ".vscode"),
            )

            GitConfigHelper.writeConfig(dir, config)

            // Verify by reading back with git config
            fun gitGet(key: String): String? {
                val result = ProcessHelper.runGit(
                    listOf("config", "--local", "--get", key),
                    workingDir = dir,
                )
                return if (result.isSuccess) result.stdout.trim() else null
            }

            assertEquals("true", gitGet("wt.enabled"))
            assertEquals("test", gitGet("wt.contextName"))
            assertEquals("/tmp/wt", gitGet("wt.worktreesBase"))
            assertEquals("/tmp/idea", gitGet("wt.ideaFilesBase"))
            assertEquals("main", gitGet("wt.baseBranch"))
            assertEquals("/tmp/active", gitGet("wt.activeWorktree"))
            assertEquals(".idea .vscode", gitGet("wt.metadataPatterns"))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testWriteAndReadRoundTrip() {
        val dir = createTempGitRepo()
        try {
            // Use a name different from the dir name to verify wt.contextName round-trip
            val original = ContextConfig(
                name = "my-custom-context",
                mainRepoRoot = dir,
                worktreesBase = Path.of("/tmp/wt"),
                ideaFilesBase = Path.of("/tmp/idea"),
                baseBranch = "develop",
                activeWorktree = Path.of("/tmp/active"),
                metadataPatterns = listOf(".idea", ".ijwb"),
            )

            GitConfigHelper.writeConfig(dir, original)
            val read = GitConfigHelper.readConfig(dir)

            assertNotNull(read)
            assertEquals(original.name, read!!.name)
            assertEquals(original.worktreesBase, read.worktreesBase)
            assertEquals(original.ideaFilesBase, read.ideaFilesBase)
            assertEquals(original.baseBranch, read.baseBranch)
            assertEquals(original.activeWorktree, read.activeWorktree)
            assertEquals(original.metadataPatterns, read.metadataPatterns)
            assertEquals(original.mainRepoRoot, read.mainRepoRoot)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testIsEnabledReturnsTrueWhenEnabled() {
        val dir = createTempGitRepo()
        try {
            setWtConfig(dir, enabled = true)
            assertTrue(GitConfigHelper.isEnabled(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testIsEnabledReturnsFalseWhenDisabled() {
        val dir = createTempGitRepo()
        try {
            setWtConfig(dir, enabled = false)
            assertFalse(GitConfigHelper.isEnabled(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testIsEnabledReturnsFalseWhenAbsent() {
        val dir = createTempGitRepo()
        try {
            assertFalse(GitConfigHelper.isEnabled(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testIsEnabledReturnsFalseForNonGitDir() {
        val dir = Files.createTempDirectory("gitconfig-test-nogit")
        try {
            assertFalse(GitConfigHelper.isEnabled(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigFromLinkedWorktree() {
        val mainDir = createTempGitRepo()
        try {
            // Create an initial commit so we have a branch
            val readmeFile = mainDir.resolve("README.md").toFile()
            readmeFile.writeText("hello")
            ProcessHelper.runGit(listOf("add", "README.md"), workingDir = mainDir)
            ProcessHelper.runGit(listOf("commit", "-m", "initial"), workingDir = mainDir)

            // Set wt config on the main repo
            setWtConfig(
                mainDir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "ideaFilesBase" to "/tmp/idea",
                    "baseBranch" to "main",
                ),
            )

            // Simulate a linked worktree: create a dir with .git file pointing back
            val worktreeDir = Files.createTempDirectory("gitconfig-linked-wt")
            val mainGitDir = mainDir.resolve(".git")
            val worktreeGitDir = mainGitDir.resolve("worktrees").resolve("feature")
            Files.createDirectories(worktreeGitDir)
            Files.writeString(worktreeDir.resolve(".git"), "gitdir: $worktreeGitDir")

            val config = GitConfigHelper.readConfig(worktreeDir)
            assertNotNull(config)
            assertEquals(Path.of("/tmp/wt"), config!!.worktreesBase)
            assertEquals(mainDir, config.mainRepoRoot)

            deleteRecursive(worktreeDir)
        } finally {
            deleteRecursive(mainDir)
        }
    }

    @Test
    fun testPartialRequiredKeysReturnsNull() {
        val dir = createTempGitRepo()
        try {
            // Set only 2 of 3 required keys
            setWtConfig(
                dir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "baseBranch" to "main",
                    // Missing ideaFilesBase
                ),
            )

            val config = GitConfigHelper.readConfig(dir)
            assertNull(config)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testContextNameDerivesFromRepoBasenameStrippingSuffix() {
        val baseDir = Files.createTempDirectory("gitconfig-test")
        try {
            // Create a repo in a directory named "java-master"
            val repoDir = baseDir.resolve("java-master")
            Files.createDirectory(repoDir)
            ProcessHelper.runGit(listOf("init"), workingDir = repoDir)

            setWtConfig(
                repoDir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "ideaFilesBase" to "/tmp/idea",
                    "baseBranch" to "master",
                ),
            )

            val config = GitConfigHelper.readConfig(repoDir)
            assertNotNull(config)
            assertEquals("java", config!!.name)
        } finally {
            deleteRecursive(baseDir)
        }
    }

    @Test
    fun testRemoveAllConfigClearsAllKeys() {
        val dir = createTempGitRepo()
        try {
            setWtConfig(
                dir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "ideaFilesBase" to "/tmp/idea",
                    "baseBranch" to "main",
                    "activeWorktree" to "/tmp/active",
                    "metadataPatterns" to ".idea .vscode",
                ),
            )

            // Verify config is present
            assertNotNull(GitConfigHelper.readConfig(dir))
            assertTrue(GitConfigHelper.isEnabled(dir))

            // Remove all config
            GitConfigHelper.removeAllConfig(dir)

            // Verify everything is gone
            assertNull(GitConfigHelper.readConfig(dir))
            assertFalse(GitConfigHelper.isEnabled(dir))
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigUsesContextNameFromGitConfig() {
        val dir = createTempGitRepo()
        try {
            setWtConfig(
                dir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "ideaFilesBase" to "/tmp/idea",
                    "baseBranch" to "main",
                    "contextName" to "mycontext",
                ),
            )

            val config = GitConfigHelper.readConfig(dir)
            assertNotNull(config)
            // Name should come from wt.contextName, not dirname
            assertEquals("mycontext", config!!.name)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testReadConfigFallsBackToDirnameWhenContextNameAbsent() {
        val baseDir = Files.createTempDirectory("gitconfig-test")
        try {
            val repoDir = baseDir.resolve("myrepo-main")
            Files.createDirectory(repoDir)
            ProcessHelper.runGit(listOf("init"), workingDir = repoDir)

            setWtConfig(
                repoDir,
                extra = mapOf(
                    "worktreesBase" to "/tmp/wt",
                    "ideaFilesBase" to "/tmp/idea",
                    "baseBranch" to "main",
                ),
            )

            val config = GitConfigHelper.readConfig(repoDir)
            assertNotNull(config)
            // Falls back to dirname with -main stripped
            assertEquals("myrepo", config!!.name)
        } finally {
            deleteRecursive(baseDir)
        }
    }

    @Test
    fun testRemoveAllConfigOnNonGitDirIsNoOp() {
        val dir = Files.createTempDirectory("gitconfig-test-nogit")
        try {
            // Should not throw
            GitConfigHelper.removeAllConfig(dir)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testWriteConfigClearsMetadataPatternsWhenEmpty() {
        val dir = createTempGitRepo()
        try {
            // First write with patterns
            val configWithPatterns = ContextConfig(
                name = dir.fileName.toString(),
                mainRepoRoot = dir,
                worktreesBase = Path.of("/tmp/wt"),
                ideaFilesBase = Path.of("/tmp/idea"),
                baseBranch = "main",
                activeWorktree = dir,
                metadataPatterns = listOf(".idea", ".vscode"),
            )
            GitConfigHelper.writeConfig(dir, configWithPatterns)

            // Verify patterns are set
            var result = ProcessHelper.runGit(
                listOf("config", "--local", "--get", "wt.metadataPatterns"),
                workingDir = dir,
            )
            assertEquals(".idea .vscode", result.stdout.trim())

            // Now write with empty patterns — should clear the key
            val configNoPatterns = configWithPatterns.copy(metadataPatterns = emptyList())
            GitConfigHelper.writeConfig(dir, configNoPatterns)

            result = ProcessHelper.runGit(
                listOf("config", "--local", "--get", "wt.metadataPatterns"),
                workingDir = dir,
            )
            // Key should be unset (git config --get returns exit code 1 for missing keys)
            assertFalse(result.isSuccess)

            // Round-trip: readConfig should return empty list
            val read = GitConfigHelper.readConfig(dir)
            assertNotNull(read)
            assertEquals(emptyList<String>(), read!!.metadataPatterns)
        } finally {
            deleteRecursive(dir)
        }
    }
}
