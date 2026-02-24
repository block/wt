package com.block.wt.actions.context

import com.block.wt.actions.WtConfigAction
import com.block.wt.util.PathHelper
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.ui.popup.JBPopupFactory
import com.intellij.ui.components.JBLabel
import com.intellij.ui.dsl.builder.panel
import javax.swing.SwingConstants

class ShowContextConfigAction : WtConfigAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val config = requireConfig(e) ?: return
        val project = e.project ?: return

        val symlinkTarget = PathHelper.readSymlink(config.activeWorktree)

        val content = panel {
            row("Name:") { cell(JBLabel(config.name)) }
            row("Main repo root:") { cell(JBLabel(config.mainRepoRoot.toString())) }
            row("Active worktree:") {
                val text = if (symlinkTarget != null) {
                    "${config.activeWorktree} -> $symlinkTarget"
                } else {
                    config.activeWorktree.toString()
                }
                cell(JBLabel(text))
            }
            row("Worktrees base:") { cell(JBLabel(config.worktreesBase.toString())) }
            row("Metadata vault:") { cell(JBLabel(config.ideaFilesBase.toString())) }
            row("Base branch:") { cell(JBLabel(config.baseBranch)) }
            if (config.metadataPatterns.isNotEmpty()) {
                row("Metadata patterns:") { cell(JBLabel(config.metadataPatterns.joinToString(", "))) }
            }
        }

        JBPopupFactory.getInstance()
            .createComponentPopupBuilder(content, null)
            .setTitle("Context: ${config.name}")
            .setFocusable(true)
            .setRequestFocus(true)
            .setMovable(true)
            .createPopup()
            .showCenteredInCurrentWindow(project)
    }
}
