plugins {
    `java-library`
    `maven-publish`
}

val workspace = providers.environmentVariable("CLOUDSMITH_ORG").get()
val repository = providers.environmentVariable("CLOUDSMITH_REPO").get()

group = "io.cloudsmith.example"
version = providers.environmentVariable("EXAMPLE_VERSION").get()

dependencies {
    implementation("io.cloudsmith.maven.example:cloudsmith-maven-cli:1.0.1090591")
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            artifactId = "maven-tools-gradle-local"
            from(components["java"])
        }
    }
    // No credentials here or in gradle.properties: the Cloudsmith plugin gets them from the CLI.
    repositories {
        maven {
            name = "cloudsmith"
            url = uri("https://maven.cloudsmith.io/$workspace/$repository/")
        }
    }
}
