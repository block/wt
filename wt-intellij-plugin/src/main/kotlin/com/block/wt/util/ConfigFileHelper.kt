package com.block.wt.util

import com.block.wt.model.ContextConfig
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.exists
import kotlin.io.path.readText
import kotlin.io.path.writeText

object ConfigFileHelper {

    private val KEY_PATTERN = Regex("""^(WT_[A-Z_]+)=["']?(.*?)["']?\s*$""")

    fun readConfig(confFile: Path): ContextConfig? {
        if (!confFile.exists()) return null

        val values = mutableMapOf<String, String>()
        for (line in Files.readAllLines(confFile)) {
            val match = KEY_PATTERN.matchEntire(line) ?: continue
            values[match.groupValues[1]] = match.groupValues[2]
        }

        val name = confFile.fileName.toString().removeSuffix(".conf")

        return ContextConfig(
            name = name,
            mainRepoRoot = PathHelper.expandTilde(values["WT_MAIN_REPO_ROOT"] ?: return null),
            worktreesBase = PathHelper.expandTilde(values["WT_WORKTREES_BASE"] ?: return null),
            activeWorktree = PathHelper.expandTilde(values["WT_ACTIVE_WORKTREE"] ?: return null),
            ideaFilesBase = PathHelper.expandTilde(values["WT_IDEA_FILES_BASE"] ?: return null),
            baseBranch = values["WT_BASE_BRANCH"] ?: "master",
            metadataPatterns = (values["WT_METADATA_PATTERNS"] ?: "")
                .split(" ")
                .filter { it.isNotBlank() },
        )
    }

    fun writeConfig(confFile: Path, config: ContextConfig) {
        Files.createDirectories(confFile.parent)
        confFile.writeText(
            buildString {
                appendLine("""WT_MAIN_REPO_ROOT="${config.mainRepoRoot}"""")
                appendLine("""WT_WORKTREES_BASE="${config.worktreesBase}"""")
                appendLine("""WT_ACTIVE_WORKTREE="${config.activeWorktree}"""")
                appendLine("""WT_IDEA_FILES_BASE="${config.ideaFilesBase}"""")
                appendLine("""WT_BASE_BRANCH="${config.baseBranch}"""")
                appendLine("""WT_METADATA_PATTERNS="${config.metadataPatterns.joinToString(" ")}"""")
            }
        )
    }

    /**
     * Reads the current context name from ~/.wt/current.
     * Returns null if the file doesn't exist or is empty.
     * Reads only the first line to match shell semantics (`head -1`).
     */
    fun readCurrentContext(file: Path = PathHelper.currentFile): String? {
        if (!file.exists()) return null
        return Files.newBufferedReader(file).use { it.readLine() }?.trim()?.ifEmpty { null }
    }

    /**
     * Writes the context name to ~/.wt/current.
     * Creates parent directory if needed.
     */
    fun writeCurrentContext(name: String, file: Path = PathHelper.currentFile) {
        Files.createDirectories(file.parent)
        file.writeText(buildString { appendLine(name) })
    }

    fun listConfigFiles(): List<Path> {
        val reposDir = PathHelper.reposDir
        if (!Files.isDirectory(reposDir)) return emptyList()
        return Files.list(reposDir).use { stream ->
            stream.filter { it.fileName.toString().endsWith(".conf") }
                .toList()
        }
    }
}
