package com.block.wt.git

import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.file.Path

class GitBranchHelperTest {

    private val base: Path = Path.of("/tmp/worktrees")

    // --- sanitizeBranchName tests ---

    @Test
    fun sanitizeBranchName_simple() {
        assertEquals("main", GitBranchHelper.sanitizeBranchName("main"))
    }

    @Test
    fun sanitizeBranchName_trims() {
        assertEquals("feature", GitBranchHelper.sanitizeBranchName("  feature  "))
    }

    @Test(expected = IllegalArgumentException::class)
    fun sanitizeBranchName_rejectsPathTraversal() {
        GitBranchHelper.sanitizeBranchName("foo/../bar")
    }

    @Test(expected = IllegalArgumentException::class)
    fun sanitizeBranchName_rejectsDoubleDotAlone() {
        GitBranchHelper.sanitizeBranchName("..")
    }

    @Test(expected = IllegalArgumentException::class)
    fun sanitizeBranchName_rejectsBlank() {
        GitBranchHelper.sanitizeBranchName("   ")
    }

    @Test(expected = IllegalArgumentException::class)
    fun sanitizeBranchName_rejectsLeadingDash() {
        GitBranchHelper.sanitizeBranchName("-bad")
    }

    // --- worktreePathForBranch tests ---

    @Test
    fun worktreePathForBranch_simpleBranch() {
        assertEquals(
            Path.of("/tmp/worktrees/simple"),
            GitBranchHelper.worktreePathForBranch(base, "simple"),
        )
    }

    @Test
    fun worktreePathForBranch_slashedBranchCreatesNestedPath() {
        assertEquals(
            Path.of("/tmp/worktrees/feature/foo"),
            GitBranchHelper.worktreePathForBranch(base, "feature/foo"),
        )
    }

    @Test
    fun worktreePathForBranch_deeplyNestedBranch() {
        assertEquals(
            Path.of("/tmp/worktrees/a/b/c"),
            GitBranchHelper.worktreePathForBranch(base, "a/b/c"),
        )
    }

    @Test
    fun worktreePathForBranch_matchesCLIBehavior() {
        // CLI: worktree_path="${WT_WORKTREES_BASE%/}/$branch_name"
        // For branch "test/foo" and base "/tmp/worktrees", CLI produces "/tmp/worktrees/test/foo"
        assertEquals(
            Path.of("/tmp/worktrees/test/foo"),
            GitBranchHelper.worktreePathForBranch(base, "test/foo"),
        )
    }
}
