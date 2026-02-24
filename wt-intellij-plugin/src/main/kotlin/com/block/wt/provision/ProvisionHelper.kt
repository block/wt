package com.block.wt.provision

import com.block.wt.model.ContextConfig
import com.block.wt.progress.ProgressScope
import com.block.wt.services.BazelService
import com.block.wt.services.MetadataService
import com.block.wt.ui.Notifications
import com.intellij.openapi.diagnostic.Logger
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
     * @param scope Optional progress scope for UI feedback.
     */
    suspend fun provisionWorktree(
        project: Project,
        worktreePath: Path,
        config: ContextConfig,
        keepExistingFiles: Boolean = false,
        scope: ProgressScope? = null,
    ) {
        val errors = mutableListOf<String>()

        // Step 1: Write marker (0%–5%)
        scope?.checkCanceled()
        scope?.text("Writing provision marker...")
        scope?.fraction(0.0)
        ProvisionMarkerService.writeProvisionMarker(worktreePath, config.name).onFailure {
            log.warn("Failed to write provision marker for $worktreePath", it)
            errors.add("Failed to write provision marker: ${it.message}")
        }

        if (!keepExistingFiles) {
            // Step 2: Import metadata (5%–85%)
            scope?.checkCanceled()
            scope?.fraction(0.05)
            scope?.text("Importing metadata...")
            runCatching {
                MetadataService.getInstance(project).importMetadata(
                    config.ideaFilesBase, worktreePath,
                    scope = scope?.sub(0.05, 0.80),
                )
            }.onFailure {
                log.warn("Metadata import failed for $worktreePath", it)
                errors.add("Metadata import: ${it.message}")
            }

            // Step 3: Bazel symlinks (85%–100%)
            scope?.checkCanceled()
            scope?.fraction(0.85)
            scope?.text("Installing Bazel symlinks...")
            runCatching {
                BazelService.getInstance(project).installBazelSymlinks(config.mainRepoRoot, worktreePath)
            }.onFailure {
                log.warn("Bazel symlink install failed for $worktreePath", it)
                errors.add("Bazel symlinks: ${it.message}")
            }
        }

        scope?.fraction(1.0)

        if (errors.isNotEmpty()) {
            Notifications.warning(
                project,
                "Provisioning Warnings",
                "Provisioned with issues:\n${errors.joinToString("\n• ", prefix = "• ")}",
            )
        }
    }
}
