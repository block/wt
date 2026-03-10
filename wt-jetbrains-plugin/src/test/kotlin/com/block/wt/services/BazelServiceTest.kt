package com.block.wt.services

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class BazelServiceTest {

    private fun writeTempFile(content: String): java.nio.file.Path {
        val dir = Files.createTempDirectory("bazel-test")
        val file = dir.resolve(".bazelproject")
        Files.writeString(file, content)
        return file
    }

    @Test
    fun testParseDirectoriesSectionStandard() {
        val file = writeTempFile("""
            directories:
              src/main
              src/test
              lib/common
        """.trimIndent())
        val result = BazelService.parseDirectoriesSection(file)
        assertEquals(listOf("src/main", "src/test", "lib/common"), result)
    }

    @Test
    fun testParseDirectoriesSectionSkipsCommentsAndExclusions() {
        val file = writeTempFile("""
            directories:
              src/main
              # this is a comment
              -excluded/dir
              src/test
        """.trimIndent())
        val result = BazelService.parseDirectoriesSection(file)
        assertEquals(listOf("src/main", "src/test"), result)
    }

    @Test
    fun testParseDirectoriesSectionSkipsBlankLines() {
        val file = writeTempFile("""
            directories:
              src/main

              src/test
        """.trimIndent())
        val result = BazelService.parseDirectoriesSection(file)
        assertEquals(listOf("src/main", "src/test"), result)
    }

    @Test
    fun testParseDirectoriesSectionStopsAtNewSection() {
        val file = writeTempFile("""
            directories:
              src/main
              src/test
            targets:
              //src/main/...
        """.trimIndent())
        val result = BazelService.parseDirectoriesSection(file)
        assertEquals(listOf("src/main", "src/test"), result)
    }

    @Test
    fun testParseDirectoriesSectionNoSection() {
        val file = writeTempFile("""
            targets:
              //src/main/...
        """.trimIndent())
        val result = BazelService.parseDirectoriesSection(file)
        assertTrue(result.isEmpty())
    }

    @Test
    fun testParseDirectoriesSectionOnly() {
        val file = writeTempFile("""
            directories:
              src/main
        """.trimIndent())
        val result = BazelService.parseDirectoriesSection(file)
        assertEquals(listOf("src/main"), result)
    }
}
