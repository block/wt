package com.block.wt.services

import com.block.wt.settings.WtPluginSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class WorktreeRefreshScheduler(
    private val cs: CoroutineScope,
    private val onRefresh: () -> Unit,
) {
    @Volatile
    private var periodicRefreshJob: Job? = null

    fun start() {
        periodicRefreshJob?.cancel()
        val intervalSeconds = WtPluginSettings.getInstance().state.autoRefreshIntervalSeconds
        if (intervalSeconds <= 0) return

        periodicRefreshJob = cs.launch {
            while (true) {
                delay(intervalSeconds * 1000L)
                onRefresh()
            }
        }
    }

    fun stop() {
        periodicRefreshJob?.cancel()
        periodicRefreshJob = null
    }
}
