package com.block.wt.services

import com.block.wt.model.MetadataPattern
import com.block.wt.util.ProcessHelper
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.service
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.exists
import kotlin.io.path.readText

@Service(Service.Level.PROJECT)
class BazelService(
    private val project: Project,
    private val cs: CoroutineScope,
) {
    private val log = Logger.getInstance(BazelService::class.java)

    companion object {
        val BAZEL_SYMLINKS = listOf("bazel-out", "bazel-bin", "bazel-testlogs", "bazel-genfiles")

        fun getInstance(project: Project): BazelService = project.service()
    }

    suspend fun installBazelSymlinks(
        mainRepo: Path,
        worktree: Path,
    ): Result<Int> = withContext(Dispatchers.IO) {
        try {
            var count = 0
            for (name in BAZEL_SYMLINKS) {
                val mainLink = mainRepo.resolve(name)
                if (!Files.isSymbolicLink(mainLink)) continue

                val target = Files.readSymbolicLink(mainLink)
                val worktreeLink = worktree.resolve(name)

                if (Files.exists(worktreeLink) || Files.isSymbolicLink(worktreeLink)) {
                    Files.delete(worktreeLink)
                }

                Files.createSymbolicLink(worktreeLink, target)
                count++
                log.info("Installed Bazel symlink: $name -> $target")
            }
            Result.success(count)
        } catch (e: Exception) {
            log.error("Failed to install Bazel symlinks", e)
            Result.failure(e)
        }
    }

    suspend fun refreshTargets(bazelDir: Path): Result<Path?> = withContext(Dispatchers.IO) {
        try {
            val projectViewFile = findProjectViewFile(bazelDir) ?: run {
                log.info("No .bazelproject file found in $bazelDir")
                return@withContext Result.success(null)
            }

            val directories = parseDirectoriesSection(projectViewFile)
            if (directories.isEmpty()) {
                log.info("No directories found in $projectViewFile")
                return@withContext Result.success(null)
            }

            val queryExpr = directories.joinToString(" + ") { "//\$it/..." }
            val fullQuery = "kind('.*', $queryExpr)"

            val workingDir = bazelDir.parent ?: bazelDir
            val result = ProcessHelper.run(
                listOf("bazel", "query", fullQuery, "--output=label", "--keep_going"),
                workingDir = workingDir,
                timeoutSeconds = 300,
            )

            if (!result.isSuccess && result.stdout.isBlank()) {
                return@withContext Result.failure(RuntimeException(result.stderr))
            }

            // Write targets file
            val targetsDir = bazelDir.resolve("targets")
            Files.createDirectories(targetsDir)

            val existingTargetsFile = Files.list(targetsDir).use { stream ->
                stream.filter { it.fileName.toString().startsWith("targets-") }
                    .findFirst()
                    .orElse(null)
            }

            val outputFile = existingTargetsFile ?: targetsDir.resolve("targets-${bazelDir.fileName}")
            val sortedTargets = result.stdout.lines()
                .filter { it.isNotBlank() }
                .sorted()
                .joinToString("\n")

            Files.writeString(outputFile, sortedTargets + "\n")
            log.info("Wrote ${sortedTargets.lines().size} targets to $outputFile")

            Result.success(outputFile)
        } catch (e: Exception) {
            log.error("Failed to refresh Bazel targets", e)
            Result.failure(e)
        }
    }

    suspend fun refreshAllBazelMetadata(repoPath: Path): Result<Int> = withContext(Dispatchers.IO) {
        try {
            var count = 0
            for (pattern in MetadataPattern.BAZEL_IDE_PATTERNS) {
                val bazelDir = repoPath.resolve(pattern)
                if (bazelDir.exists()) {
                    val result = refreshTargets(bazelDir)
                    result.fold(
                        onSuccess = { path -> if (path != null) count++ },
                        onFailure = { log.warn("Failed to refresh targets in $bazelDir", it) },
                    )
                }
            }
            Result.success(count)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private fun findProjectViewFile(bazelDir: Path): Path? {
        val projectView = bazelDir.resolve(".bazelproject")
        return if (projectView.exists()) projectView else null
    }

    internal fun parseDirectoriesSection(projectViewFile: Path): List<String> {
        val lines = projectViewFile.readText().lines()
        val directories = mutableListOf<String>()
        var inDirectoriesSection = false

        for (line in lines) {
            val trimmed = line.trim()
            when {
                trimmed == "directories:" -> inDirectoriesSection = true
                inDirectoriesSection && trimmed.isBlank() -> continue
                inDirectoriesSection && !trimmed.startsWith("#") && !trimmed.startsWith("-") -> {
                    if (trimmed.endsWith(":")) {
                        // New section started
                        break
                    }
                    directories.add(trimmed)
                }
            }
        }

        return directories
    }
}
