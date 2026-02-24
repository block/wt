package com.block.wt.actions.metadata

import com.block.wt.actions.WtConfigAction
import com.block.wt.services.BazelService
import com.block.wt.services.MetadataService
import com.block.wt.ui.Notifications
import com.intellij.openapi.actionSystem.AnActionEvent

class RefreshBazelTargetsAction : WtConfigAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val config = requireConfig() ?: return

        runInBackground(project, "Refreshing Bazel Targets") { indicator ->
            indicator.text = "Refreshing Bazel targets..."
            BazelService.getInstance(project)
                .refreshAllBazelMetadata(config.mainRepoRoot)
                .fold(
                    onSuccess = { count ->
                        if (count > 0) {
                            indicator.text = "Re-exporting metadata..."
                            MetadataService.getInstance(project)
                                .exportMetadata(config.mainRepoRoot, config.ideaFilesBase, config.metadataPatterns)
                                .onFailure { ex ->
                                    Notifications.warning(project, "Metadata Export Failed", ex.message ?: "Unknown error")
                                }
                        }
                        Notifications.info(project, "Bazel Targets Refreshed", "Refreshed $count Bazel IDE directories")
                    },
                    onFailure = { ex ->
                        Notifications.error(project, "Refresh Failed", ex.message ?: "Unknown error")
                    }
                )
        }
    }
}
