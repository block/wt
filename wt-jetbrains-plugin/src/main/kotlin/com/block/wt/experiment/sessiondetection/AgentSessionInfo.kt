package com.block.wt.experiment.sessiondetection

enum class AgentSessionState {
    RUNNING,            // PID alive AND .jsonl written to within 60s
    IDLE,               // PID alive but .jsonl unchanged for 60s-10m
}

enum class AgentTerminalKind {
    INTELLIJ, ITERM2, TERMINAL_APP, UNKNOWN;

    val displayName: String get() = when (this) {
        INTELLIJ -> "IntelliJ"
        ITERM2 -> "iTerm"
        TERMINAL_APP -> "Terminal"
        UNKNOWN -> ""
    }
}

data class AgentSessionInfo(
    val sessionId: String,
    val state: AgentSessionState,
    val pid: Long?,
    val tty: String?,
    val terminalKind: AgentTerminalKind = AgentTerminalKind.UNKNOWN,
    val lastActivityMs: Long,
    val sessionStartMs: Long,
)
