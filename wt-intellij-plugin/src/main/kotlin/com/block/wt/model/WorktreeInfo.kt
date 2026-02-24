package com.block.wt.model

import com.block.wt.util.relativizeAgainst
import java.nio.file.Path

sealed class WorktreeStatus {
    data object NotLoaded : WorktreeStatus()
    data class Loaded(
        val staged: Int,
        val modified: Int,
        val untracked: Int,
        val conflicts: Int,
        val ahead: Int?,
        val behind: Int?,
    ) : WorktreeStatus() {
        val isDirty: Boolean get() = staged + modified + untracked + conflicts > 0
    }
}

data class WorktreeInfo(
    val path: Path,
    val branch: String?,
    val head: String,
    val isMain: Boolean = false,
    val isLinked: Boolean = false,
    val isPrunable: Boolean = false,
    val status: WorktreeStatus = WorktreeStatus.NotLoaded,
    val isProvisioned: Boolean = false,
    val isProvisionedByCurrentContext: Boolean = false,
    val activeAgentSessionIds: List<String> = emptyList(),
) {
    val hasActiveAgent: Boolean get() = activeAgentSessionIds.isNotEmpty()

    /** True if the worktree has any uncommitted changes. Null if status not loaded yet. */
    val isDirty: Boolean?
        get() = when (status) {
            is WorktreeStatus.NotLoaded -> null
            is WorktreeStatus.Loaded -> status.isDirty
        }

    val displayName: String
        get() = branch ?: head.take(8)

    val shortPath: String
        get() = path.fileName?.toString() ?: path.toString()

    fun relativePath(worktreesBase: Path?): String = path.relativizeAgainst(worktreesBase)
}
