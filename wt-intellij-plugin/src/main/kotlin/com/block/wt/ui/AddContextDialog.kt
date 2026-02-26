package com.block.wt.ui

import com.block.wt.model.MetadataPattern
import com.block.wt.util.PathHelper
import com.block.wt.util.ProcessHelper
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.openapi.ui.ValidationInfo
import com.intellij.ui.components.JBCheckBox
import com.intellij.ui.components.JBLabel
import com.intellij.ui.components.JBTextField
import com.intellij.ui.dsl.builder.panel
import java.nio.file.Files
import java.nio.file.Path
import javax.swing.JComponent
import javax.swing.event.DocumentEvent
import javax.swing.event.DocumentListener

class AddContextDialog(private val project: Project?) : DialogWrapper(project) {

    private val repoPathField = JBTextField().apply { isEditable = false }
    private val contextNameField = JBTextField()
    private val baseBranchField = JBTextField()
    private val activeWorktreeField = JBTextField()
    private val worktreesBaseLabel = JBLabel()
    private val ideaFilesBaseLabel = JBLabel()
    private val patternCheckboxes = mutableListOf<Pair<JBCheckBox, String>>()

    private var isGitRepo: Boolean = false

    var repoPath: Path? = null
        private set
    var contextName: String = ""
        private set
    var baseBranch: String = "main"
        private set
    var activeWorktree: Path? = null
        private set
    var worktreesBase: Path? = null
        private set
    var ideaFilesBase: Path? = null
        private set
    var selectedPatterns: List<String> = emptyList()
        private set

    init {
        title = "Add Context"
        init()
        prefillFromProject()
        setupAutoDerivation()
    }

    private fun prefillFromProject() {
        val basePath = project?.basePath ?: return
        // Resolve to git root (follow symlinks, find actual repo root)
        val projectPath = Path.of(basePath)
        val resolved = runCatching { projectPath.toRealPath() }.getOrElse { projectPath.normalize() }
        repoPathField.text = resolved.toString()
        rederive()
    }

    private fun setupAutoDerivation() {
        contextNameField.document.addDocumentListener(object : DocumentListener {
            override fun insertUpdate(e: DocumentEvent) = rederivePaths()
            override fun removeUpdate(e: DocumentEvent) = rederivePaths()
            override fun changedUpdate(e: DocumentEvent) = rederivePaths()
        })
    }

    private fun rederive() {
        val pathStr = repoPathField.text.trim()
        if (pathStr.isBlank()) return

        val path = Path.of(pathStr)
        if (!Files.isDirectory(path)) return

        // Auto-derive context name from repo basename
        val basename = path.fileName?.toString() ?: return
        val name = basename
            .removeSuffix("-master")
            .removeSuffix("-main")
        contextNameField.text = name

        // Auto-detect base branch and validate git repo (runs git subprocess off EDT)
        data class DeriveResult(val branch: String, val isGit: Boolean)
        val result = ProgressManager.getInstance().runProcessWithProgressSynchronously<DeriveResult, Exception>(
            {
                val isGit = ProcessHelper.runGit(listOf("rev-parse", "--git-dir"), workingDir = path).isSuccess
                val branch = if (isGit) detectBaseBranch(path) else "main"
                DeriveResult(branch, isGit)
            },
            "Detecting Repository Info",
            false,
            project,
        )
        isGitRepo = result.isGit
        baseBranchField.text = result.branch

        // Auto-derive active worktree
        activeWorktreeField.text = path.toString()

        // Detect metadata patterns
        detectAndShowPatterns(path)

        rederivePaths()
    }

    private fun rederivePaths() {
        val name = contextNameField.text.trim()
        if (name.isBlank()) return

        val wBase = PathHelper.reposDir.resolve(name).resolve("worktrees")
        val iBase = PathHelper.reposDir.resolve(name).resolve("idea-files")
        worktreesBaseLabel.text = wBase.toString()
        ideaFilesBaseLabel.text = iBase.toString()
    }

