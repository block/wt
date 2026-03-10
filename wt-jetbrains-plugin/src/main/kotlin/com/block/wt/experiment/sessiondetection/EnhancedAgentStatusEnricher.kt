package com.block.wt.experiment.sessiondetection

import com.block.wt.model.WorktreeInfo
import com.block.wt.services.WorktreeEnricher
class EnhancedAgentStatusEnricher(
    private val detector: EnhancedAgentDetector,
) : WorktreeEnricher {

    override fun enrich(worktrees: List<WorktreeInfo>): List<WorktreeInfo> {
        return worktrees.map { wt ->
            val sessions = detector.detectAgentSessions(wt.path)

            // Backward compat: populate activeAgentSessionIds from sessions
            val legacyIds = sessions.map { it.sessionId }

            wt.copy(
                agentSessions = sessions,
                activeAgentSessionIds = legacyIds.ifEmpty { wt.activeAgentSessionIds },
            )
        }
    }
}
