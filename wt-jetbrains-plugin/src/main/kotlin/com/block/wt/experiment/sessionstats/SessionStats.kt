package com.block.wt.experiment.sessionstats

import com.block.wt.util.DurationFormat
import java.time.Instant

/**
 * Aggregated statistics parsed from a Claude Code session `.jsonl` transcript.
 */
data class SessionStats(
    val sessionId: String,
    val model: String?,
    val claudeCodeVersion: String?,
    val slug: String?,
    val inputTokens: Long,
    val outputTokens: Long,
    val cacheCreationTokens: Long,
    val cacheReadTokens: Long,
    val userTurns: Int,
    val assistantMessages: Int,
    val toolUses: Int,
    val totalTurnDurationMs: Long,
    val firstTimestamp: String?,
    val lastTimestamp: String?,
) {
    val totalTokens: Long get() = inputTokens + outputTokens

    val wallDurationMs: Long? get() {
        if (firstTimestamp == null || lastTimestamp == null) return null
        return try {
            val first = Instant.parse(firstTimestamp).toEpochMilli()
            val last = Instant.parse(lastTimestamp).toEpochMilli()
            (last - first).coerceAtLeast(0)
        } catch (_: Exception) { null }
    }

    fun formatTokenCount(count: Long): String = when {
        count >= 1_000_000 -> String.format("%.1fM", count / 1_000_000.0)
        count >= 1_000 -> String.format("%.1fk", count / 1_000.0)
        else -> count.toString()
    }

    fun formatDuration(ms: Long): String = DurationFormat.detailed(ms)
}
