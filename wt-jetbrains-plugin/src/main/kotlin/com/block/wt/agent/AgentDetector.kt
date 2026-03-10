package com.block.wt.agent

import com.intellij.openapi.diagnostic.Logger
import java.nio.file.Files
import java.nio.file.Path

object AgentDetector : AgentDetection {

    private val log = Logger.getInstance(AgentDetector::class.java)

    const val CLAUDE_PROJECTS_DIR = ".claude/projects"
    const val SESSION_ACTIVE_THRESHOLD_MS = 30L * 60 * 1000 // 30 minutes
    private val NON_ALNUM = Regex("[^a-zA-Z0-9]")

    /**
     * Detects working directories that have active Claude processes.
     * Uses `/usr/sbin/lsof` to find running `claude` processes and their cwds.
     * Falls back to scanning `~/.claude/projects/` for recent session files.
     */
    override fun detectActiveAgentDirs(): Set<Path> {
        val fromProcess = detectViaLsof()
        val fromSessions = detectViaSessions()
        return fromProcess + fromSessions
    }

    /**
     * Finds active Claude session IDs for a worktree by checking `.jsonl` transcripts
     * in `~/.claude/projects/<encoded-path>/` modified within the threshold.
     */
    override fun detectActiveSessionIds(worktreePath: Path): List<String> {
        return try {
            val projectDir = resolveProjectDir(worktreePath) ?: return emptyList()
            val cutoff = System.currentTimeMillis() - SESSION_ACTIVE_THRESHOLD_MS

            Files.list(projectDir).use { stream ->
                stream
                    .filter { it.fileName.toString().endsWith(".jsonl") }
                    .filter { Files.getLastModifiedTime(it).toMillis() > cutoff }
                    .map { it.fileName.toString().removeSuffix(".jsonl") }
                    .sorted(Comparator.reverseOrder())
                    .toList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /**
     * Detects active claude process cwds via lsof.
     * Uses full path `/usr/sbin/lsof` to avoid PATH issues in IntelliJ.
     * Returns empty set on failure (Windows, permission denied, lsof not found, etc.)
     */
    private fun detectViaLsof(): Set<Path> {
        if (isWindows()) return emptySet()

        return try {
            val lsofPath = if (Files.exists(Path.of("/usr/sbin/lsof"))) "/usr/sbin/lsof"
                else if (Files.exists(Path.of("/usr/bin/lsof"))) "/usr/bin/lsof"
                else "lsof"

            val process = ProcessBuilder(lsofPath, "-a", "-d", "cwd", "-c", "claude", "-Fn")
                .redirectErrorStream(true)
                .start()

            val output = process.inputStream.bufferedReader().readText()
            val exited = process.waitFor()
            if (exited != 0) return emptySet()

            output.lines()
                .filter { it.startsWith("n") && it.length > 1 }
                .mapNotNull { line ->
                    val pathStr = line.removePrefix("n")
                    if (pathStr == "/") return@mapNotNull null
                    try { Path.of(pathStr) } catch (_: Exception) { null }
                }
                .toSet()
        } catch (e: Exception) {
            log.debug("lsof detection failed, falling back to session files", e)
            emptySet()
        }
    }

    /**
     * Scans `~/.claude/projects/` for dirs with recently-modified session files.
     * Uses the correct encoding (all non-alphanumeric → `-`).
     */
    private fun detectViaSessions(): Set<Path> {
        return try {
            val projectsDir = claudeProjectsDir() ?: return emptySet()
            val cutoff = System.currentTimeMillis() - SESSION_ACTIVE_THRESHOLD_MS

            Files.list(projectsDir).use { stream ->
                stream.toList()
                    .filter { Files.isDirectory(it) }
                    .filter { dir -> hasRecentSession(dir, cutoff) }
                    .mapNotNull { dir -> decodeDirToPath(dir.fileName.toString()) }
                    .toSet()
            }
        } catch (e: Exception) {
            log.debug("Session-based detection failed", e)
            emptySet()
        }
    }

    private fun resolveProjectDir(worktreePath: Path): Path? {
        val projectsDir = claudeProjectsDir() ?: return null
        val encoded = encodePath(worktreePath)
        val dir = projectsDir.resolve(encoded)
        return if (Files.isDirectory(dir)) dir else null
    }

    private fun claudeProjectsDir(): Path? {
        val dir = Path.of(System.getProperty("user.home")).resolve(CLAUDE_PROJECTS_DIR)
        return if (Files.isDirectory(dir)) dir else null
    }

    private fun hasRecentSession(projectDir: Path, cutoff: Long): Boolean {
        return try {
            Files.list(projectDir).use { stream ->
                stream.anyMatch { file ->
                    file.fileName.toString().endsWith(".jsonl") &&
                        Files.getLastModifiedTime(file).toMillis() > cutoff
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    /** Claude Code encodes paths by replacing all non-alphanumeric chars with `-`. */
    private fun encodePath(path: Path): String = NON_ALNUM.replace(path.toString(), "-")

    /** Best-effort reverse of encodePath. Lossy, so we validate via round-trip. */
    private fun decodeDirToPath(encoded: String): Path? {
        if (isWindows()) return null
        val candidate = "/" + encoded.replace("-", "/")
        return try {
            val path = Path.of(candidate).normalize()
            if (Files.isDirectory(path) && encodePath(path) == encoded) path else null
        } catch (_: Exception) {
            null
        }
    }

    private fun isWindows(): Boolean = System.getProperty("os.name").lowercase().contains("win")
}
