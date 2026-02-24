package com.block.wt.util

import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.CapturingProcessHandler
import com.intellij.execution.process.ProcessEvent
import com.intellij.execution.process.ProcessListener
import com.intellij.execution.process.ProcessOutputTypes
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.util.Key
import java.nio.file.Path

object ProcessHelper : ProcessRunner {

    private val log = Logger.getInstance(ProcessHelper::class.java)

    private val GIT_PROGRESS_REGEX = Regex("""\b(\d{1,3})%""")

    data class ProcessResult(
        val exitCode: Int,
        val stdout: String,
        val stderr: String,
    ) {
        val isSuccess: Boolean get() = exitCode == 0
    }

    override fun run(
        command: List<String>,
        workingDir: Path?,
        timeoutSeconds: Long,
    ): ProcessResult {
        return runInternal(command, workingDir, timeoutSeconds, onProgress = null)
    }

    override fun runGit(args: List<String>, workingDir: Path?): ProcessResult {
        return run(listOf("git") + args, workingDir)
    }

    /**
     * Runs a git command while streaming stderr to parse progress percentages.
     * Git outputs lines like "Receiving objects:  45% (123/273)" to stderr.
     * The [onProgress] callback receives values in 0.0..1.0.
     */
    fun runGitWithProgress(
        args: List<String>,
        workingDir: Path?,
        onProgress: (Double) -> Unit,
    ): ProcessResult {
        return runInternal(listOf("git") + args, workingDir, timeoutSeconds = 300, onProgress = onProgress)
    }

    private fun runInternal(
        command: List<String>,
        workingDir: Path?,
        timeoutSeconds: Long,
        onProgress: ((Double) -> Unit)?,
    ): ProcessResult {
        val cli = GeneralCommandLine(command)
        if (workingDir != null) {
            cli.workDirectory = workingDir.toFile()
        }
        cli.charset = Charsets.UTF_8

        val handler = CapturingProcessHandler(cli)

        if (onProgress != null) {
            handler.addProcessListener(object : ProcessListener {
                override fun onTextAvailable(event: ProcessEvent, outputType: Key<*>) {
                    if (outputType == ProcessOutputTypes.STDERR) {
                        val match = GIT_PROGRESS_REGEX.find(event.text)
                        if (match != null) {
                            val pct = match.groupValues[1].toIntOrNull() ?: return
                            onProgress(pct.coerceIn(0, 100) / 100.0)
                        }
                    }
                }
            })
        }

        val output = handler.runProcess((timeoutSeconds * 1000).toInt())

        if (output.isTimeout) {
            log.warn("Command timed out after ${timeoutSeconds}s: ${command.joinToString(" ")}")
            return ProcessResult(-1, output.stdout, "Process timed out after ${timeoutSeconds}s")
        }

        val result = ProcessResult(
            exitCode = output.exitCode,
            stdout = output.stdout,
            stderr = output.stderr,
        )
        if (!result.isSuccess) {
            log.debug("Command failed (exit=${result.exitCode}): ${command.joinToString(" ")}${if (result.stderr.isNotBlank()) "\nstderr: ${result.stderr.trim()}" else ""}")
        }
        return result
    }
}
