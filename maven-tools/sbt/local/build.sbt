val workspace = sys.env("CLOUDSMITH_ORG")
val repository = sys.env("CLOUDSMITH_REPO")

organization := "io.cloudsmith.example"
name := "maven-tools-sbt-local"
version := sys.env("EXAMPLE_VERSION")
// A Java-only build, so the artifact name has no Scala version.
autoScalaLibrary := false
crossPaths := false

// No credentials here or in ~/.sbt: the Cloudsmith plugin gets them from the CLI.
resolvers += "cloudsmith" at s"https://dl.cloudsmith.io/basic/$workspace/$repository/maven/"
// The publish target needs a name that no resolver has: sbt looks it up by name.
publishTo := Some("cloudsmith-publish" at s"https://maven.cloudsmith.io/$workspace/$repository/")

libraryDependencies += "io.cloudsmith.maven.example" % "cloudsmith-maven-cli" % "1.0.1090591"
