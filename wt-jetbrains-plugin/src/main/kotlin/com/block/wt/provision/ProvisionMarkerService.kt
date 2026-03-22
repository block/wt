package com.block.wt.provision

import com.block.wt.git.GitDirResolver
import com.block.wt.services.BazelService
import java.nio.file.FileVisitOption
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.attribute.BasicFileAttributes
import java.util.EnumSet

enum class ConflictType { METADATA, BAZEL_DIR }

data class ConflictInfo(val relativePath: String, val type: ConflictType)

object ProvisionMarkerService {

    private const val WT_DIR = "wt"
    private const val ADOPTED_FILE = "adopted"
    private const val LEGACY_JSON_FILE = "wt-provisioned"

    // Used by ContextSetupDialog to detect existing IDE metadata
    val IDE_METADATA_DIRS = listOf(".idea", ".ijwb", ".aswb", ".clwb", ".vscode")

    /**
     * Fast check whether a worktree has been adopted by any context.
     * Checks the new wt/adopted marker first, then falls back to legacy wt-provisioned.
     */
    fun isProvisioned(worktreePath: Path): Boolean {
        val gitDir = GitDirResolver.resolveGitDir(worktreePath) ?: return false
        return Files.exists(gitDir.resolve(WT_DIR).resolve(ADOPTED_FILE)) ||
            Files.exists(gitDir.resolve(LEGACY_JSON_FILE))
    }

    /**
     * Checks whether a worktree is currently adopted by a specific context.
     */
    fun isProvisionedByContext(worktreePath: Path, contextName: String): Boolean {
        val context = readAdoptedContext(worktreePath) ?: return false
        return context == contextName
    }

    /**
     * Reads the context name from the adoption marker.
     * Returns null if not adopted or if the marker exists but has no context info.
     */
    fun readAdoptedContext(worktreePath: Path): String? {
        val gitDir = GitDirResolver.resolveGitDir(worktreePath) ?: return null
        // Primary: read from wt/adopted
        val marker = gitDir.resolve(WT_DIR).resolve(ADOPTED_FILE)
        if (Files.exists(marker)) {
            val content = Files.readString(marker).trim()
            return content.ifEmpty { null }
        }
        // Fallback: read "current" from legacy JSON
        val legacy = gitDir.resolve(LEGACY_JSON_FILE)
        if (Files.exists(legacy)) {
            return readCurrentFromLegacyJson(legacy)
        }
        return null
    }

    /**
     * Writes the adoption marker for a worktree.
     * Stores the context name in plain text at <gitdir>/wt/adopted.
     * Cleans up legacy wt-provisioned JSON if present.
     */
    fun writeAdoptionMarker(worktreePath: Path, contextName: String): Result<Unit> = runCatching {
        val gitDir = GitDirResolver.resolveGitDir(worktreePath)
            ?: throw IllegalStateException("Cannot resolve git dir for $worktreePath")
        val wtDir = gitDir.resolve(WT_DIR)
        Files.createDirectories(wtDir)
        Files.writeString(wtDir.resolve(ADOPTED_FILE), contextName + "\n")
        // Clean up legacy JSON marker
        Files.deleteIfExists(gitDir.resolve(LEGACY_JSON_FILE))
    }

    /**
     * Removes the adoption marker for a worktree.
     * Cleans up both wt/adopted and legacy wt-provisioned.
     */
    fun removeAdoptionMarker(worktreePath: Path): Result<Unit> = runCatching {
        val gitDir = GitDirResolver.resolveGitDir(worktreePath)
            ?: throw IllegalStateException("Cannot resolve git dir for $worktreePath")
        val wtDir = gitDir.resolve(WT_DIR)
        Files.deleteIfExists(wtDir.resolve(ADOPTED_FILE))
        runCatching { Files.delete(wtDir) } // remove wt/ dir if empty, ignore if not
        Files.deleteIfExists(gitDir.resolve(LEGACY_JSON_FILE))
    }

    /**
     * Checks whether a worktree already has IDE metadata directories.
     */
    fun hasExistingMetadata(worktreePath: Path): Boolean =
        IDE_METADATA_DIRS.any { Files.isDirectory(worktreePath.resolve(it)) }

    /**
     * Detects conflicts in a worktree by scanning the vault for metadata
     * matching the given patterns and checking for Bazel real directories.
     *
     * Pass 1: Walk the vault with FOLLOW_LINKS, match pattern names,
     *         check if corresponding target path exists in the worktree.
     * Pass 2: Check bazel-out, bazel-bin, etc. as real directories (not symlinks).
     */
    fun detectConflicts(
        worktreePath: Path,
        vault: Path?,
        patterns: List<String>,
    ): List<ConflictInfo> {
        val conflicts = mutableListOf<ConflictInfo>()
        val patternSet = patterns.toSet()

        // Pass 1: Vault metadata scan
        if (vault != null && Files.isDirectory(vault)) {
            Files.walkFileTree(vault, EnumSet.of(FileVisitOption.FOLLOW_LINKS), Int.MAX_VALUE,
                object : SimpleFileVisitor<Path>() {
                    override fun preVisitDirectory(dir: Path, attrs: BasicFileAttributes): FileVisitResult {
                        if (dir == vault) return FileVisitResult.CONTINUE
                        val name = dir.fileName?.toString() ?: return FileVisitResult.CONTINUE
                        if (name in patternSet) {
                            val relativePath = vault.relativize(dir).toString()
                            val targetPath = worktreePath.resolve(relativePath)
                            if (Files.exists(targetPath) || Files.isSymbolicLink(targetPath)) {
                                conflicts.add(ConflictInfo(relativePath, ConflictType.METADATA))
                            }
                            return FileVisitResult.SKIP_SUBTREE
                        }
                        return FileVisitResult.CONTINUE
                    }

                    override fun visitFileFailed(file: Path, exc: java.io.IOException): FileVisitResult {
                        return FileVisitResult.CONTINUE
                    }
                })
        }

        // Pass 2: Bazel real directories
        for (name in BazelService.BAZEL_SYMLINKS) {
            val target = worktreePath.resolve(name)
            if (Files.isDirectory(target) && !Files.isSymbolicLink(target)) {
                conflicts.add(ConflictInfo(name, ConflictType.BAZEL_DIR))
            }
        }

        return conflicts
    }

    private fun readCurrentFromLegacyJson(jsonFile: Path): String? {
        val content = Files.readString(jsonFile)
        val match = Regex(""""current"\s*:\s*"([^"]+)"""").find(content)
        return match?.groupValues?.get(1)
    }
}
