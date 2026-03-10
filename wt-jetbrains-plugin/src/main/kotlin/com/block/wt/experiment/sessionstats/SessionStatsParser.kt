package com.block.wt.experiment.sessionstats

import com.block.wt.agent.ClaudeSessionPaths
import com.intellij.openapi.diagnostic.Logger
import java.nio.file.Files
import java.nio.file.Path

/**
 * Parses Claude Code session `.jsonl` transcript files to extract aggregate statistics.
 *
 * Each line is a JSON object with a `type` field. Relevant types:
 * - `assistant` → `message.model`, `message.usage` (tokens), `message.content` (tool_use counts)
 * - `user` → user turns (excluding tool_result entries)
 * - `system` with `subtype: "turn_duration"` → `durationMs`
 *
 * Uses minimal regex-based JSON extraction to avoid adding a JSON library dependency
 * and to keep parsing fast for multi-MB files.
 */
object SessionStatsParser {

    private val log = Logger.getInstance(SessionStatsParser::class.java)

    fun parse(worktreePath: Path, sessionId: String): SessionStats? {
        val file = ClaudeSessionPaths.resolveSessionFile(worktreePath, sessionId) ?: return null
        return parseFile(file, sessionId)
    }

    internal fun parseFile(file: Path, sessionId: String): SessionStats? {
        return try {
            var model: String? = null
            var version: String? = null
            var slug: String? = null
            var inputTokens = 0L
            var outputTokens = 0L
            var cacheCreationTokens = 0L
            var cacheReadTokens = 0L
            var userTurns = 0
            var assistantMessages = 0
            var toolUses = 0
            var totalTurnDurationMs = 0L
            var firstTimestamp: String? = null
            var lastTimestamp: String? = null

            Files.newBufferedReader(file).useLines { lines ->
                lines.forEach { line ->
                    val type = extractTopLevelType(line)
                    val timestamp = extractString(line, "\"timestamp\"")

                    if (timestamp != null) {
                        if (firstTimestamp == null) firstTimestamp = timestamp
                        lastTimestamp = timestamp
                    }

                    when (type) {
                        "assistant" -> {
                            assistantMessages++
                            if (model == null) model = extractString(line, "\"model\"")
                            if (slug == null) slug = extractString(line, "\"slug\"")
                            inputTokens += extractLong(line, "\"input_tokens\"")
                            outputTokens += extractLong(line, "\"output_tokens\"")
                            cacheCreationTokens += extractLong(line, "\"cache_creation_input_tokens\"")
                            cacheReadTokens += extractLong(line, "\"cache_read_input_tokens\"")
                            toolUses += countOccurrences(line, "\"type\":\"tool_use\"") +
                                countOccurrences(line, "\"type\": \"tool_use\"")
                        }
                        "user" -> {
                            // Count human turns, not tool_result feedback
                            val userType = extractString(line, "\"userType\"")
                            if (userType != "tool_result") {
                                userTurns++
                            }
                        }
                        "system" -> {
                            val subtype = extractString(line, "\"subtype\"")
                            if (subtype == "turn_duration") {
                                totalTurnDurationMs += extractLong(line, "\"durationMs\"")
                            }
                            if (version == null) version = extractString(line, "\"version\"")
                        }
                    }
                }
            }

            SessionStats(
                sessionId = sessionId,
                model = model,
                claudeCodeVersion = version,
                slug = slug,
                inputTokens = inputTokens,
                outputTokens = outputTokens,
                cacheCreationTokens = cacheCreationTokens,
                cacheReadTokens = cacheReadTokens,
                userTurns = userTurns,
                assistantMessages = assistantMessages,
                toolUses = toolUses,
                totalTurnDurationMs = totalTurnDurationMs,
                firstTimestamp = firstTimestamp,
                lastTimestamp = lastTimestamp,
            )
        } catch (e: Exception) {
            log.debug("Failed to parse session file: $file", e)
            null
        }
    }

    /**
     * Extracts the top-level `"type"` value from a JSON line.
     * Matches against known patterns to avoid finding `"type"` inside nested objects
     * (e.g. `"type":"message"` inside the `message` field).
     */
    internal fun extractTopLevelType(line: String): String? {
        // Match "type":"<value>" or "type": "<value>" patterns.
        // The top-level type is always one of a known set — check each directly.
        for (t in TOP_LEVEL_TYPES) {
            if (line.contains("\"type\":\"$t\"") || line.contains("\"type\": \"$t\"")) {
                return t
            }
        }
        return null
    }

    private val TOP_LEVEL_TYPES = arrayOf(
        "assistant", "user", "system", "progress", "file-history-snapshot", "queue-operation"
    )

    /**
     * Extracts a string value for a JSON key using simple pattern matching.
     * Handles `"key": "value"` and `"key":"value"`.
     */
    internal fun extractString(line: String, key: String): String? {
        val keyIdx = line.indexOf(key)
        if (keyIdx < 0) return null
        val afterKey = keyIdx + key.length
        // Skip `: ` or `:`
        var i = afterKey
        while (i < line.length && (line[i] == ':' || line[i] == ' ')) i++
        if (i >= line.length || line[i] != '"') return null
        i++ // skip opening quote
        val start = i
        while (i < line.length && line[i] != '"') {
            if (line[i] == '\\') i++ // skip escaped char
            i++
        }
        return if (i > start) line.substring(start, i) else null
    }

    /** Extracts a numeric value for a JSON key. */
    internal fun extractLong(line: String, key: String): Long {
        val keyIdx = line.indexOf(key)
        if (keyIdx < 0) return 0
        val afterKey = keyIdx + key.length
        var i = afterKey
        while (i < line.length && (line[i] == ':' || line[i] == ' ')) i++
        val start = i
        while (i < line.length && line[i].isDigit()) i++
        return if (i > start) line.substring(start, i).toLongOrNull() ?: 0 else 0
    }

    private fun countOccurrences(line: String, pattern: String): Int =
        (line.length - line.replace(pattern, "").length) / pattern.length
}
