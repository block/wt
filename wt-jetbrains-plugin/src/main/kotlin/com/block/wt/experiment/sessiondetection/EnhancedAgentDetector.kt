package com.block.wt.experiment.sessiondetection

import com.block.wt.agent.AgentDetection
import com.block.wt.agent.ClaudeSessionPaths
import com.block.wt.experiment.terminalnav.TerminalNavigator
import com.block.wt.util.PlatformUtil
import com.intellij.openapi.diagnostic.Logger
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.ConcurrentHashMap

/**
 * Enhanced agent detection with lock file PID validation, tiered thresholds,
 * and file size growth tracking. Implements [AgentDetection] for backward compat
 * and adds [detectAgentSessions] for richer session info.
 */
class EnhancedAgentDetector(
    private val delegate: AgentDetection,
    private val clock: () -> Long = System::currentTimeMillis,
) : AgentDetection by delegate {

    private val log = Logger.getInstance(EnhancedAgentDetector::class.java)

    companion object {
        const val ACTIVE_WRITE_THRESHOLD_MS = 60L * 1000
        const val IDLE_THRESHOLD_MS = 10L * 60 * 1000
        private const val CLAUDE_IDE_DIR = ".claude/ide"
    }

    private val fileSizeCache = ConcurrentHashMap<Path, Long>()

    fun detectAgentSessions(worktreePath: Path): List<AgentSessionInfo> {
        val now = clock()
        val alivePids = collectAlivePids(worktreePath)
        val pidToTty = doResolveTtys(alivePids)
        val pidToTerminal = resolveTerminalKinds(alivePids)
        val sessionFiles = doListSessionFiles(worktreePath)

        // Build candidate sessions sorted by recency (most recent first)
        val candidates = sessionFiles.mapNotNull { file ->
            buildSessionCandidate(file, now)
        }.sortedByDescending { it.lastModified }

        // Assign PIDs to sessions: most recent session gets first PID, etc.
        val remainingPids = alivePids.toMutableSet()
        val sessions = mutableListOf<AgentSessionInfo>()

        for (candidate in candidates) {
            val assignedPid = if (remainingPids.isNotEmpty()) {
                remainingPids.first().also { remainingPids.remove(it) }
            } else null
            val state = classifyState(candidate.sizeGrew, candidate.timeSinceActivity, assignedPid)
                ?: continue
            sessions.add(AgentSessionInfo(
                sessionId = candidate.sessionId,
                state = state,
                pid = assignedPid,
                tty = assignedPid?.let { pidToTty[it] },
                terminalKind = assignedPid?.let { pidToTerminal[it] } ?: AgentTerminalKind.UNKNOWN,
                lastActivityMs = candidate.lastModified,
                sessionStartMs = candidate.createdMs,
            ))
        }

        // Fallback: PIDs that are alive but didn't match any session file.
        // Synthesize a RUNNING session for each (e.g., claude sitting at prompt, no .jsonl yet).
        for (pid in remainingPids) {
            sessions.add(AgentSessionInfo(
                sessionId = "(pid:$pid)",
                state = AgentSessionState.RUNNING,
                pid = pid,
                tty = pidToTty[pid],
                terminalKind = pidToTerminal[pid] ?: AgentTerminalKind.UNKNOWN,
                lastActivityMs = now,
                sessionStartMs = now,
            ))
        }

        return sessions
    }

    private data class SessionCandidate(
        val sessionId: String,
        val lastModified: Long,
        val createdMs: Long,
        val sizeGrew: Boolean,
        val timeSinceActivity: Long,
    )

    private fun buildSessionCandidate(file: Path, now: Long): SessionCandidate? {
        val sessionId = file.fileName.toString().removeSuffix(".jsonl")
        val lastModified = try {
            Files.getLastModifiedTime(file).toMillis()
        } catch (_: Exception) {
            return null
        }

        val fileSize = try { Files.size(file) } catch (_: Exception) { 0L }
        val previousSize = fileSizeCache.put(file, fileSize)
        val sizeGrew = previousSize != null && fileSize > previousSize

        val createdMs = try {
            val attr = Files.getAttribute(file, "creationTime")
            (attr as java.nio.file.attribute.FileTime).toMillis()
        } catch (_: Exception) {
            lastModified
        }

        return SessionCandidate(
            sessionId = sessionId,
            lastModified = lastModified,
            createdMs = createdMs,
            sizeGrew = sizeGrew,
            timeSinceActivity = now - lastModified,
        )
    }

    private fun classifyState(
        sizeGrew: Boolean,
        timeSinceActivity: Long,
        matchedPid: Long?,
    ): AgentSessionState? {
        return when {
            sizeGrew && matchedPid != null -> AgentSessionState.RUNNING
            timeSinceActivity <= ACTIVE_WRITE_THRESHOLD_MS && matchedPid != null -> AgentSessionState.RUNNING
            timeSinceActivity <= ACTIVE_WRITE_THRESHOLD_MS -> null
            timeSinceActivity <= IDLE_THRESHOLD_MS && matchedPid != null -> AgentSessionState.IDLE
            else -> null
        }
    }

    /**
     * Collects PIDs of claude processes whose cwd matches [worktreePath].
     * Uses lsof for precise per-process cwd matching, plus lock file PIDs.
     */
    private fun collectAlivePids(worktreePath: Path): Set<Long> {
        val pids = mutableSetOf<Long>()
        pids.addAll(doDetectLockFilePids(worktreePath))
        pids.addAll(findClaudePidsForWorktree(worktreePath))

        return pids.filter { pid ->
            try {
                ProcessHandle.of(pid).isPresent
            } catch (_: Exception) {
                false
            }
        }.toSet()
    }

    /**
     * Uses lsof to find claude process PIDs whose cwd is exactly [worktreePath].
     * Returns only PIDs for this specific worktree, not all claude processes.
     */
    private fun findClaudePidsForWorktree(worktreePath: Path): Set<Long> {
        if (PlatformUtil.isWindows()) return emptySet()
        return try {
            val lsofPath = if (Files.exists(Path.of("/usr/sbin/lsof"))) "/usr/sbin/lsof"
            else if (Files.exists(Path.of("/usr/bin/lsof"))) "/usr/bin/lsof"
            else "lsof"

            val process = ProcessBuilder(lsofPath, "-a", "-d", "cwd", "-c", "claude", "-Fpn")
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().readText()
            process.waitFor()

            // Parse lsof -Fpn output: lines alternate between p<pid> and n<path>
            val normalizedTarget = worktreePath.normalize().toString()
            val pids = mutableSetOf<Long>()
            var currentPid: Long? = null

            for (line in output.lines()) {
                if (line.startsWith("p")) {
                    currentPid = line.removePrefix("p").toLongOrNull()
                } else if (line.startsWith("n") && currentPid != null) {
                    val cwdPath = line.removePrefix("n")
                    if (cwdPath == normalizedTarget) {
                        pids.add(currentPid)
                    }
                    currentPid = null
                }
            }
            pids
        } catch (e: Exception) {
            log.debug("lsof PID detection failed", e)
            emptySet()
        }
    }

    internal fun doDetectLockFilePids(worktreePath: Path): Set<Long> {
        val ideDir = Path.of(System.getProperty("user.home")).resolve(CLAUDE_IDE_DIR)
        if (!Files.isDirectory(ideDir)) return emptySet()

        val pids = mutableSetOf<Long>()
        try {
            Files.list(ideDir).use { stream ->
                val lockFiles = stream.filter { it.fileName.toString().endsWith(".lock") }.toList()
                for (lockFile in lockFiles) {
                    try {
                        val content = Files.readString(lockFile)
                        val pid = extractJsonLong(content, "pid")
                        val folders = extractJsonStringArray(content, "workspaceFolders")
                        if (pid != null && folders.any { folderMatchesWorktree(it, worktreePath) }) {
                            pids.add(pid)
                        }
                    } catch (_: Exception) {
                        // Skip malformed lock files
                    }
                }
            }
        } catch (e: Exception) {
            log.debug("Failed to scan lock files", e)
        }
        return pids
    }

    private fun folderMatchesWorktree(folder: String, worktreePath: Path): Boolean {
        return try {
            Path.of(folder).normalize() == worktreePath.normalize()
        } catch (_: Exception) {
            false
        }
    }

    private fun resolveTerminalKinds(pids: Set<Long>): Map<Long, AgentTerminalKind> {
        return pids.associateWith { pid ->
            when (TerminalNavigator.resolveTerminalOwner(pid)) {
                TerminalNavigator.TerminalKind.INTELLIJ -> AgentTerminalKind.INTELLIJ
                TerminalNavigator.TerminalKind.ITERM2 -> AgentTerminalKind.ITERM2
                TerminalNavigator.TerminalKind.TERMINAL_APP -> AgentTerminalKind.TERMINAL_APP
                TerminalNavigator.TerminalKind.UNKNOWN -> AgentTerminalKind.UNKNOWN
            }
        }
    }

    internal fun doResolveTtys(pids: Set<Long>): Map<Long, String> {
        if (pids.isEmpty() || PlatformUtil.isWindows()) return emptyMap()
        val result = mutableMapOf<Long, String>()
        for (pid in pids) {
            TerminalNavigator.resolveTty(pid)?.let { result[pid] = it }
        }
        return result
    }

    private fun doListSessionFiles(worktreePath: Path): List<Path> {
        val projectDir = ClaudeSessionPaths.resolveProjectDir(worktreePath) ?: return emptyList()
        return try {
            Files.list(projectDir).use { stream ->
                stream.filter { it.fileName.toString().endsWith(".jsonl") }.toList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    internal fun extractJsonLong(json: String, key: String): Long? {
        val pattern = Regex(""""$key"\s*:\s*(\d+)""")
        return pattern.find(json)?.groupValues?.get(1)?.toLongOrNull()
    }

    internal fun extractJsonStringArray(json: String, key: String): List<String> {
        val pattern = Regex(""""$key"\s*:\s*\[([^\]]*)]""")
        val match = pattern.find(json) ?: return emptyList()
        val arrayContent = match.groupValues[1]
        return Regex(""""([^"]*?)"""").findAll(arrayContent)
            .map { it.groupValues[1] }
            .toList()
    }

}
