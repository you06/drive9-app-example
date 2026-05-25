pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Drive9AndroidExample"
include(":app")

val drive9Repo = System.getenv("DRIVE9_REPO")
    ?: file("../vendor/drive9").absolutePath
val drive9KotlinLib = file("$drive9Repo/clients/drive9-kotlin/lib")

check(drive9KotlinLib.exists()) {
    "Drive9 Kotlin SDK not found at $drive9KotlinLib. Run ../scripts/bootstrap-drive9-sdk.sh or set DRIVE9_REPO."
}

include(":drive9-kotlin")
project(":drive9-kotlin").projectDir = drive9KotlinLib
