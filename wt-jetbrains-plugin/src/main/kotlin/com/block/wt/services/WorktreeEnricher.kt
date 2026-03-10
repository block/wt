package com.block.wt.services

import com.block.wt.provision.ProvisionMarkerService
import com.block.wt.agent.AgentDetection
import com.block.wt.model.WorktreeInfo
import com.block.wt.util.normalizeSafe

interface WorktreeEnricher {
    fun enrich(worktrees: List<WorktreeInfo>): List<WorktreeInfo>
}

class ProvisionStatusEnricher(private val contextService: ContextService) : WorktreeEnricher {
    override fun enrich(worktrees: List<WorktreeInfo>): List<WorktreeInfo> {
        val currentContextName = contextService.getCurrentConfig()?.name
        return worktrees.map { wt ->
            val provisioned = ProvisionMarkerService.isProvisioned(wt.path)
            val provisionedByCtx = if (provisioned && currentContextName != null) {
                ProvisionMarkerService.isProvisionedByContext(wt.path, currentContextName)
            } else false
            wt.copy(isProvisioned = provisioned, isProvisionedByCurrentContext = provisionedByCtx)
        }
    }
}

class AgentStatusEnricher(private val agentDetection: AgentDetection) : WorktreeEnricher {
    override fun enrich(worktrees: List<WorktreeInfo>): List<WorktreeInfo> {
        // Process detection (lsof) catches running-but-idle agents;
        // session file check catches recently active agents.
        // detectActiveAgentDirs() returns the union of both.
        val activeDirs = agentDetection.detectActiveAgentDirs()
        return worktrees.map { wt ->
            val hasRunningProcess = activeDirs.any { it.normalizeSafe() == wt.path.normalizeSafe() }
            val sessionIds = agentDetection.detectActiveSessionIds(wt.path)
            // Show 🤖 if either a process is running or sessions are recent.
            // For idle processes with no recent sessions, use a placeholder ID.
            val effectiveIds = if (sessionIds.isNotEmpty()) {
                sessionIds
            } else if (hasRunningProcess) {
                listOf("(running)")
            } else {
                emptyList()
            }
            wt.copy(activeAgentSessionIds = effectiveIds)
        }
    }
}
