package com.block.wt.experiment.sessionstats

import com.block.wt.experiment.sessiondetection.AgentSessionInfo
import com.block.wt.experiment.sessiondetection.AgentSessionState
import com.block.wt.util.DurationFormat
import java.nio.file.Path

/**
 * Builds HTML tooltip content for agent session info.
 * Extracted from WorktreePanel to keep session-stats presentation logic
 * colocated with the data model it formats.
 */
object SessionTooltipBuilder {

    /**
     * Builds a full agent tooltip for a worktree, dispatching between
     * enhanced session info and legacy session ID display.
     */
    fun buildAgentTooltip(
        sessions: List<AgentSessionInfo>,
        legacySessionIds: List<String>,
        worktreePath: Path,
    ): String {
        if (sessions.isNotEmpty()) {
            val parts = sessions.map { s -> buildSessionBlock(worktreePath, s) }
            return "<html>${parts.joinToString("<hr>")}</html>"
        }

        // Fallback: legacy tooltip
        return when {
            legacySessionIds.size == 1 -> "<html>Claude agent active<br>Session: ${legacySessionIds[0]}</html>"
            legacySessionIds.size > 1 -> "<html>${legacySessionIds.size} active sessions:<br>${legacySessionIds.joinToString("<br>") { "&nbsp;&nbsp;$it" }}</html>"
            else -> "Claude agent active"
        }
    }

    /**
     * Builds one tooltip block for a single agent session, including
     * state header, timing, and parsed session stats (tokens, turns, etc.).
     */
    fun buildSessionBlock(worktreePath: Path, s: AgentSessionInfo): String {
        val now = System.currentTimeMillis()
        val stateLabel = when (s.state) {
            AgentSessionState.RUNNING -> "\uD83D\uDFE2 Running"   // green circle
            AgentSessionState.IDLE -> "\uD83D\uDFE1 Idle"         // yellow circle
        }
        val elapsed = DurationFormat.compact(now - s.lastActivityMs)
        val termStr = if (s.terminalKind.displayName.isNotEmpty()) " \u2014 ${s.terminalKind.displayName}" else ""
        val pidStr = s.pid?.let { " (PID $it)" } ?: ""

        val sb = StringBuilder()

        // Header: terminal + PID
        sb.append("<b>$stateLabel</b>$termStr$pidStr")
        sb.append("<br>Last activity ${elapsed} ago")
        sb.append("<br><font color='gray'>${s.sessionId}</font>")

        val sessionId = s.sessionId
        if (sessionId.startsWith("(pid:")) return sb.toString()

        val stats = try {
            SessionStatsParser.parse(worktreePath, sessionId)
        } catch (_: Exception) { null } ?: return sb.toString()

        sb.append("<br><br>")

        fun row(label: String, value: String) {
            sb.append("<tr><td nowrap><font color='gray'>$label</font></td><td>&nbsp;&nbsp;</td><td nowrap>$value</td></tr>")
        }

        sb.append("<table cellpadding='1' cellspacing='0'>")
        stats.model?.let { row("Model", it) }
        if (stats.totalTokens > 0) {
            row("Tokens", "${stats.formatTokenCount(stats.inputTokens)} in \u00b7 ${stats.formatTokenCount(stats.outputTokens)} out")
        }
        if (stats.cacheReadTokens > 0 || stats.cacheCreationTokens > 0) {
            row("Cache", "${stats.formatTokenCount(stats.cacheReadTokens)} read \u00b7 ${stats.formatTokenCount(stats.cacheCreationTokens)} write")
        }
        if (stats.userTurns > 0) {
            row("Turns", "${stats.userTurns}")
            row("Tool uses", "${stats.toolUses}")
        }
        if (stats.totalTurnDurationMs > 0) {
            row("Duration (API)", stats.formatDuration(stats.totalTurnDurationMs))
        }
        stats.wallDurationMs?.let { wall ->
            if (wall > 0) row("Duration (wall)", stats.formatDuration(wall))
        }
        stats.claudeCodeVersion?.let { row("Version", it) }
        sb.append("</table>")

        return sb.toString()
    }
}
