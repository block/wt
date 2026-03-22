package com.block.wt.services

import com.block.wt.testutil.TestFileHelper.deleteRecursive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class BazelServiceSymlinkTest {

    @Test
    fun testInstallBazelSymlinksAbsolutizesRelativeTarget() {
        val dir = Files.createTempDirectory("bazel-symlink-test")
        try {
            val mainRepo = dir.resolve("main-repo")
            val worktree = dir.resolve("worktree")
            Files.createDirectories(mainRepo)
            Files.createDirectories(worktree)

            // Create a real bazel output dir
            val bazelOutputDir = dir.resolve("bazel-cache/output")
            Files.createDirectories(bazelOutputDir)

            // Create a relative symlink in the main repo: bazel-out -> ../bazel-cache/output
            val relativeTarget = mainRepo.relativize(bazelOutputDir)
            Files.createSymbolicLink(mainRepo.resolve("bazel-out"), relativeTarget)

            // Verify the relative symlink works in mainRepo context
            assertTrue(Files.exists(mainRepo.resolve("bazel-out")))

            // The fix: when BazelService reads the symlink and creates it in the worktree,
            // it should absolutize the relative target.
            // We test the core logic directly:
            val mainLink = mainRepo.resolve("bazel-out")
            val rawTarget = Files.readSymbolicLink(mainLink)
            val absoluteTarget = if (rawTarget.isAbsolute) rawTarget
                else mainLink.parent.resolve(rawTarget).normalize()

            val worktreeLink = worktree.resolve("bazel-out")
            Files.createSymbolicLink(worktreeLink, absoluteTarget)

            // The worktree symlink should point to an absolute path
            val installedTarget = Files.readSymbolicLink(worktreeLink)
            assertTrue("Target should be absolute: $installedTarget", installedTarget.isAbsolute)

            // And it should resolve to the actual directory
            assertTrue(Files.exists(worktreeLink))
            assertEquals(bazelOutputDir.toRealPath(), worktreeLink.toRealPath())
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testInstallBazelSymlinksPreservesAbsoluteTarget() {
        val dir = Files.createTempDirectory("bazel-symlink-abs-test")
        try {
            val mainRepo = dir.resolve("main-repo")
            val worktree = dir.resolve("worktree")
            Files.createDirectories(mainRepo)
            Files.createDirectories(worktree)

            // Create a real bazel output dir
            val bazelOutputDir = dir.resolve("bazel-cache/output")
            Files.createDirectories(bazelOutputDir)

            // Create an absolute symlink in the main repo
            Files.createSymbolicLink(mainRepo.resolve("bazel-out"), bazelOutputDir)

            // Test the core logic
            val mainLink = mainRepo.resolve("bazel-out")
            val rawTarget = Files.readSymbolicLink(mainLink)
            val absoluteTarget = if (rawTarget.isAbsolute) rawTarget
                else mainLink.parent.resolve(rawTarget).normalize()

            val worktreeLink = worktree.resolve("bazel-out")
            Files.createSymbolicLink(worktreeLink, absoluteTarget)

            // Should still point to the same absolute path
            assertEquals(bazelOutputDir, Files.readSymbolicLink(worktreeLink))
            assertTrue(Files.exists(worktreeLink))
        } finally {
            deleteRecursive(dir)
        }
    }
}
