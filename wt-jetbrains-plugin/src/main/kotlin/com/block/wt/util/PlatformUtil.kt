package com.block.wt.util

/** Shared OS detection to avoid duplicating `System.getProperty("os.name")` checks. */
object PlatformUtil {
    fun isWindows(): Boolean = System.getProperty("os.name").lowercase().contains("win")
    fun isMacOS(): Boolean = System.getProperty("os.name").lowercase().contains("mac")
}
