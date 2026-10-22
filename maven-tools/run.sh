#!/usr/bin/env bash
# Sets up the Cloudsmith Maven tools for the example in the current directory, builds and
# publishes the example, and checks that the build used the CLI credential for both the download
# URL and the upload URL.
# Usage: run.sh maven|gradle|sbt global|local|mavenrc
set -euo pipefail

tool="${1:?Usage: run.sh maven|gradle|sbt global|local|mavenrc}"
scope="${2:?Usage: run.sh maven|gradle|sbt global|local|mavenrc}"
: "${CLOUDSMITH_ORG:?Set CLOUDSMITH_ORG to your Cloudsmith workspace.}"
: "${CLOUDSMITH_REPO:?Set CLOUDSMITH_REPO to a Cloudsmith repository that you can write to.}"
# Cloudsmith rejects a release version that it already has, so each run publishes a new one.
export EXAMPLE_VERSION="${EXAMPLE_VERSION:-0.1.$(date +%s)}"

# Gradle has no init scripts for one build: the local example applies the plugin in
# settings.gradle.kts instead.
if [ "${tool}/${scope}" != "gradle/local" ]; then
  case "${scope}" in
    global) cloudsmith credential-helper install "${tool}" ;;
    *) cloudsmith credential-helper install "${tool}" "--${scope}" ;;
  esac
fi

case "${tool}" in
  maven)
    mvn -B -q versions:set -DnewVersion="${EXAMPLE_VERSION}" -DgenerateBackupPoms=false
    build=(mvn -B -X deploy)
    ;;
  gradle) build=(gradle --info --no-daemon publish) ;;
  sbt) build=(sbt -batch -debug publish) ;;
esac

if ! "${build[@]}" > build.log 2>&1; then
  tail -n 100 build.log
  echo "FAIL: ${build[*]} failed. The full log is in $(pwd)/build.log."
  exit 1
fi

for url in \
  "https://dl.cloudsmith.io/basic/${CLOUDSMITH_ORG}/${CLOUDSMITH_REPO}/maven/" \
  "https://maven.cloudsmith.io/${CLOUDSMITH_ORG}/${CLOUDSMITH_REPO}/"; do
  if ! grep -qF "Using the cloudsmith CLI credential for ${url}" build.log; then
    echo "FAIL: the build did not use the CLI credential for ${url}."
    exit 1
  fi
  echo "Used the CLI credential for ${url}"
done
echo "PASS: ${tool} ${scope} downloaded from and published ${EXAMPLE_VERSION} to Cloudsmith."
