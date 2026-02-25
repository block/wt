package com.block.wt.ui

import com.block.wt.git.GitBranchHelper
import com.block.wt.services.ContextService
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.openapi.ui.ValidationInfo
import com.intellij.ui.components.JBTextField
import com.intellij.ui.dsl.builder.bindSelected
import com.intellij.ui.dsl.builder.bindText
import com.intellij.ui.dsl.builder.panel
import javax.swing.JComponent

class CreateWorktreeDialog(private val project: Project) : DialogWrapper(project) {

    var branchName: String = ""
    var createNewBranch: Boolean = false
    var worktreePath: String = ""

    private lateinit var branchField: JBTextField
    private lateinit var pathField: JBTextField

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
                    .onChanged { updatePath() }
                    .also { branchField = it.component }
            }
            row("") {
                checkBox("Create new branch (-b)")
                    .bindSelected(::createNewBranch)
            }
            row("Path:") {
                textField()
                    .bindText(::worktreePath)
                    .comment("Auto-derived from branch name. Override if needed.")
                    .also { pathField = it.component }
            }
        }
    }

    private fun updatePath() {
        val config = ContextService.getInstance().getCurrentConfig() ?: return
        if (branchField.text.isNotBlank()) {
            pathField.text = GitBranchHelper.worktreePathForBranch(config.worktreesBase, branchField.text).toString()
        }
    }

    override fun doValidate(): ValidationInfo? {
        val branch = branchField.text
        if (branch.isBlank()) return ValidationInfo("Branch name is required", branchField)
        if (branch.contains("..")) return ValidationInfo("Branch name cannot contain '..'", branchField)
        if (branch.startsWith("-")) return ValidationInfo("Branch name cannot start with '-'", branchField)
        if (pathField.text.isBlank()) return ValidationInfo("Worktree path is required", pathField)
        return null
    }
}
