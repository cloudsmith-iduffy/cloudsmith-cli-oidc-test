// Gradle has no init scripts for one build, so this build applies the Cloudsmith plugin itself.
// This is the block that `cloudsmith credential-helper install gradle --local` prints.
pluginManagement {
    repositories {
        maven { url = uri("https://dl.cloudsmith.io/public/cloudsmith/maven-tools/maven/") }
        gradlePluginPortal()
    }
}

plugins {
    id("io.cloudsmith.gradle-plugin") version "0.1.0"
}

val workspace = providers.environmentVariable("CLOUDSMITH_ORG").get()
val repository = providers.environmentVariable("CLOUDSMITH_REPO").get()

dependencyResolutionManagement {
    repositories {
        maven { url = uri("https://dl.cloudsmith.io/basic/$workspace/$repository/maven/") }
        mavenCentral()
    }
}

rootProject.name = "maven-tools-gradle-local"