    private fun detectBaseBranch(repoPath: Path): String {
        try {
            val result = ProcessHelper.runGit(
                listOf("symbolic-ref", "refs/remotes/origin/HEAD"),
                workingDir = repoPath,
            )
            if (result.isSuccess) {
                val ref = result.stdout.trim()
                return ref.substringAfterLast("/")
            }
        } catch (_: Exception) {}

        // Fallback: check if main or master exists
        for (branch in listOf("main", "master")) {
            try {
                val result = ProcessHelper.runGit(
                    listOf("rev-parse", "--verify", "refs/heads/$branch"),
                    workingDir = repoPath,
                )
                if (result.isSuccess) return branch
            } catch (_: Exception) {}
        }

        return "main"
    }

    private fun detectAndShowPatterns(repoPath: Path) {
        patternCheckboxes.clear()
        for (pattern in MetadataPattern.KNOWN_PATTERNS) {
            val candidate = repoPath.resolve(pattern.name)
            if (Files.exists(candidate)) {
                val checkbox = JBCheckBox("${pattern.name} - ${pattern.description}", true)
                patternCheckboxes.add(Pair(checkbox, pattern.name))
            }
        }
    }

    override fun createCenterPanel(): JComponent {
        return panel {
            row("Repository path:") {
                cell(repoPathField).resizableColumn()
            }
            row("Context name:") {
                cell(contextNameField).resizableColumn()
            }
            row("Base branch:") {
                cell(baseBranchField).resizableColumn()
            }
            row("Active worktree:") {
                cell(activeWorktreeField).resizableColumn()
            }
            row("Worktrees base:") {
                cell(worktreesBaseLabel)
            }
            row("Metadata vault:") {
                cell(ideaFilesBaseLabel)
            }
            if (patternCheckboxes.isNotEmpty()) {
                group("Metadata Patterns") {
                    for ((checkbox, _) in patternCheckboxes) {
                        row { cell(checkbox) }
                    }
                }
            }
        }
    }

    override fun doValidate(): ValidationInfo? {
        val pathStr = repoPathField.text.trim()
        if (pathStr.isBlank()) {
            return ValidationInfo("Repository path is required", repoPathField)
        }
        val path = Path.of(pathStr)
        if (!Files.isDirectory(path)) {
            return ValidationInfo("Directory does not exist", repoPathField)
        }
        // Check it's a git repo (computed off-EDT during rederive)
        if (!isGitRepo) {
            return ValidationInfo("Not a git repository", repoPathField)
        }

        val name = contextNameField.text.trim()
        if (name.isBlank()) {
            return ValidationInfo("Context name is required", contextNameField)
        }
        if (!name.matches(Regex("[a-zA-Z0-9_-]+"))) {
            return ValidationInfo("Context name must contain only letters, digits, hyphens, and underscores", contextNameField)
        }
        val existingConf = PathHelper.reposDir.resolve("$name.conf")
        if (Files.exists(existingConf)) {
            return ValidationInfo("A context named '$name' already exists", contextNameField)
        }

        if (baseBranchField.text.trim().isBlank()) {
            return ValidationInfo("Base branch is required", baseBranchField)
        }

        if (activeWorktreeField.text.trim().isBlank()) {
            return ValidationInfo("Active worktree path is required", activeWorktreeField)
        }

        return null
    }

    override fun doOKAction() {
        val pathStr = repoPathField.text.trim()
        repoPath = Path.of(pathStr)
        contextName = contextNameField.text.trim()
        baseBranch = baseBranchField.text.trim()
        activeWorktree = Path.of(activeWorktreeField.text.trim())
        worktreesBase = PathHelper.reposDir.resolve(contextName).resolve("worktrees")
        ideaFilesBase = PathHelper.reposDir.resolve(contextName).resolve("idea-files")
        selectedPatterns = patternCheckboxes
            .filter { it.first.isSelected }
            .map { it.second }
        super.doOKAction()
    }
}
