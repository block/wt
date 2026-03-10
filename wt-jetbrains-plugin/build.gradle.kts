import org.jetbrains.intellij.platform.gradle.TestFrameworkType

plugins {
    id("org.jetbrains.kotlin.jvm") version "2.3.0"
    id("org.jetbrains.intellij.platform") version "2.11.0"
}

group = providers.gradleProperty("pluginGroup").get()
version = providers.gradleProperty("pluginVersion").get()

kotlin {
    jvmToolchain(25)
    compilerOptions {
        // JDK 25 toolchain for compilation, JVM 21 bytecode for IDE compatibility.
        // IntelliJ 2025.3 bundles JBR 21; bump to JVM_25 when targeting 2026.1+ (JBR 25).
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
    }
}

repositories {
    maven(url = "https://maven.global.square/artifactory/square-public")
    intellijPlatform {
        defaultRepositories()
    }
}

dependencies {
    intellijPlatform {
        intellijIdea(providers.gradleProperty("platformVersion"))

        bundledPlugin("Git4Idea")
        bundledPlugin("org.jetbrains.plugins.terminal")

        testFramework(TestFrameworkType.Platform)
    }

    testImplementation("junit:junit:4.13.2")
}

intellijPlatform {
    pluginConfiguration {
        name = providers.gradleProperty("pluginName")
        version = providers.gradleProperty("pluginVersion")

        ideaVersion {
            sinceBuild = providers.gradleProperty("pluginSinceBuild")
            untilBuild = providers.gradleProperty("pluginUntilBuild")
        }
    }

    pluginVerification {
        ides {
            recommended()
        }
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
}

tasks {
    runIde {
        jvmArgs("-Xmx2g")
        systemProperty("idea.is.internal", "true")
    }

    test {
        systemProperty("idea.home.path", layout.buildDirectory.dir("idea-sandbox").get().asFile.absolutePath)
    }
}
