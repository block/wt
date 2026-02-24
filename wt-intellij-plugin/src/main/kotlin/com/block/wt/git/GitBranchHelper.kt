package com.block.wt.git

import java.nio.file.Path

object GitBranchHelper {

    fun sanitizeBranchName(name: String): String {
        val trimmed = name.trim()
        require(!trimmed.contains("..")) { "Branch name cannot contain '..' (path traversal)" }
        require(trimmed.isNotBlank()) { "Branch name cannot be blank" }
        require(!trimmed.startsWith("-")) { "Branch name cannot start with '-'" }
        return trimmed
    }

    fun worktreePathForBranch(worktreesBase: Path, branchName: String): Path {
        val safeName = branchName.replace("/", "-")
        return worktreesBase.resolve(safeName)
    }
}
