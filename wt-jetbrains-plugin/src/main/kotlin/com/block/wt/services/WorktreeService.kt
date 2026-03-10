package com.block.wt.services

import com.block.wt.agent.AgentDetection
import com.block.wt.agent.AgentDetector
import com.block.wt.experiment.sessiondetection.EnhancedAgentDetector
import com.block.wt.experiment.sessiondetection.EnhancedAgentStatusEnricher
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
    private val prLoader by lazy { PullRequestLoader(processRunner) }
    private val enrichers: List<WorktreeEnricher> by lazy {
        val agentEnricher = if (WtPluginSettings.getInstance().state.enhancedSessionDetection) {
            EnhancedAgentStatusEnricher(EnhancedAgentDetector(agentDetection))
        } else {
            AgentStatusEnricher(agentDetection)
        }
        listOf(
            ProvisionStatusEnricher(ContextService.getInstance(project)),
            agentEnricher,
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
                // Carry forward previous PR info to avoid flicker (blank → loaded)
                val previousByPath = _worktrees.value.associateBy { it.path }
                val listWithPrCarryForward = list.map { wt ->
                    val prev = previousByPath[wt.path]
                    if (prev != null && wt.branch == prev.branch) {
                        wt.copy(prInfo = prev.prInfo)
                    } else {
                        wt
                    }
                }
                _worktrees.value = listWithPrCarryForward
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

                // Detect repo slug for "Create PR" links (before PR jobs so it's available on click)
                val repoRoot = getMainRepoRoot()
                if (repoRoot != null) {
                    _repoSlug = prLoader.detectRepoSlug(repoRoot)
                }

                // Async-load PR info for each worktree
                val currentList = _worktrees.value
                val prJobs = currentList.withIndex().map { (index, wt) ->
                    async {
                        val prInfo = prLoader.loadPRInfo(wt)
                        statusMutex.withLock {
                            val current = _worktrees.value.toMutableList()
                            if (index < current.size && current[index].path == wt.path) {
                                current[index] = current[index].copy(prInfo = prInfo)
                                _worktrees.value = current
                            }
                        }
                    }
                }
                prJobs.awaitAll()
            } finally {
                _isLoading.value = false
            }
        }
    }

    suspend fun listWorktrees(): List<WorktreeInfo> = withContext(Dispatchers.IO) {
        val repoRoot = getMainRepoRoot() ?: return@withContext emptyList()

        // worktree list has no programmatic API — use subprocess
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

    /**
     * Loads status via `git status --porcelain=v1 -b` subprocess.
     * Runs in a separate process — zero JVM heap impact
     * for DirCache, pack indices, and working tree scanning.
     */
    private suspend fun loadStatusIndicators(wt: WorktreeInfo): WorktreeInfo = withContext(Dispatchers.IO) {
        val result = processRunner.runGit(
            listOf("status", "--porcelain=v1", "-b"),
            workingDir = wt.path,
        )
        if (!result.isSuccess) {
            log.warn("git status failed for ${wt.path}: ${result.stderr.trim()}")
            return@withContext wt
        }
        parseGitStatusOutput(wt, result.stdout)
    }

    internal fun parseGitStatusOutput(wt: WorktreeInfo, output: String): WorktreeInfo =
        parseGitStatus(wt, output)

    // --- PR info ---

    @Volatile
    private var _repoSlug: String? = null

    /** The GitHub owner/repo slug (e.g. "block/wt"), available after first refresh. */
    val repoSlug: String? get() = _repoSlug

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

/**
 * Parses `git status --porcelain=v1 -b` output.
 *
 * Format:
 * ```
 * ## branch...origin/branch [ahead 1, behind 2]
 * M  staged-file.txt
 *  M unstaged-file.txt
 * ?? untracked.txt
 * UU conflicting.txt
 * ```
 */
internal fun parseGitStatus(wt: WorktreeInfo, output: String): WorktreeInfo {
    var staged = 0; var modified = 0; var untracked = 0; var conflicts = 0
    var ahead: Int? = null; var behind: Int? = null

    for (line in output.lines()) {
        if (line.startsWith("## ")) {
            // Parse branch line: "## branch...origin/branch [ahead 1, behind 2]"
            val bracketContent = line.substringAfter("[", "").substringBefore("]", "")
            if (bracketContent.isNotEmpty()) {
                for (part in bracketContent.split(",")) {
                    val trimmed = part.trim()
                    if (trimmed.startsWith("ahead ")) {
                        ahead = trimmed.removePrefix("ahead ").trim().toIntOrNull()
                    } else if (trimmed.startsWith("behind ")) {
                        behind = trimmed.removePrefix("behind ").trim().toIntOrNull()
                    }
                }
            }
            continue
        }
        if (line.length < 2) continue
        val x = line[0] // staged status
        val y = line[1] // unstaged status

        // Conflicts: UU, AA, DD, AU, UA, DU, UD
        if ((x == 'U' || y == 'U') || (x == 'A' && y == 'A') || (x == 'D' && y == 'D')) {
            conflicts++; continue
        }
        // Untracked
        if (x == '?' && y == '?') { untracked++; continue }
        // Staged changes (X column)
        if (x in "MADRC") staged++
        // Unstaged changes (Y column)
        if (y in "MD") modified++
    }

    return wt.copy(
        status = WorktreeStatus.Loaded(staged, modified, untracked, conflicts, ahead, behind),
    )
}
