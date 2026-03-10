package com.block.wt.util

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.util.UUID

object PathHelper {

    private val HOME: Path = Path.of(System.getProperty("user.home"))

    fun expandTilde(path: String): Path {
        return if (path.startsWith("~/") || path == "~") {
            HOME.resolve(path.removePrefix("~/").removePrefix("~"))
        } else {
            Path.of(path)
        }
    }

    fun normalize(path: Path): Path {
        return path.toRealPath()
    }

    fun normalizeSafe(path: Path): Path {
        return try {
            path.toRealPath()
        } catch (_: Exception) {
            path.toAbsolutePath().normalize()
        }
    }

    fun atomicSetSymlink(linkPath: Path, newTarget: Path) {
        val parent = linkPath.parent
            ?: throw IllegalArgumentException("Link path must have a parent directory: $linkPath")
        Files.createDirectories(parent)

        val tempLink = parent.resolve(".${linkPath.fileName}.${UUID.randomUUID()}.tmp")
        Files.createSymbolicLink(tempLink, newTarget)
        try {
            Files.move(tempLink, linkPath, StandardCopyOption.ATOMIC_MOVE)
        } catch (e: Exception) {
            runCatching { Files.deleteIfExists(tempLink) }
            throw e
        }
    }

    fun isSymlink(path: Path): Boolean = Files.isSymbolicLink(path)

    fun readSymlink(path: Path): Path? {
        return if (Files.isSymbolicLink(path)) Files.readSymbolicLink(path) else null
    }

    val wtRoot: Path get() = HOME.resolve(".wt")

    val reposDir: Path get() = wtRoot.resolve("repos")

    val currentFile: Path get() = wtRoot.resolve("current")
}
