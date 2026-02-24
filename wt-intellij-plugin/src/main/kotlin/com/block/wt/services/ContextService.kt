package com.block.wt.services

import com.block.wt.git.GitConfigHelper
import com.block.wt.git.GitDirResolver
import com.block.wt.model.ContextConfig
import com.block.wt.util.ConfigFileHelper
import com.block.wt.util.PathHelper
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.service
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.nio.file.Path

@Service(Service.Level.PROJECT)
class ContextService(
    private val project: Project,
    private val cs: CoroutineScope,
) {
    private val log = Logger.getInstance(ContextService::class.java)

    private val _contexts = MutableStateFlow<List<ContextConfig>>(emptyList())
    val contexts: StateFlow<List<ContextConfig>> = _contexts.asStateFlow()

    private val _config = MutableStateFlow<ContextConfig?>(null)
    val config: StateFlow<ContextConfig?> = _config.asStateFlow()

    fun initialize() {
        reload()
    }

    fun reload() {
        _contexts.value = ConfigFileHelper.listConfigFiles().mapNotNull { ConfigFileHelper.readConfig(it) }
        val detected = detectContext()
        _config.value = detected
    }

    fun getCurrentConfig(): ContextConfig? = _config.value

    fun addContext(config: ContextConfig) {
        // Primary: write to git local config
        runCatching { GitConfigHelper.writeConfig(config.mainRepoRoot, config) }
            .onFailure { log.warn("Failed to write git local config: ${it.message}") }

        // Backward compat: write .conf file
        val confFile = PathHelper.reposDir.resolve("${config.name}.conf")
        ConfigFileHelper.writeConfig(confFile, config)

        // Write ~/.wt/current only when creating a new active context (not re-provisioning a different one)
        val currentActive = getCurrentConfig()?.name
        if (currentActive == null || currentActive == config.name) {
            runCatching { ConfigFileHelper.writeCurrentContext(config.name) }
                .onFailure { log.warn("Failed to write ~/.wt/current: ${it.message}") }
        }

        reload()
    }

    /**
     * Detects context: tries git local config first, falls back to .conf file matching.
     */
    private fun detectContext(): ContextConfig? {
        val projectPath = project.basePath?.let { Path.of(it) } ?: return null

        // Try git local config first (from PR #23 convention)
        val gitConfig = GitConfigHelper.readConfig(projectPath)
        if (gitConfig != null) {
            log.info("Auto-detected context '${gitConfig.name}' from git config for $projectPath")
            return gitConfig
        }

        // Fallback: match against .conf files
        val repoRoot = findGitRepoRoot(projectPath) ?: return null
        return detectFromConfFiles(repoRoot)
    }

    /**
     * Matches repo root against loaded .conf file configs.
     */
    private fun detectFromConfFiles(repoRoot: Path): ContextConfig? {
        val repoRootPaths = resolvePaths(repoRoot)

        return _contexts.value.firstOrNull { config ->
            val mainRootPaths = resolvePaths(config.mainRepoRoot)
            repoRootPaths.any { it in mainRootPaths }
        }?.also { log.info("Auto-detected context '${it.name}' from .conf for project") }
    }

    /**
     * Walks up from the given path to find the git repo root.
     * Delegates to GitDirResolver for .git resolution.
     */
    private fun findGitRepoRoot(startPath: Path): Path? {
        var current = startPath.normalize()
        while (true) {
            val mainGitDir = GitDirResolver.resolveMainGitDir(current)
            if (mainGitDir != null) return mainGitDir.parent
            current = current.parent ?: break
        }
        return null
    }

    private fun resolvePaths(path: Path): Set<Path> = buildSet {
        add(path.normalize())
        runCatching { path.toRealPath() }.onSuccess { add(it) }
    }

    companion object {
        fun getInstance(project: Project): ContextService = project.service()
    }
}
