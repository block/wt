package com.block.wt.services

import com.block.wt.model.ContextConfig
import com.block.wt.util.PathHelper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Path

class ExternalChangeWatcherTest {

    private fun makeConfig(
        activeWorktree: Path = Path.of("/wt/repos/java/worktrees/guodong"),
        mainRepoRoot: Path = Path.of("/wt/repos/java/base"),
    ) = ContextConfig(
        name = "java",
        mainRepoRoot = mainRepoRoot,
        worktreesBase = Path.of("/wt/repos/java/worktrees"),
        activeWorktree = activeWorktree,
        ideaFilesBase = Path.of("/wt/repos/java/idea-files"),
        baseBranch = "master",
        metadataPatterns = emptyList(),
    )

    // --- isRelevantEvent tests ---

    @Test
    fun testConfFileChangeIsRelevant() {
        assertTrue(ExternalChangeWatcher.isRelevantEvent("java.conf", PathHelper.reposDir, null))
    }

    @Test
    fun testConfFileChangeInWrongDirIsNotRelevant() {
        val config = makeConfig()
        val gitDir = config.mainRepoRoot.resolve(".git")
        assertFalse(ExternalChangeWatcher.isRelevantEvent("something.conf", gitDir, config))
    }

    @Test
    fun testCurrentFileChangeIsRelevant() {
        assertTrue(ExternalChangeWatcher.isRelevantEvent("current", PathHelper.wtRoot, null))
    }

    @Test
    fun testCurrentFileChangeInWrongDirIsNotRelevant() {
        assertFalse(ExternalChangeWatcher.isRelevantEvent("current", Path.of("/some/dir"), null))
    }

    @Test
    fun testActiveWorktreeSymlinkChangeIsRelevant() {
        val config = makeConfig()
        assertTrue(
            ExternalChangeWatcher.isRelevantEvent("guodong", config.activeWorktree.parent, config)
        )
    }

    @Test
    fun testActiveWorktreeSymlinkChangeInWrongDirIsNotRelevant() {
        val config = makeConfig()
        assertFalse(
            ExternalChangeWatcher.isRelevantEvent("guodong", Path.of("/some/other/dir"), config)
        )
    }

    @Test
    fun testUnrelatedFileChangeIsNotRelevant() {
        val config = makeConfig()
        assertFalse(
            ExternalChangeWatcher.isRelevantEvent("unrelated.txt", Path.of("/some/dir"), config)
        )
    }

    @Test
    fun testGitWorktreesDirChangeIsRelevant() {
        val config = makeConfig()
        val gitWorktreesDir = config.mainRepoRoot.resolve(".git/worktrees")
        assertTrue(
            ExternalChangeWatcher.isRelevantEvent("feature-branch", gitWorktreesDir, config)
        )
    }

    @Test
    fun testGitConfigChangeIsRelevant() {
        val config = makeConfig()
        val gitDir = config.mainRepoRoot.resolve(".git")
        assertTrue(
            ExternalChangeWatcher.isRelevantEvent("config", gitDir, config)
        )
    }

    @Test
    fun testGitDirNonConfigChangeIsNotRelevant() {
        val config = makeConfig()
        val gitDir = config.mainRepoRoot.resolve(".git")
        assertFalse(
            ExternalChangeWatcher.isRelevantEvent("HEAD", gitDir, config)
        )
    }

    @Test
    fun testNullConfigStillDetectsConfAndCurrentChanges() {
        assertTrue(ExternalChangeWatcher.isRelevantEvent("foo.conf", PathHelper.reposDir, null))
        assertTrue(ExternalChangeWatcher.isRelevantEvent("current", PathHelper.wtRoot, null))
        assertFalse(ExternalChangeWatcher.isRelevantEvent("random.txt", null, null))
    }

    // --- buildWatchState tests ---

    @Test
    fun testBuildWatchStateIncludesActiveWorktreeFileName() {
        val config = makeConfig()
        val paths = setOf(Path.of("/wt"), Path.of("/wt/repos/java/worktrees"))
        val state = ExternalChangeWatcher.buildWatchState(config, paths)
        assertEquals("guodong", state.activeWorktreeFileName)
        assertEquals(paths, state.paths)
    }

    @Test
    fun testBuildWatchStateNullConfigReturnsNullFileName() {
        val state = ExternalChangeWatcher.buildWatchState(null, emptySet())
        assertEquals(null, state.activeWorktreeFileName)
    }

    @Test
    fun testBuildWatchStateDiffersWhenActiveWorktreeChanges() {
        val config1 = makeConfig(activeWorktree = Path.of("/wt/repos/java/worktrees/guodong"))
        val config2 = makeConfig(activeWorktree = Path.of("/wt/repos/java/worktrees/feature"))
        val paths = setOf(Path.of("/wt"))
        // Same paths, different activeWorktree filename → different state
        val state1 = ExternalChangeWatcher.buildWatchState(config1, paths)
        val state2 = ExternalChangeWatcher.buildWatchState(config2, paths)
        assertNotEquals(state1, state2)
    }

    @Test
    fun testBuildWatchStateSameWhenNothingChanges() {
        val config = makeConfig()
        val paths = setOf(Path.of("/wt"))
        val state1 = ExternalChangeWatcher.buildWatchState(config, paths)
        val state2 = ExternalChangeWatcher.buildWatchState(config, paths)
        assertEquals(state1, state2)
    }
}
