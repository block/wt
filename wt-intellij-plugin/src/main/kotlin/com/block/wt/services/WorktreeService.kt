package com.block.wt.services

import com.block.wt.agent.AgentDetection
import com.block.wt.agent.AgentDetector
import com.block.wt.git.GitParser
import com.block.wt.model.WorktreeInfo
import com.block.wt.model.WorktreeStatus
import com.block.wt.settings.WtPluginSettings
import com.block.wt.util.PathHelper
import com.block.wt.util.ProcessHelper
import com.block.wt.util.ProcessRunner
import com.block.wt.util.normalizeSafe
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.service
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import git4idea.repo.GitRepositoryManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.nio.file.Path

@Service(Service.Level.PROJECT)
class WorktreeService(
    private val project: Project,
    private val cs: CoroutineScope,
) {
    private val log = Logger.getInstance(WorktreeService::class.java)

    // Injectable for testing — default to production singletons
    internal var processRunner: ProcessRunner = ProcessHelper
    internal var agentDetection: AgentDetection = AgentDetector

    private val gitClient by lazy { GitClient(processRunner) }
    private val enrichers: List<WorktreeEnricher> by lazy {
        listOf(
            ProvisionStatusEnricher(ContextService.getInstance(project)),
            AgentStatusEnricher(agentDetection),
        )
    }
    private val refreshScheduler = WorktreeRefreshScheduler(cs) { refreshWorktreeList() }

    private val _worktrees = MutableStateFlow<List<WorktreeInfo>>(emptyList())
    val worktrees: StateFlow<List<WorktreeInfo>> = _worktrees.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val statusMutex = Mutex()

    fun refreshWorktreeList() {
        _isLoading.value = true
        cs.launch {
            try {
                val list = listWorktrees()
                _worktrees.value = list
                lastRefreshTime = System.currentTimeMillis()

                // Async-load status indicators (skip if disabled in settings)
                if (!WtPluginSettings.getInstance().state.statusLoadingEnabled) return@launch
                val statusJobs = list.withIndex().map { (index, wt) ->
                    async {
                        val loadedStatus = loadStatusIndicators(wt).status
                        statusMutex.withLock {
                            val current = _worktrees.value.toMutableList()
                            if (index < current.size && current[index].path == wt.path) {
                                current[index] = current[index].copy(status = loadedStatus)
                                _worktrees.value = current
                            }
                        }
                    }
                }
                statusJobs.awaitAll()
            } finally {
                _isLoading.value = false
            }
        }
    }

    suspend fun listWorktrees(): List<WorktreeInfo> = withContext(Dispatchers.IO) {
        val repoRoot = getMainRepoRoot() ?: return@withContext emptyList()

        val result = processRunner.runGit(
            listOf("worktree", "list", "--porcelain"),
            workingDir = repoRoot,
        )

        if (!result.isSuccess) {
            log.warn("git worktree list failed (exit=${result.exitCode}): ${result.stderr.trim()}")
            return@withContext emptyList()
        }

        val linkedPath = getLinkedWorktreePath()
        parseAndEnrich(result.stdout, linkedPath)
    }

    internal fun parseAndEnrich(porcelainOutput: String, linkedPath: Path?): List<WorktreeInfo> {
        val parsed = GitParser.parsePorcelainOutput(porcelainOutput, linkedPath)
        return enrichers.fold(parsed) { list, enricher -> enricher.enrich(list) }
    }

    private suspend fun loadStatusIndicators(wt: WorktreeInfo): WorktreeInfo = withContext(Dispatchers.IO) {
        // Parse full git status
        var staged = 0
        var modified = 0
        var untracked = 0
        var conflicts = 0
        var statusLoaded = false

        try {
            val result = processRunner.runGit(
                listOf("status", "--porcelain"),
                workingDir = wt.path,
            )
            if (result.isSuccess) {
                statusLoaded = true
                for (line in result.stdout.lines()) {
                    if (line.length < 2) continue
                    val x = line[0] // index (staged) status
                    val y = line[1] // working tree status

                    when {
                        // Unmerged (conflict) entries
                        (x == 'U' || y == 'U') || (x == 'A' && y == 'A') || (x == 'D' && y == 'D') -> conflicts++
                        // Untracked
                        x == '?' -> untracked++
                        // Ignored
                        x == '!' -> { /* skip */ }
                        else -> {
                            // Staged changes (index column has a letter, not space or ?)
                            if (x != ' ' && x != '?') staged++
                            // Unstaged changes (working tree column has a letter, not space)
                            if (y != ' ' && y != '?') modified++
                        }
                    }
                }
            }
        } catch (e: Exception) {
            log.warn("Failed to load status for ${wt.path}", e)
        }

        val (ahead, behind) = try {
            val result = processRunner.runGit(
                listOf("rev-list", "--left-right", "--count", "@{upstream}...HEAD"),
                workingDir = wt.path,
            )
            if (result.isSuccess) {
                val parts = result.stdout.trim().split("\t")
                if (parts.size == 2) {
                    Pair(parts[1].toIntOrNull(), parts[0].toIntOrNull())
                } else {
                    Pair(null, null)
                }
            } else {
                Pair(null, null)
            }
        } catch (e: Exception) {
            log.warn("Failed to load ahead/behind for ${wt.path}", e)
            Pair(null, null)
        }

        if (statusLoaded) {
            wt.copy(
                status = WorktreeStatus.Loaded(
                    staged = staged, modified = modified,
                    untracked = untracked, conflicts = conflicts,
                    ahead = ahead, behind = behind,
                ),
            )
        } else if (ahead != null || behind != null) {
            wt.copy(
                status = WorktreeStatus.Loaded(
                    staged = 0, modified = 0,
                    untracked = 0, conflicts = 0,
                    ahead = ahead, behind = behind,
                ),
            )
        } else {
            wt
        }
    }

    // --- Facade delegates to GitClient ---

    suspend fun createWorktree(
        path: Path,
        branch: String,
        createNewBranch: Boolean = false,
        onProgress: ((Double) -> Unit)? = null,
    ): Result<Unit> {
        val repoRoot = getMainRepoRoot()
            ?: return Result.failure(IllegalStateException("No git repository found"))
        return gitClient.createWorktree(repoRoot, path, branch, createNewBranch, onProgress)
    }

    suspend fun removeWorktree(path: Path, force: Boolean = false): Result<Unit> {
        val repoRoot = getMainRepoRoot()
            ?: return Result.failure(IllegalStateException("No git repository found"))
        return gitClient.removeWorktree(repoRoot, path, force)
    }

    suspend fun getMergedBranches(): List<String> {
        val repoRoot = getMainRepoRoot() ?: return emptyList()
        val contextService = ContextService.getInstance(project)
        val baseBranch = contextService.getCurrentConfig()?.baseBranch ?: "main"
        return gitClient.getMergedBranches(repoRoot, baseBranch)
    }

    suspend fun hasUncommittedChanges(worktreePath: Path): Boolean =
        gitClient.hasUncommittedChanges(worktreePath)

    suspend fun stashSave(worktreePath: Path, name: String): Result<Unit> =
        gitClient.stashSave(worktreePath, name)

    suspend fun stashPop(worktreePath: Path, name: String): Result<Unit> =
        gitClient.stashPop(worktreePath, name)

    suspend fun checkout(worktreePath: Path, branchOrRev: String): Result<Unit> =
        gitClient.checkout(worktreePath, branchOrRev)

    suspend fun pullFfOnly(worktreePath: Path, onProgress: ((Double) -> Unit)? = null): Result<Unit> =
        gitClient.pullFfOnly(worktreePath, onProgress)

    suspend fun getCurrentBranch(worktreePath: Path): String? =
        gitClient.getCurrentBranch(worktreePath)

    suspend fun getCurrentRevision(worktreePath: Path): String? =
        gitClient.getCurrentRevision(worktreePath)

    // --- Repo root resolution ---

    fun getMainRepoRoot(): Path? {
        val contextService = ContextService.getInstance(project)
        val config = contextService.getCurrentConfig()
        if (config != null) return config.mainRepoRoot

        // Fallback: use the project's git root
        val repos = GitRepositoryManager.getInstance(project).repositories
        return repos.firstOrNull()?.root?.toNioPath()
    }

    private fun getLinkedWorktreePath(): Path? {
        val contextService = ContextService.getInstance(project)
        val config = contextService.getCurrentConfig() ?: return null
        val symlinkPath = config.activeWorktree
        return PathHelper.readSymlink(symlinkPath)?.normalizeSafe()
    }

    // --- Periodic refresh ---

    @Volatile
    var lastRefreshTime: Long = 0L
        private set

    fun startPeriodicRefresh() = refreshScheduler.start()

    fun stopPeriodicRefresh() = refreshScheduler.stop()

    companion object {
        fun getInstance(project: Project): WorktreeService = project.service()
    }
}
