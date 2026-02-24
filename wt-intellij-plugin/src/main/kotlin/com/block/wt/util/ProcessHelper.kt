package com.block.wt.util

import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.CapturingProcessHandler
import com.intellij.openapi.diagnostic.Logger
import java.nio.file.Path

object ProcessHelper : ProcessRunner {

    private val log = Logger.getInstance(ProcessHelper::class.java)

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
        val cli = GeneralCommandLine(command)
        if (workingDir != null) {
            cli.workDirectory = workingDir.toFile()
        }
        cli.charset = Charsets.UTF_8

        val handler = CapturingProcessHandler(cli)
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

    override fun runGit(args: List<String>, workingDir: Path?): ProcessResult {
        return run(listOf("git") + args, workingDir)
    }
}
