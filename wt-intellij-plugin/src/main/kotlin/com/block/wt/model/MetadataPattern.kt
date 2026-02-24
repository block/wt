package com.block.wt.model

data class MetadataPattern(
    val name: String,
    val description: String,
) {
    companion object {
        val KNOWN_PATTERNS: List<MetadataPattern> = listOf(
            MetadataPattern(".idea", "IntelliJ IDEA project settings"),
            MetadataPattern(".ijwb", "IntelliJ with Bazel plugin settings"),
            MetadataPattern(".aswb", "Android Studio with Bazel plugin settings"),
            MetadataPattern(".clwb", "CLion with Bazel plugin settings"),
            MetadataPattern(".bazelproject", "Bazel project view file"),
            MetadataPattern(".xcodeproj", "Xcode project"),
            MetadataPattern(".xcworkspace", "Xcode workspace"),
            MetadataPattern(".swiftpm", "Swift Package Manager settings"),
            MetadataPattern(".vscode", "VS Code settings"),
            MetadataPattern(".bsp", "Build Server Protocol settings"),
            MetadataPattern(".metals", "Metals (Scala) settings"),
            MetadataPattern(".eclipse", "Eclipse project settings"),
            MetadataPattern(".classpath", "Eclipse classpath file"),
            MetadataPattern(".project", "Eclipse project file"),
            MetadataPattern(".settings", "Eclipse workspace settings"),
        )

        val BAZEL_IDE_PATTERNS: Set<String> = setOf(".ijwb", ".aswb", ".clwb")
    }
}
