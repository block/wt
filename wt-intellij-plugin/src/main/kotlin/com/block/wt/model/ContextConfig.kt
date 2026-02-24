package com.block.wt.model

import java.nio.file.Path

data class ContextConfig(
    val name: String,
    val mainRepoRoot: Path,
    val worktreesBase: Path,
    val activeWorktree: Path,
    val ideaFilesBase: Path,
    val baseBranch: String,
    val metadataPatterns: List<String>,
)
