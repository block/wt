package com.block.wt.progress

import com.block.wt.services.WorktreeService
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.nio.file.Files
import java.nio.file.Path

object RemovalProgress {

    /**
     * Removes a worktree while polling file count for progress.
     *
     * Counts files before removal, launches a polling coroutine that updates
     * `scope.fraction` based on (deleted / total), then invokes `git worktree remove`.
     * Poll interval is 250ms -- a compromise between responsiveness and I/O cost.
     */
    suspend fun removeWithProgress(
        scope: ProgressScope,
        path: Path,
        worktreeService: WorktreeService,
        force: Boolean = false,
    ): Result<Unit> {
        val totalFiles = countFiles(path)
        if (totalFiles == 0L) {
            return worktreeService.removeWorktree(path, force = force)
        }

        return coroutineScope {
            val monitorJob = launch {
                while (isActive) {
                    delay(250)
                    val remaining = countFiles(path)
                    val deleted = totalFiles - remaining
                    if (deleted > 0) {
                        scope.fraction(deleted.toDouble() / totalFiles)
                        scope.text2("$deleted / $totalFiles files removed")
                    }
                    if (remaining == 0L) break
                }
            }

            val result = worktreeService.removeWorktree(path, force = force)
            monitorJob.cancel()
            scope.text2("")
            scope.fraction(1.0)
            result
        }
    }

    fun countFiles(dir: Path): Long {
        if (!Files.isDirectory(dir)) return 0
        return try {
            Files.walk(dir).use { stream -> stream.count() }
        } catch (_: Exception) {
            0
        }
    }
}
