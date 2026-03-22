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
 * Consolidates the provision flow: import metadata -> install Bazel symlinks -> write marker.
 * The marker is written only after all steps succeed, matching CLI semantics.
 * Collects errors and reports them instead of silently swallowing.
 */
object ProvisionHelper {

    private val log = Logger.getInstance(ProvisionHelper::class.java)

    /**
     * Performs the full provision sequence for a single worktree.
     *
     * @param keepExistingFiles If true, skips metadata import (marker + Bazel symlinks only).
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

        if (!keepExistingFiles) {
            // Step 1: Import metadata (0%–80%)
            scope?.checkCanceled()
            scope?.fraction(0.0)
            scope?.text("Importing metadata...")
            runCatching {
                MetadataService.getInstance(project).importMetadata(
                    config.ideaFilesBase, worktreePath,
                    patterns = config.metadataPatterns,
                    scope = scope?.sub(0.0, 0.80),
                )
            }.onFailure {
                log.warn("Metadata import failed for $worktreePath", it)
                errors.add("Metadata import: ${it.message}")
            }

            // Step 2: Bazel symlinks (80%–95%)
            scope?.checkCanceled()
            scope?.fraction(0.80)
            scope?.text("Installing Bazel symlinks...")
            runCatching {
                BazelService.getInstance(project).installBazelSymlinks(config.mainRepoRoot, worktreePath)
            }.onFailure {
                log.warn("Bazel symlink install failed for $worktreePath", it)
                errors.add("Bazel symlinks: ${it.message}")
            }
        }

        // Step 3: Write adoption marker only if no errors (95%–100%)
        scope?.checkCanceled()
        scope?.fraction(0.95)
        scope?.text("Writing adoption marker...")
        if (errors.isEmpty()) {
            ProvisionMarkerService.writeAdoptionMarker(worktreePath, config.name).onFailure {
                log.warn("Failed to write adoption marker for $worktreePath", it)
                errors.add("Failed to write adoption marker: ${it.message}")
            }
        }

        scope?.fraction(1.0)

        if (errors.isNotEmpty()) {
            Notifications.warning(
                project,
                "Adoption Warnings",
                "Adopted with issues:\n${errors.joinToString("\n• ", prefix = "• ")}",
            )
        }
    }
}
