package com.block.wt.services

import com.block.wt.model.MetadataPattern
import com.block.wt.progress.ProgressScope
import com.block.wt.util.PathHelper
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.service
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.file.FileVisitOption
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.BasicFileAttributes
import java.util.EnumSet

@Service(Service.Level.PROJECT)
class MetadataService(
    private val project: Project,
    private val cs: CoroutineScope,
) {
    private val log = Logger.getInstance(MetadataService::class.java)

    suspend fun exportMetadata(
        source: Path,
        vault: Path,
        patterns: List<String>,
    ): Result<Int> = withContext(Dispatchers.IO) {
        exportMetadataStatic(source, vault, patterns)
    }

    suspend fun importMetadata(
        vault: Path,
        target: Path,
        scope: ProgressScope? = null,
    ): Result<Int> = withContext(Dispatchers.IO) {
        try {
            if (!Files.isDirectory(vault)) {
                return@withContext Result.failure(
                    IllegalArgumentException("Vault directory does not exist: $vault")
                )
            }

            val entries = Files.list(vault).use { it.toList() }
            val total = entries.size
            var count = 0

            for ((i, entry) in entries.withIndex()) {
                scope?.fraction(i.toDouble() / total.coerceAtLeast(1))
                scope?.text2("${i + 1} / $total directories")

                val realPath = if (Files.isSymbolicLink(entry)) {
                    try {
                        entry.toRealPath()
                    } catch (_: Exception) {
                        log.warn("Broken symlink in vault: $entry, cleaning up")
                        Files.deleteIfExists(entry)
                        continue
                    }
                } else {
                    entry
                }

                if (!Files.isDirectory(realPath)) continue

                val targetDir = target.resolve(entry.fileName)
                copyDirectory(realPath, targetDir)
                count++
                log.info("Imported metadata: ${entry.fileName}")
            }

            scope?.text2("")
            scope?.fraction(1.0)
            Result.success(count)
        } catch (e: Exception) {
            log.error("Failed to import metadata", e)
            Result.failure(e)
        }
    }

    fun detectPatterns(repoPath: Path): List<String> {
        val found = mutableListOf<String>()
        for (pattern in MetadataPattern.KNOWN_PATTERNS) {
            val candidate = repoPath.resolve(pattern.name)
            if (Files.exists(candidate)) {
                found.add(pattern.name)
            }
        }
        return found
    }

    internal fun deduplicateNested(paths: List<Path>): List<Path> = deduplicateNestedStatic(paths)

    private fun copyDirectory(source: Path, target: Path) {
        // FOLLOW_LINKS so vault symlinks are resolved to actual content
        Files.walkFileTree(source, EnumSet.of(FileVisitOption.FOLLOW_LINKS), Int.MAX_VALUE,
            object : SimpleFileVisitor<Path>() {
                override fun preVisitDirectory(dir: Path, attrs: BasicFileAttributes): FileVisitResult {
                    val targetDir = target.resolve(source.relativize(dir))
                    Files.createDirectories(targetDir)
                    return FileVisitResult.CONTINUE
                }

                override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                    val targetFile = target.resolve(source.relativize(file))
                    try {
                        Files.copy(file, targetFile, StandardCopyOption.REPLACE_EXISTING)
                    } catch (e: java.nio.file.NoSuchFileException) {
                        log.warn("Skipping broken symlink during copy: $file")
                    }
                    return FileVisitResult.CONTINUE
                }

                override fun visitFileFailed(file: Path, exc: java.io.IOException): FileVisitResult {
                    log.warn("Failed to access file during copy, skipping: $file (${exc.message})")
                    return FileVisitResult.CONTINUE
                }
            })
    }

    companion object {
        private val staticLog = Logger.getInstance(MetadataService::class.java)

        fun getInstance(project: Project): MetadataService = project.service()

        fun exportMetadataStatic(
            source: Path,
            vault: Path,
            patterns: List<String>,
        ): Result<Int> {
            return try {
                Files.createDirectories(vault)

                val foundPaths = findMetadataDirsStatic(source, patterns)
                val deduplicated = deduplicateNestedStatic(foundPaths)

                var count = 0
                for (metaPath in deduplicated) {
                    val relative = source.relativize(metaPath)
                    val vaultLink = vault.resolve(relative)
                    Files.createDirectories(vaultLink.parent)

                    if (Files.isSymbolicLink(vaultLink)) {
                        Files.delete(vaultLink)
                    }

                    Files.createSymbolicLink(vaultLink, metaPath)
                    count++
                    staticLog.info("Exported metadata: vault/$relative -> $metaPath")
                }

                Result.success(count)
            } catch (e: Exception) {
                staticLog.error("Failed to export metadata", e)
                Result.failure(e)
            }
        }

        private fun findMetadataDirsStatic(
            source: Path,
            patterns: List<String>,
            maxDepth: Int = 5,
        ): List<Path> {
            val found = mutableListOf<Path>()
            Files.walkFileTree(source, emptySet(), maxDepth, object : SimpleFileVisitor<Path>() {
                override fun preVisitDirectory(dir: Path, attrs: BasicFileAttributes): FileVisitResult {
                    val name = dir.fileName?.toString() ?: return FileVisitResult.CONTINUE
                    if (name in patterns) {
                        found.add(dir)
                        return FileVisitResult.SKIP_SUBTREE
                    }
                    return FileVisitResult.CONTINUE
                }
            })
            return found
        }

        internal fun deduplicateNestedStatic(paths: List<Path>): List<Path> {
            val sorted = paths.sortedBy { it.nameCount }
            val kept = mutableListOf<Path>()
            for (path in sorted) {
                val isNested = kept.any { path.startsWith(it) }
                if (!isNested) {
                    kept.add(path)
                }
            }
            return kept
        }
    }
}
