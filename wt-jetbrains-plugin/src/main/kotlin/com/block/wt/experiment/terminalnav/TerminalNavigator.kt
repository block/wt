package com.block.wt.experiment.terminalnav

import com.block.wt.ui.Notifications
import com.block.wt.util.PlatformUtil
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project

/**
 * Navigates to the terminal window hosting an agent process.
 * Detects terminal ownership via process tree walk, then dispatches
 * to the appropriate strategy (IntelliJ, iTerm2, or Terminal.app).
 */
object TerminalNavigator {

    private val log = Logger.getInstance(TerminalNavigator::class.java)
    private val TTY_PATTERN = Regex("^ttys\\d+$")

    private val IDE_BINARY_NAMES = setOf(
        "idea", "goland", "pycharm", "webstorm", "clion",
        "rider", "rubymine", "phpstorm", "appcode", "datagrip",
        "dataspell", "fleet", "studio",
    )

    internal fun isIdeLauncherComm(comm: String): Boolean {
        val binaryName = comm.substringAfterLast("/").lowercase()
        return binaryName in IDE_BINARY_NAMES
    }

    enum class TerminalKind { INTELLIJ, ITERM2, TERMINAL_APP, UNKNOWN }

    fun navigateToTerminal(project: Project, pid: Long, tty: String?) {
        val resolvedTty = tty ?: resolveTty(pid)
        val owner = resolveTerminalOwner(pid)

        when (owner) {
            TerminalKind.ITERM2 -> {
                if (resolvedTty != null && PlatformUtil.isMacOS()) {
                    navigateITerm2(resolvedTty)
                } else {
                    notifyUnresolved(project, pid, resolvedTty)
                }
            }
            TerminalKind.TERMINAL_APP -> {
                if (resolvedTty != null && PlatformUtil.isMacOS()) {
                    navigateTerminalApp(resolvedTty)
                } else {
                    notifyUnresolved(project, pid, resolvedTty)
                }
            }
            TerminalKind.INTELLIJ -> {
                activateIntelliJTerminal(project, resolvedTty)
            }
            TerminalKind.UNKNOWN -> {
                notifyUnresolved(project, pid, resolvedTty)
            }
        }
    }

    /** Resolves the TTY for a PID via `ps -o tty= -p <pid>`. */
    internal fun resolveTty(pid: Long): String? {
        if (PlatformUtil.isWindows()) return null
        return try {
            val process = ProcessBuilder("ps", "-o", "tty=", "-p", pid.toString())
                .redirectErrorStream(true)
                .start()
            val tty = process.inputStream.bufferedReader().readText().trim()
            process.waitFor()
            if (tty.isNotEmpty() && tty != "??" && tty != "?") tty else null
        } catch (e: Exception) {
            log.debug("Failed to resolve TTY for PID $pid", e)
            null
        }
    }

    /**
     * Walks the process tree upward to find the ancestor terminal process.
     * Matches ancestor `comm` name to determine the terminal kind.
     */
    internal fun resolveTerminalOwner(pid: Long): TerminalKind {
        if (PlatformUtil.isWindows()) return TerminalKind.UNKNOWN
        var currentPid = pid
        val visited = mutableSetOf<Long>()

        while (currentPid > 1 && visited.add(currentPid)) {
            val commName = getProcessComm(currentPid)
            if (commName != null) {
                val lower = commName.lowercase()
                if (lower.contains("iterm2") || lower == "iterm") return TerminalKind.ITERM2
                if (lower == "terminal" || lower.contains("terminal.app")) return TerminalKind.TERMINAL_APP
                if (lower.contains("idea") || lower.contains("intellij") || lower.contains("goland") ||
                    lower.contains("pycharm") || lower.contains("webstorm") || lower.contains("clion") ||
                    lower.contains("rider") || lower.contains("rubymine") || lower.contains("phpstorm")) {
                    return TerminalKind.INTELLIJ
                }
            }

            val ppid = getParentPid(currentPid)
            if (ppid == null || ppid == currentPid) break
            currentPid = ppid
        }

        return TerminalKind.UNKNOWN
    }

    internal fun getProcessComm(pid: Long): String? {
        return try {
            val process = ProcessBuilder("ps", "-o", "comm=", "-p", pid.toString())
                .redirectErrorStream(true)
                .start()
            val comm = process.inputStream.bufferedReader().readText().trim()
            process.waitFor()
            comm.ifEmpty { null }
        } catch (e: Exception) {
            log.debug("Failed to get comm for PID $pid", e)
            null
        }
    }

    internal fun getParentPid(pid: Long): Long? {
        return try {
            val process = ProcessBuilder("ps", "-o", "ppid=", "-p", pid.toString())
                .redirectErrorStream(true)
                .start()
            val ppid = process.inputStream.bufferedReader().readText().trim().toLongOrNull()
            process.waitFor()
            ppid
        } catch (e: Exception) {
            log.debug("Failed to get parent PID for PID $pid", e)
            null
        }
    }

    private fun navigateITerm2(tty: String) {
        if (!validateTty(tty)) return
        val script = """
            tell application "iTerm2"
                repeat with aWindow in every window
                    repeat with aTab in every tab of aWindow
                        repeat with aSession in every session of aTab
                            if tty of aSession is "/dev/$tty" then
                                tell aTab to select
                                tell aWindow to select
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
        """.trimIndent()
        runAppleScript(script)
    }

