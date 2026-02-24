package com.block.wt.util

import java.nio.file.Path

/**
 * Interface for running external processes. Production implementation uses IntelliJ's
 * OSProcessHandler; test implementation returns canned responses.
 */
interface ProcessRunner {
    fun run(command: List<String>, workingDir: Path? = null, timeoutSeconds: Long = 60): ProcessHelper.ProcessResult
    fun runGit(args: List<String>, workingDir: Path? = null): ProcessHelper.ProcessResult
}
