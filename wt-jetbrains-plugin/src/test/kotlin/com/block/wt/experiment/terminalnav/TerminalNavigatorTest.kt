package com.block.wt.experiment.terminalnav

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TerminalNavigatorTest {

    // --- TTY validation ---

    @Test
    fun testValidateTtyValid() {
        assertTrue(TerminalNavigator.validateTty("ttys000"))
        assertTrue(TerminalNavigator.validateTty("ttys123"))
        assertTrue(TerminalNavigator.validateTty("ttys999"))
    }

    @Test
    fun testValidateTtyRejectsInjection() {
        assertFalse(TerminalNavigator.validateTty("ttys000\" then\ndo shell script \"evil"))
        assertFalse(TerminalNavigator.validateTty("/dev/ttys000"))
        assertFalse(TerminalNavigator.validateTty(""))
        assertFalse(TerminalNavigator.validateTty("pts/0"))
        assertFalse(TerminalNavigator.validateTty("??"))
    }

    @Test
    fun testValidateTtyRejectsNonNumericSuffix() {
        assertFalse(TerminalNavigator.validateTty("ttysabc"))
        assertFalse(TerminalNavigator.validateTty("ttys"))
    }

    // --- TTY resolution ---

    @Test
    fun testResolveTtyForNonexistentPid() {
        // PID 999999999 should not exist — should not crash
        val tty = TerminalNavigator.resolveTty(999999999L)
        // Result is null when PID doesn't exist (ps returns no output or error)
        // This test just verifies no exception is thrown
        assertTrue(tty == null || tty is String)
    }

    // --- Terminal owner resolution ---

    @Test
    fun testResolveTerminalOwnerForNonexistentPid() {
        val kind = TerminalNavigator.resolveTerminalOwner(999999999L)
        assertTrue(kind == TerminalNavigator.TerminalKind.UNKNOWN)
    }

    @Test
    fun testGetProcessCommForNonexistentPid() {
        // Should not crash for non-existent PID
        val comm = TerminalNavigator.getProcessComm(999999999L)
        assertTrue(comm == null || comm is String)
    }

    @Test
    fun testGetParentPidForNonexistentPid() {
        val ppid = TerminalNavigator.getParentPid(999999999L)
        assertTrue(ppid == null)
    }
}
