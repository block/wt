package com.block.wt.actions.metadata

import com.block.wt.actions.WtConfigAction
import com.block.wt.services.MetadataService
import com.block.wt.ui.Notifications
import com.block.wt.util.PathHelper
import com.intellij.openapi.actionSystem.AnActionEvent

class ExportMetadataAction : WtConfigAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val config = requireConfig() ?: return

        val source = if (PathHelper.isSymlink(config.activeWorktree)) {
            val raw = PathHelper.readSymlink(config.activeWorktree) ?: config.mainRepoRoot
            if (raw.isAbsolute) raw else config.activeWorktree.parent.resolve(raw).normalize()
        } else {
            config.mainRepoRoot
        }

        runInBackground(project, "Exporting Metadata", cancellable = false) {
            it.text = "Exporting metadata to vault..."
            MetadataService.getInstance(project)
                .exportMetadata(source, config.ideaFilesBase, config.metadataPatterns)
                .fold(
                    onSuccess = { count ->
                        Notifications.info(project, "Metadata Exported", "Exported $count metadata directories to vault")
                    },
                    onFailure = { ex ->
                        Notifications.error(project, "Export Failed", ex.message ?: "Unknown error")
                    }
                )
        }
    }
}
