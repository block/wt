package com.block.wt.services

import com.block.wt.settings.WtPluginSettings
import com.block.wt.util.PathHelper
import com.block.wt.util.normalizeSafe
import com.intellij.ide.AppLifecycleListener
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.ProjectManager
import java.nio.file.Files

class MetadataAutoExporter : AppLifecycleListener {

    private val log = Logger.getInstance(MetadataAutoExporter::class.java)

    override fun appWillBeClosed(isRestart: Boolean) {
        if (!WtPluginSettings.getInstance().state.autoExportOnShutdown) return

        val config = ContextService.getInstance().getCurrentConfig() ?: return
        if (config.metadataPatterns.isEmpty()) return

        // Find the source path: look for an open project whose base path matches the active worktree,
        // otherwise use the active worktree's symlink target directly
        val source = run {
            val activeWorktree = config.activeWorktree
            val resolved = if (Files.isSymbolicLink(activeWorktree)) {
                activeWorktree.normalizeSafe()
            } else {
                activeWorktree
            }

            // Check open projects for a match
            val projects = ProjectManager.getInstance().openProjects
            for (project in projects) {
                val basePath = project.basePath ?: continue
                val projectPath = java.nio.file.Path.of(basePath).normalizeSafe()
                if (projectPath == resolved || projectPath == activeWorktree.normalizeSafe()) {
                    return@run resolved
                }
            }
            resolved
        }

        if (!Files.isDirectory(source)) return

        try {
            val result = MetadataService.exportMetadataStatic(
                source = source,
                vault = config.ideaFilesBase,
                patterns = config.metadataPatterns,
            )
            result.fold(
                onSuccess = { count -> log.info("Auto-exported $count metadata entries on shutdown") },
                onFailure = { e -> log.warn("Failed to auto-export metadata on shutdown", e) }
            )
        } catch (e: Exception) {
            log.warn("Failed to auto-export metadata on shutdown", e)
        }
    }
}
