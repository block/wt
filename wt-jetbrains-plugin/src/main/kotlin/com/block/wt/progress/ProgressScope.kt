package com.block.wt.progress

import com.intellij.openapi.progress.ProgressIndicator

/**
 * Maps a sub-range of a [ProgressIndicator]'s fraction to 0.0..1.0.
 *
 * Example: if the overall bar is at 0.40..0.80 for "Creating worktree",
 * `ProgressScope(indicator, start=0.40, size=0.40)` lets you call
 * `fraction(0.5)` to set the bar to 0.60 (the midpoint of that range).
 */
class ProgressScope(
    private val indicator: ProgressIndicator,
    private val start: Double,
    private val size: Double,
) {
    fun fraction(progress: Double) {
        indicator.fraction = start + progress.coerceIn(0.0, 1.0) * size
    }

    fun text(value: String) { indicator.text = value }
    fun text2(value: String) { indicator.text2 = value }
    fun checkCanceled() { indicator.checkCanceled() }

    fun sub(subStart: Double, subSize: Double) =
        ProgressScope(indicator, start + subStart * size, subSize * size)
}

fun ProgressIndicator.asScope() = ProgressScope(this, 0.0, 1.0)
