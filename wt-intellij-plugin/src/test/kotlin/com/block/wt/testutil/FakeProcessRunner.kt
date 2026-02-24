package com.block.wt.testutil

import com.block.wt.util.ProcessHelper
import com.block.wt.util.ProcessRunner
import java.nio.file.Path

class FakeProcessRunner(
    private val responses: Map<List<String>, ProcessHelper.ProcessResult> = emptyMap(),
) : ProcessRunner {

    private val defaultResult = ProcessHelper.ProcessResult(exitCode = 1, stdout = "", stderr = "not configured")

    override fun run(command: List<String>, workingDir: Path?, timeoutSeconds: Long): ProcessHelper.ProcessResult {
        return responses[command] ?: defaultResult
    }

    override fun runGit(args: List<String>, workingDir: Path?): ProcessHelper.ProcessResult {
        return responses[listOf("git") + args] ?: responses[args] ?: defaultResult
    }
}
