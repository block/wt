package com.block.wt.services

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
import java.nio.file.Files
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
        _config.value = detectContext()
    }

    fun getCurrentConfig(): ContextConfig? = _config.value

    fun addContext(config: ContextConfig) {
        val confFile = PathHelper.reposDir.resolve("${config.name}.conf")
        ConfigFileHelper.writeConfig(confFile, config)
        reload()
    }

    /**
     * Finds the git repo root from the project path, then matches it
     * against each config's mainRepoRoot.
     */
    private fun detectContext(): ContextConfig? {
        val projectPath = project.basePath?.let { Path.of(it) } ?: return null
        val repoRoot = findGitRepoRoot(projectPath) ?: return null
        val repoRootPaths = resolvePaths(repoRoot)

        return _contexts.value.firstOrNull { config ->
            val mainRootPaths = resolvePaths(config.mainRepoRoot)
            repoRootPaths.any { it in mainRootPaths }
        }?.also { log.info("Auto-detected context '${it.name}' for $projectPath") }
    }

    /**
     * Walks up from the given path to find the git repo root.
     * For linked worktrees (.git is a file), follows the gitdir pointer
     * to resolve the main repo root.
     */
    private fun findGitRepoRoot(startPath: Path): Path? {
        var current = startPath.normalize()
        while (true) {
            val dotGit = current.resolve(".git")
            when {
                Files.isDirectory(dotGit) -> return current
                Files.isRegularFile(dotGit) -> {
                    return resolveMainRepoFromGitFile(dotGit) ?: current
                }
            }
            current = current.parent ?: break
        }
        return null
    }

    /**
     * Reads a linked worktree's .git file ("gitdir: /path/to/main/.git/worktrees/name")
     * and returns the main repo root (parent of the .git directory).
     */
    private fun resolveMainRepoFromGitFile(dotGitFile: Path): Path? {
        return try {
            val content = Files.readString(dotGitFile).trim()
            if (!content.startsWith("gitdir: ")) return null
            val gitDir = Path.of(content.removePrefix("gitdir: ")).let {
                if (it.isAbsolute) it else dotGitFile.parent.resolve(it).normalize()
            }
            var dir = gitDir
            while (dir.parent != null) {
                if (dir.fileName?.toString() == ".git") return dir.parent
                dir = dir.parent
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun resolvePaths(path: Path): Set<Path> = buildSet {
        add(path.normalize())
        runCatching { path.toRealPath() }.onSuccess { add(it) }
    }

    companion object {
        fun getInstance(project: Project): ContextService = project.service()
    }
}
