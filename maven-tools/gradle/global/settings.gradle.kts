// `cloudsmith credential-helper install gradle` applies the Cloudsmith plugin to every build
// through an init script in ~/.gradle/init.d, so this file does not name the plugin.
val workspace = providers.environmentVariable("CLOUDSMITH_ORG").get()
val repository = providers.environmentVariable("CLOUDSMITH_REPO").get()

dependencyResolutionManagement {
    repositories {
        maven { url = uri("https://dl.cloudsmith.io/basic/$workspace/$repository/maven/") }
        mavenCentral()
    }
}

rootProject.name = "maven-tools-gradle-global"
