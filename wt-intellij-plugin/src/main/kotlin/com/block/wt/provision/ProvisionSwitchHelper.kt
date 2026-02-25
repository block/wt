package com.block.wt.provision

import com.block.wt.model.WorktreeInfo
import com.block.wt.progress.asScope
import com.block.wt.services.ContextService
import com.block.wt.services.SymlinkSwitchService
import com.block.wt.settings.WtPluginSettings
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.progress.runBlockingCancellable
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.Messages

/**
 * Handles the "should we provision before switching?" flow.
 * Extracted from SwitchWorktreeAction.Companion to give it a proper home
 * in the provision/ package. Called from SwitchWorktreeAction and WorktreePanel.
 */
object ProvisionSwitchHelper {

    fun switchWithProvisionPrompt(project: Project, wt: WorktreeInfo) {
        val settings = WtPluginSettings.getInstance().state

        // Standard confirm-before-switch check
        if (settings.confirmBeforeSwitch) {
            val answer = Messages.showYesNoDialog(
                project,
                "Switch to '${wt.displayName}'?",
                "Confirm Switch",
                Messages.getQuestionIcon(),
            )
            if (answer != Messages.YES) return
        }

        // Provision prompt: only when the worktree is not provisioned by the current context
        val contextService = ContextService.getInstance()
        val config = contextService.getCurrentConfig()
        val currentContextName = config?.name

        if (settings.promptProvisionOnSwitch && currentContextName != null && !wt.isProvisionedByCurrentContext) {
            val hasMetadata = ProvisionMarkerService.hasExistingMetadata(wt.path)

            if (hasMetadata) {
                // Worktree already has project files — ask whether to claim them or overwrite
                val options = arrayOf(
                    "Provision (keep files)",
                    "Provision (overwrite from vault)",
                    "Switch Only",
                    "Cancel",
                )
                val answer = Messages.showDialog(
                    project,
                    "Worktree '${wt.displayName}' has existing project files but hasn't been " +
                        "provisioned by context '$currentContextName'.\n\n" +
                        "Keep files: mark as provisioned without changing anything.\n" +
                        "Overwrite: replace project files with this context's vault.",
                    "Provision Worktree?",
                    options,
                    0, // default: keep files
                    Messages.getQuestionIcon(),
                )

                when (answer) {
                    0 -> {
                        // Provision (keep files) — marker only, no import
                        ProvisionMarkerService.writeProvisionMarker(wt.path, currentContextName)
                            .onFailure { /* best-effort: switch anyway */ }
                        SymlinkSwitchService.getInstance(project).switchWorktree(wt.path)
                        return
                    }
                    1 -> {
                        // Provision (overwrite from vault) — full import then switch
                        provisionAndSwitch(project, wt)
                        return
                    }
                    2 -> {
                        // Switch Only — fall through
                    }
                    else -> return // Cancel or closed
                }
            } else {
                // No existing metadata — standard provision prompt
                val answer = Messages.showYesNoCancelDialog(
                    project,
                    "Worktree '${wt.displayName}' is not provisioned by context '$currentContextName'.\n\n" +
                        "Provisioning will import IDE metadata and install Bazel symlinks.",
                    "Provision Worktree?",
                    "Provision && Switch",
                    "Switch Only",
                    "Cancel",
                    Messages.getQuestionIcon(),
                )

                when (answer) {
                    Messages.YES -> {
                        provisionAndSwitch(project, wt)
                        return
                    }
                    Messages.NO -> {
                        // Switch Only — fall through
                    }
                    else -> return // Cancel
                }
            }
        }

        SymlinkSwitchService.getInstance(project).switchWorktree(wt.path)
    }

    private fun provisionAndSwitch(project: Project, wt: WorktreeInfo) {
        val config = ContextService.getInstance().getCurrentConfig() ?: return

        ProgressManager.getInstance().run(object : Task.Backgroundable(
            project, "Provisioning & Switching Worktree", true
        ) {
            override fun run(indicator: ProgressIndicator) {
                indicator.isIndeterminate = false
                val scope = indicator.asScope()

                runBlockingCancellable {
                    ProvisionHelper.provisionWorktree(
                        project, wt.path, config,
                        scope = scope.sub(0.0, 0.40),
                    )

                    scope.fraction(0.40)
                    SymlinkSwitchService.getInstance(project).doSwitch(
                        wt.path, indicator,
                        scope = scope.sub(0.40, 0.60),
                    )
                    scope.fraction(1.0)
                }
            }
        })
    }
}
