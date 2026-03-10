package com.block.wt.util

/**
 * Shared duration formatting used across table cells, tooltips, and session stats.
 */
object DurationFormat {

    /** Compact format: "45s", "3m", "2h" — used in table cells and tooltips. */
    fun compact(ms: Long): String {
        val seconds = ms / 1000
        return when {
            seconds < 60 -> "${seconds}s"
            seconds < 3600 -> "${seconds / 60}m"
            else -> "${seconds / 3600}h"
        }
    }

    /** Detailed format: "45s", "2m 30s", "1h 5m" — used in session stats. */
    fun detailed(ms: Long): String {
        val seconds = ms / 1000
        return when {
            seconds < 60 -> "${seconds}s"
            seconds < 3600 -> "${seconds / 60}m ${seconds % 60}s"
            else -> "${seconds / 3600}h ${(seconds % 3600) / 60}m"
        }
    }
}
