package com.block.wt.testutil

import java.nio.file.Files
import java.nio.file.Path

object TestFileHelper {

    fun deleteRecursive(path: Path) {
        if (Files.isDirectory(path) && !Files.isSymbolicLink(path)) {
            Files.list(path).use { stream ->
                stream.forEach { deleteRecursive(it) }
            }
        }
        Files.deleteIfExists(path)
    }
}