    private fun navigateTerminalApp(tty: String) {
        if (!validateTty(tty)) return
        val script = """
            tell application "Terminal"
                repeat with aWindow in every window
                    repeat with aTab in every tab of aWindow
                        if tty of aTab is "/dev/$tty" then
                            set selected tab of aWindow to aTab
                            set frontmost of aWindow to true
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end tell
        """.trimIndent()
        runAppleScript(script)
    }

    private fun activateIntelliJTerminal(project: Project, tty: String?) {
        try {
            val toolWindow = com.intellij.openapi.wm.ToolWindowManager.getInstance(project)
                .getToolWindow("Terminal") ?: return

            toolWindow.activate {
                if (tty == null) return@activate

                val contentManager = toolWindow.contentManager
                val contents = contentManager.contents
                if (contents.isEmpty()) return@activate

                // Find which shell on our target TTY is a direct child of the IntelliJ
                // native launcher. IntelliJ spawns one shell per terminal tab.
                val ideaPid = findIdeaNativePid()
                if (ideaPid == null) return@activate

                // Get all shell children of the idea process, sorted by PID.
                // Tab order in IntelliJ matches creation order, which matches PID order.
                val shellChildren = findChildShellPids(ideaPid)
                if (shellChildren.isEmpty()) return@activate

                // Find which shell is on our target TTY
                val targetShellPid = shellChildren.firstOrNull { pid ->
                    val shellTty = resolveTty(pid)
                    shellTty == tty
                }
                if (targetShellPid == null) return@activate

                // Map shell PID position to tab index
                val tabIndex = shellChildren.indexOf(targetShellPid)
                if (tabIndex in contents.indices) {
                    contentManager.setSelectedContent(contents[tabIndex])
                }
            }
        } catch (e: Exception) {
            log.debug("Failed to activate IntelliJ terminal", e)
        }
    }

    /**
     * Finds the PID of the native IntelliJ launcher process (the `idea` binary).
     * Terminal shells are direct children of this process, not of the JVM.
     */
    private fun findIdeaNativePid(): Long? {
        return try {
            // Walk up from the current JVM process to find the IDE launcher
            var pid = ProcessHandle.current().pid()
            val visited = mutableSetOf<Long>()
            while (pid > 1 && visited.add(pid)) {
                val comm = getProcessComm(pid)
                if (comm != null && isIdeLauncherComm(comm)) {
                    return pid
                }
                val ppid = getParentPid(pid)
                if (ppid == null || ppid == pid) break
                pid = ppid
            }
            // Fallback: search by process name across all known IDE binaries
            IDE_BINARY_NAMES.firstNotNullOfOrNull { findPidByComm(it) }
        } catch (_: Exception) { null }
    }

    private fun findPidByComm(name: String): Long? {
        if (PlatformUtil.isWindows()) return null
        return try {
            val process = ProcessBuilder("pgrep", "-x", name)
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().readText()
            process.waitFor()
            output.lines().firstNotNullOfOrNull { it.trim().toLongOrNull() }
        } catch (_: Exception) { null }
    }

    /**
     * Finds direct child PIDs of [parentPid] that are shell processes, sorted by PID.
     * Uses `ps -eo pid,ppid,comm` and filters, since macOS `ps` doesn't support `-ppid`.
     */
    private fun findChildShellPids(parentPid: Long): List<Long> {
        if (PlatformUtil.isWindows()) return emptyList()
        return try {
            val process = ProcessBuilder("ps", "-eo", "pid=,ppid=,comm=")
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().readText()
            process.waitFor()
            output.lines()
                .mapNotNull { line ->
                    val parts = line.trim().split(Regex("\\s+"), 3)
                    if (parts.size == 3) {
                        val pid = parts[0].toLongOrNull()
                        val ppid = parts[1].toLongOrNull()
                        val comm = parts[2]
                        if (pid != null && ppid == parentPid && isShellName(comm)) pid else null
                    } else null
                }
                .sorted()
        } catch (_: Exception) { emptyList() }
    }

    private fun isShellName(comm: String): Boolean {
        val name = comm.substringAfterLast("/").removePrefix("-")
        return name in setOf("zsh", "bash", "sh", "fish", "tcsh", "csh", "ksh")
    }

    /** Validates TTY string matches expected format to prevent AppleScript injection. */
    internal fun validateTty(tty: String): Boolean = TTY_PATTERN.matches(tty)

    private fun runAppleScript(script: String) {
        try {
            val process = ProcessBuilder("osascript", "-e", script)
                .redirectErrorStream(true)
                .start()
            process.waitFor()
        } catch (e: Exception) {
            log.debug("AppleScript execution failed", e)
        }
    }

    private fun notifyUnresolved(project: Project, pid: Long, tty: String?) {
        val ttyInfo = if (tty != null) " on TTY $tty" else ""
        Notifications.info(
            project,
            "Agent Terminal",
            "Agent PID $pid$ttyInfo \u2014 could not locate terminal window"
        )
    }

}
