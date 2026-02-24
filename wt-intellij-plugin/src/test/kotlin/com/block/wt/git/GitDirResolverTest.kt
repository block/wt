package com.block.wt.git

import com.block.wt.testutil.TestFileHelper.deleteRecursive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path

class GitDirResolverTest {

    @Test
    fun testMainWorktreeWithDotGitDirectory() {
        val dir = Files.createTempDirectory("gitdir-test")
        try {
            val dotGit = dir.resolve(".git")
            Files.createDirectory(dotGit)

            val result = GitDirResolver.resolveGitDir(dir)
            assertNotNull(result)
            assertEquals(dotGit, result)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testLinkedWorktreeWithAbsoluteGitdir() {
        val dir = Files.createTempDirectory("gitdir-test")
        try {
            val gitWorktreeDir = dir.resolve("main-repo").resolve(".git").resolve("worktrees").resolve("feature")
            Files.createDirectories(gitWorktreeDir)

            val worktree = dir.resolve("worktree")
            Files.createDirectory(worktree)
            Files.writeString(worktree.resolve(".git"), "gitdir: $gitWorktreeDir")

            val result = GitDirResolver.resolveGitDir(worktree)
            assertNotNull(result)
            assertEquals(gitWorktreeDir, result)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testLinkedWorktreeWithRelativeGitdir() {
        val dir = Files.createTempDirectory("gitdir-test")
        try {
            val mainRepo = dir.resolve("repo")
            val gitWorktreeDir = mainRepo.resolve(".git").resolve("worktrees").resolve("feature")
            Files.createDirectories(gitWorktreeDir)

            val worktree = dir.resolve("worktree")
            Files.createDirectory(worktree)

            // Write a relative gitdir path
            val relativePath = worktree.relativize(gitWorktreeDir)
            Files.writeString(worktree.resolve(".git"), "gitdir: $relativePath")

            val result = GitDirResolver.resolveGitDir(worktree)
            assertNotNull(result)
            // The resolved path should be normalized and point to the same directory
            assertEquals(gitWorktreeDir.toRealPath(), result!!.toRealPath())
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testNoDotGitReturnsNull() {
        val dir = Files.createTempDirectory("gitdir-test")
        try {
            val result = GitDirResolver.resolveGitDir(dir)
            assertNull(result)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testMalformedGitFileReturnsNull() {
        val dir = Files.createTempDirectory("gitdir-test")
        try {
            Files.writeString(dir.resolve(".git"), "not a gitdir pointer")
            val result = GitDirResolver.resolveGitDir(dir)
            assertNull(result)
        } finally {
            deleteRecursive(dir)
        }
    }

    @Test
    fun testUnreadableGitFileReturnsNull() {
        val dir = Files.createTempDirectory("gitdir-test")
        try {
            val dotGit = dir.resolve(".git")
            Files.writeString(dotGit, "gitdir: /some/path")
            dotGit.toFile().setReadable(false)

            val result = GitDirResolver.resolveGitDir(dir)
            assertNull(result)
        } finally {
            // Restore permissions for cleanup
            dir.resolve(".git").toFile().setReadable(true)
            deleteRecursive(dir)
        }
    }

    @Test
    fun testEmptyGitFileReturnsNull() {
        val dir = Files.createTempDirectory("gitdir-test")
        try {
            Files.writeString(dir.resolve(".git"), "")
            val result = GitDirResolver.resolveGitDir(dir)
            assertNull(result)
        } finally {
            deleteRecursive(dir)
        }
    }

}
