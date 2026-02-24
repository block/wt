package com.block.wt.provision

import com.block.wt.model.ContextConfig
import com.block.wt.services.BazelService
import com.block.wt.services.MetadataService
import com.block.wt.ui.Notifications
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.project.Project
import java.nio.file.Path

/**
 * Consolidates the provision flow: write marker -> import metadata -> install Bazel symlinks.
 * Collects errors and reports them instead of silently swallowing.
 */
object ProvisionHelper {

    private val log = Logger.getInstance(ProvisionHelper::class.java)

    /**
     * Performs the full provision sequence for a single worktree.
     *
     * @param keepExistingFiles If true, only writes the provision marker without importing metadata.
     * @param indicator Optional progress indicator for UI feedback.
     */
    suspend fun provisionWorktree(
        project: Project,
        worktreePath: Path,
        config: ContextConfig,
        keepExistingFiles: Boolean = false,
        indicator: ProgressIndicator? = null,
    ) {
        val errors = mutableListOf<String>()

        indicator?.checkCanceled()
        indicator?.text = "Writing provision marker..."
        ProvisionMarkerService.writeProvisionMarker(worktreePath, config.name).onFailure {
            log.warn("Failed to write provision marker for $worktreePath", it)
            errors.add("Failed to write provision marker: ${it.message}")
        }

        if (!keepExistingFiles) {
            indicator?.checkCanceled()
            indicator?.text = "Importing metadata..."
            runCatching {
                MetadataService.getInstance(project).importMetadata(config.ideaFilesBase, worktreePath)
            }.onFailure {
                log.warn("Metadata import failed for $worktreePath", it)
                errors.add("Metadata import: ${it.message}")
            }

            indicator?.checkCanceled()
            indicator?.text = "Installing Bazel symlinks..."
            runCatching {
                BazelService.getInstance(project).installBazelSymlinks(config.mainRepoRoot, worktreePath)
            }.onFailure {
                log.warn("Bazel symlink install failed for $worktreePath", it)
                errors.add("Bazel symlinks: ${it.message}")
            }
        }

        if (errors.isNotEmpty()) {
            Notifications.warning(
                project,
                "Provisioning Warnings",
                "Provisioned with issues:\n${errors.joinToString("\n• ", prefix = "• ")}",
            )
        }
    }
}
