package com.block.wt.git

import com.block.wt.model.WorktreeInfo
import com.block.wt.util.normalizeSafe
import java.nio.file.Path

object GitParser {

    fun parsePorcelainOutput(output: String, linkedWorktreePath: Path? = null): List<WorktreeInfo> {
        if (output.isBlank()) return emptyList()

        val worktrees = mutableListOf<WorktreeInfo>()
        val blocks = output.trim().split("\n\n")

        for ((index, block) in blocks.withIndex()) {
            val lines = block.lines().filter { it.isNotBlank() }
            var path: Path? = null
            var head: String? = null
            var branch: String? = null
            var isPrunable = false

            for (line in lines) {
                when {
                    line.startsWith("worktree ") -> path = Path.of(line.removePrefix("worktree "))
                    line.startsWith("HEAD ") -> head = line.removePrefix("HEAD ")
                    line.startsWith("branch ") -> {
                        branch = line.removePrefix("branch ")
                        if (branch.startsWith("refs/heads/")) {
                            branch = branch.removePrefix("refs/heads/")
                        }
                    }
                    line == "detached" -> branch = null
                    line == "prunable" -> isPrunable = true
                }
            }

            if (path != null && head != null) {
                val isMain = index == 0
                val isLinked = linkedWorktreePath != null &&
                    path.normalizeSafe() == linkedWorktreePath.normalizeSafe()

                worktrees.add(
                    WorktreeInfo(
                        path = path,
                        branch = branch,
                        head = head,
                        isMain = isMain,
                        isLinked = isLinked,
                        isPrunable = isPrunable,
                    )
                )
            }
        }

        return worktrees
    }
}
