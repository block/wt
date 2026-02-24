package com.block.wt.actions.metadata

import com.block.wt.actions.WtConfigAction
import com.block.wt.services.MetadataService
import com.block.wt.ui.Notifications
import com.block.wt.util.PathHelper
import com.intellij.openapi.actionSystem.AnActionEvent

class ImportMetadataAction : WtConfigAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val config = requireConfig(e) ?: return

        val target = if (PathHelper.isSymlink(config.activeWorktree)) {
            val raw = PathHelper.readSymlink(config.activeWorktree) ?: config.activeWorktree
            if (raw.isAbsolute) raw else config.activeWorktree.parent.resolve(raw).normalize()
        } else {
            config.activeWorktree
        }

        runInBackground(project, "Importing Metadata", cancellable = false) {
            it.text = "Importing metadata from vault..."
            MetadataService.getInstance(project)
                .importMetadata(config.ideaFilesBase, target)
                .fold(
                    onSuccess = { count ->
                        Notifications.info(project, "Metadata Imported", "Imported $count metadata directories")
                    },
                    onFailure = { ex ->
                        Notifications.error(project, "Import Failed", ex.message ?: "Unknown error")
                    }
                )
        }
    }
}
