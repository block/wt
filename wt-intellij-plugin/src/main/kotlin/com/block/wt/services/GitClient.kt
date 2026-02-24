package com.block.wt.services

import com.block.wt.util.ProcessHelper
import com.block.wt.util.ProcessRunner
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.file.Path

class GitClient(private val processRunner: ProcessRunner) {

    suspend fun createWorktree(
        repoRoot: Path,
        path: Path,
        branch: String,
        createNewBranch: Boolean = false,
        onProgress: ((Double) -> Unit)? = null,
    ): Result<Unit> = withContext(Dispatchers.IO) {
        val args = mutableListOf("worktree", "add")
        if (createNewBranch) {
            args.add("-b")
            args.add(branch)
            args.add(path.toString())
        } else {
            args.add(path.toString())
            args.add(branch)
        }

        val result = if (onProgress != null && processRunner is ProcessHelper) {
            processRunner.runGitWithProgress(args, workingDir = repoRoot, onProgress = onProgress)
        } else {
            processRunner.runGit(args, workingDir = repoRoot)
        }
        if (result.isSuccess) {
            Result.success(Unit)
        } else {
            Result.failure(RuntimeException(result.stderr.ifBlank { "Failed to create worktree" }))
        }
    }

    suspend fun removeWorktree(repoRoot: Path, path: Path, force: Boolean = false): Result<Unit> =
        withContext(Dispatchers.IO) {
            val args = mutableListOf("worktree", "remove")
            if (force) args.add("--force")
            args.add(path.toString())

            val result = processRunner.runGit(args, workingDir = repoRoot)
            if (result.isSuccess) {
                Result.success(Unit)
            } else {
                Result.failure(RuntimeException(result.stderr.ifBlank { "Failed to remove worktree" }))
            }
        }

    suspend fun getMergedBranches(repoRoot: Path, baseBranch: String): List<String> =
        withContext(Dispatchers.IO) {
            val result = processRunner.runGit(
                listOf("branch", "--merged", baseBranch),
                workingDir = repoRoot,
            )
            if (!result.isSuccess) return@withContext emptyList()

            result.stdout.lines()
                .map { it.trim().removePrefix("* ") }
                .filter { it.isNotBlank() && it != baseBranch }
        }

    suspend fun hasUncommittedChanges(worktreePath: Path): Boolean = withContext(Dispatchers.IO) {
        val result = processRunner.runGit(
            listOf("status", "--porcelain"),
            workingDir = worktreePath,
        )
        result.isSuccess && result.stdout.isNotBlank()
    }

    suspend fun stashSave(worktreePath: Path, name: String): Result<Unit> = withContext(Dispatchers.IO) {
        val result = processRunner.runGit(
            listOf("stash", "push", "-m", name),
            workingDir = worktreePath,
        )
        if (result.isSuccess) Result.success(Unit)
        else Result.failure(RuntimeException(result.stderr))
    }

    suspend fun stashPop(worktreePath: Path, name: String): Result<Unit> = withContext(Dispatchers.IO) {
        val listResult = processRunner.runGit(
            listOf("stash", "list"),
            workingDir = worktreePath,
        )
        if (!listResult.isSuccess) return@withContext Result.failure(RuntimeException(listResult.stderr))

        val stashIndex = listResult.stdout.lines()
            .indexOfFirst { it.contains(name) }

        if (stashIndex < 0) return@withContext Result.success(Unit)

        val result = processRunner.runGit(
            listOf("stash", "pop", "stash@{$stashIndex}"),
            workingDir = worktreePath,
        )
        if (result.isSuccess) Result.success(Unit)
        else Result.failure(RuntimeException(result.stderr))
    }

    suspend fun checkout(worktreePath: Path, branchOrRev: String): Result<Unit> = withContext(Dispatchers.IO) {
        val result = processRunner.runGit(
            listOf("checkout", branchOrRev),
            workingDir = worktreePath,
        )
        if (result.isSuccess) Result.success(Unit)
        else Result.failure(RuntimeException(result.stderr))
    }

    suspend fun pullFfOnly(
        worktreePath: Path,
        onProgress: ((Double) -> Unit)? = null,
    ): Result<Unit> = withContext(Dispatchers.IO) {
        val args = listOf("pull", "--ff-only", "--progress")
        val result = if (onProgress != null && processRunner is ProcessHelper) {
            processRunner.runGitWithProgress(args, workingDir = worktreePath, onProgress = onProgress)
        } else {
            processRunner.runGit(args, workingDir = worktreePath)
        }
        if (result.isSuccess) Result.success(Unit)
        else Result.failure(RuntimeException(result.stderr))
    }

    suspend fun getCurrentBranch(worktreePath: Path): String? = withContext(Dispatchers.IO) {
        val result = processRunner.runGit(
            listOf("rev-parse", "--abbrev-ref", "HEAD"),
            workingDir = worktreePath,
        )
        if (result.isSuccess) result.stdout.trim().ifBlank { null } else null
    }

    suspend fun getCurrentRevision(worktreePath: Path): String? = withContext(Dispatchers.IO) {
        val result = processRunner.runGit(
            listOf("rev-parse", "HEAD"),
            workingDir = worktreePath,
        )
        if (result.isSuccess) result.stdout.trim().ifBlank { null } else null
    }
}
