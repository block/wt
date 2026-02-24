package com.block.wt.util

import java.nio.file.Path

fun Path.normalizeSafe(): Path = try {
    toRealPath()
} catch (_: Exception) {
    toAbsolutePath().normalize()
}

fun Path.relativizeAgainst(base: Path?): String =
    if (base != null && startsWith(base)) base.relativize(this).toString() else toString()
