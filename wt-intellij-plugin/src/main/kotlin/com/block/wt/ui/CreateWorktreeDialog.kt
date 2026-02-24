package com.block.wt.ui

import com.block.wt.git.GitBranchHelper
import com.block.wt.services.ContextService
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.openapi.ui.ValidationInfo
import com.intellij.ui.dsl.builder.bindSelected
import com.intellij.ui.dsl.builder.bindText
import com.intellij.ui.dsl.builder.panel
import javax.swing.JComponent

class CreateWorktreeDialog(private val project: Project) : DialogWrapper(project) {

    var branchName: String = ""
    var createNewBranch: Boolean = false
    var worktreePath: String = ""

    init {
        title = "Create Worktree"
        init()
        updatePath()
    }

    override fun createCenterPanel(): JComponent {
        return panel {
            row("Branch:") {
                textField()
                    .bindText(::branchName)
                    .focused()
                    .validationOnApply {
                        when {
                            it.text.isBlank() -> ValidationInfo("Branch name is required")
                            it.text.contains("..") -> ValidationInfo("Branch name cannot contain '..'")
                            it.text.startsWith("-") -> ValidationInfo("Branch name cannot start with '-'")
                            else -> null
                        }
                    }
                    .onChanged { updatePath() }
            }
            row("") {
                checkBox("Create new branch (-b)")
                    .bindSelected(::createNewBranch)
            }
            row("Path:") {
                textField()
                    .bindText(::worktreePath)
                    .comment("Auto-derived from branch name. Override if needed.")
            }
        }
    }

    private fun updatePath() {
        val config = ContextService.getInstance().getCurrentConfig() ?: return
        if (branchName.isNotBlank()) {
            worktreePath = GitBranchHelper.worktreePathForBranch(config.worktreesBase, branchName).toString()
        }
    }

    override fun doValidate(): ValidationInfo? {
        if (branchName.isBlank()) return ValidationInfo("Branch name is required")
        if (worktreePath.isBlank()) return ValidationInfo("Worktree path is required")
        return null
    }
}
