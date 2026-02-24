package com.block.wt.provision

import com.block.wt.git.GitDirResolver
import com.block.wt.model.ProvisionEntry
import com.block.wt.model.ProvisionMarker
import com.google.gson.GsonBuilder
import com.intellij.openapi.diagnostic.Logger
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant

object ProvisionMarkerService {

    private val log = Logger.getInstance(ProvisionMarkerService::class.java)

    const val MARKER_FILE = "wt-provisioned"

    val IDE_METADATA_DIRS = listOf(".idea", ".ijwb", ".aswb", ".clwb", ".vscode")

    private val gson = GsonBuilder().setPrettyPrinting().create()

    /**
     * Fast check whether a worktree has been provisioned by any context.
     * No subprocess — reads the filesystem directly.
     */
    fun isProvisioned(worktreePath: Path): Boolean {
        val gitDir = GitDirResolver.resolveGitDir(worktreePath) ?: return false
        return Files.exists(gitDir.resolve(MARKER_FILE))
    }

    /**
     * Checks whether a worktree is currently provisioned by a specific context
     * (i.e. that context is the `current` provisioner).
     */
    fun isProvisionedByContext(worktreePath: Path, contextName: String): Boolean {
        val marker = readProvisionMarker(worktreePath) ?: return false
        return marker.current == contextName
    }

    /**
     * Reads and parses the provision marker file, returning null if not provisioned.
     */
    fun readProvisionMarker(worktreePath: Path): ProvisionMarker? {
        val gitDir = GitDirResolver.resolveGitDir(worktreePath) ?: return null
        val markerPath = gitDir.resolve(MARKER_FILE)
        if (!Files.exists(markerPath)) return null

        return try {
            val marker = gson.fromJson(Files.readString(markerPath), ProvisionMarker::class.java)
            // Gson can produce non-null Kotlin types with null values when JSON fields
            // are missing or null. The null checks below are runtime-necessary despite
            // Kotlin's type system saying they're redundant.
            @Suppress("SENSELESS_COMPARISON")
            if (marker == null || marker.current == null || marker.provisions == null) {
                log.warn("Incomplete provision marker for $worktreePath")
                null
            } else {
                marker
            }
        } catch (e: Exception) {
            log.warn("Failed to parse provision marker for $worktreePath", e)
            null
        }
    }

    /**
     * Writes (or updates) the provision marker for a worktree.
     * Sets the given context as `current` and adds/updates its entry in the provisions array.
     */
    fun writeProvisionMarker(worktreePath: Path, contextName: String): Result<Unit> {
        val gitDir = GitDirResolver.resolveGitDir(worktreePath)
            ?: return Result.failure(IllegalStateException("Cannot resolve git dir for $worktreePath"))
        val markerPath = gitDir.resolve(MARKER_FILE)

        val existing = readProvisionMarker(worktreePath)
        val now = Instant.now().toString()

        val provisions = (existing?.provisions?.filter { it.context != contextName } ?: emptyList()) +
            ProvisionEntry(context = contextName, provisionedAt = now, provisionedBy = "intellij-plugin")

        val marker = ProvisionMarker(current = contextName, provisions = provisions)
        return try {
            Files.writeString(markerPath, markerToJson(marker))
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Removes the provision marker for a worktree.
     * If contextName is null, deletes the entire marker file.
     * If non-null, removes just that context's entry; clears current if it matched;
     * if the array becomes empty, deletes the file.
     */
    fun removeProvisionMarker(worktreePath: Path, contextName: String? = null): Result<Unit> {
        val gitDir = GitDirResolver.resolveGitDir(worktreePath)
            ?: return Result.failure(IllegalStateException("Cannot resolve git dir for $worktreePath"))
        val markerPath = gitDir.resolve(MARKER_FILE)
        if (!Files.exists(markerPath)) return Result.success(Unit)

        if (contextName == null) {
            return try {
                Files.deleteIfExists(markerPath)
                Result.success(Unit)
            } catch (e: Exception) {
                Result.failure(e)
            }
        }

        val existing = readProvisionMarker(worktreePath) ?: return Result.success(Unit)
        val remaining = existing.provisions.filter { it.context != contextName }

        if (remaining.isEmpty()) {
            return try {
                Files.deleteIfExists(markerPath)
                Result.success(Unit)
            } catch (e: Exception) {
                Result.failure(e)
            }
        }

        val newCurrent = if (existing.current == contextName) remaining.last().context else existing.current
        val marker = ProvisionMarker(current = newCurrent, provisions = remaining)

        return try {
            Files.writeString(markerPath, markerToJson(marker))
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Checks whether a worktree already has IDE metadata directories (e.g. .idea/, .ijwb/).
     * Used to detect worktrees that were set up outside the provision flow and don't need
     * a full metadata import — just the provision marker.
     */
    fun hasExistingMetadata(worktreePath: Path): Boolean {
        for (pattern in IDE_METADATA_DIRS) {
            if (Files.isDirectory(worktreePath.resolve(pattern))) return true
        }
        return false
    }

    private fun markerToJson(marker: ProvisionMarker): String = gson.toJson(marker)
}
