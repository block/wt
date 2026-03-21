package com.block.wt.model

data class MetadataPattern(
    val name: String,
    val description: String,
) {
    companion object {
        val KNOWN_PATTERNS: List<MetadataPattern> = listOf(
            MetadataPattern(".idea", "JetBrains IDE project settings"),
            MetadataPattern(".run", "JetBrains run/debug configurations"),
            MetadataPattern(".fleet", "JetBrains Fleet"),
            MetadataPattern(".ijwb", "IntelliJ Bazel plugin settings"),
            MetadataPattern(".aswb", "Android Studio with Bazel plugin settings"),
            MetadataPattern(".clwb", "CLion with Bazel plugin settings"),
            MetadataPattern(".bazelbsp", "JetBrains Bazel plugin (BSP-based)"),
            MetadataPattern(".bazelproject", "Bazel project view file"),
            MetadataPattern(".bsp", "Build Server Protocol settings"),
            MetadataPattern(".xcodeproj", "Xcode project"),
            MetadataPattern(".xcworkspace", "Xcode workspace"),
            MetadataPattern(".swiftpm", "Swift Package Manager settings"),
            MetadataPattern("xcuserdata", "Xcode user data"),
            MetadataPattern(".vscode", "VS Code settings"),
            MetadataPattern(".metals", "Metals (Scala) settings"),
            MetadataPattern(".bloop", "Bloop build server (Scala)"),
            MetadataPattern(".eclipse", "Eclipse project settings"),
            MetadataPattern(".settings", "Eclipse workspace settings"),
            MetadataPattern(".project", "Eclipse project file"),
            MetadataPattern(".classpath", "Eclipse classpath file"),
        )

        val BAZEL_IDE_PATTERNS: Set<String> = setOf(".ijwb", ".aswb", ".clwb")
    }
}
