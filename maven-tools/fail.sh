#!/usr/bin/env bash
# Breaks one thing that the Cloudsmith Maven tools need, runs the real command, and checks that it
# fails cleanly: the expected exit status, a message that names the cause, and no traceback.
# Usage: fail.sh maven|gradle|sbt <scenario>
#
# Scenarios that break the build (the extension or plugin must warn, and the build must fail):
#   cli-missing          The cloudsmith CLI is not on PATH.
#   cli-unauthenticated  The CLI has no credential. This workflow has no OIDC token.
#   cli-invalid-certs    The CLI does not trust the certificate of Cloudsmith.
#   cli-timeout          The CLI does not answer in time.
# Scenarios that break `cloudsmith credential-helper install`:
#   install-invalid-certs  The CLI does not trust the certificate of Cloudsmith.
#   tool-missing           The build tool is not installed. Install uses the default location.
#   tool-broken            The build tool fails. Install uses the default location and warns.
#   relative-location      The build tool reports a relative location. Install stops.
set -euo pipefail

usage="Usage: fail.sh maven|gradle|sbt <scenario>"
tool="${1:?${usage}}"
scenario="${2:?${usage}}"
: "${CLOUDSMITH_ORG:?Set CLOUDSMITH_ORG to your Cloudsmith workspace.}"
: "${CLOUDSMITH_REPO:?Set CLOUDSMITH_REPO to a private Cloudsmith repository.}"
# Each build fails before it publishes, but the Gradle and sbt examples need a version.
export EXAMPLE_VERSION=0.0.0-failure

case "${tool}" in
  maven)
    executable=mvn
    build=(mvn -B package)
    relative_option=MAVEN_OPTS=-Dmaven.repo.local=relative-m2
    default_location="${HOME}/.m2/repository/io/cloudsmith"
    ;;
  gradle)
    executable=gradle
    build=(gradle --no-daemon build)
    relative_option=GRADLE_OPTS=-Dgradle.user.home=relative-gradle
    default_location="${GRADLE_USER_HOME:-${HOME}/.gradle}/init.d/cloudsmith.init.gradle.kts"
    ;;
  sbt)
    executable=sbt
    build=(sbt -batch -no-colors update)
    relative_option=SBT_OPTS=-Dsbt.global.base=relative-sbt
    default_location="${HOME}/.sbt/1.0/plugins/cloudsmith.sbt"
    ;;
  *)
    echo "${usage}"
    exit 2
    ;;
esac

cd "$(dirname "$0")/${tool}"
log="$(pwd)/failure.log"
scratch="$(mktemp -d)"

# Runs the command, writes its output to the log, and fails unless the exit status is as expected.
# expect_status 0|fail <command...>
expect_status() {
  local expected="$1"
  shift
  local status=0
  "$@" > "${log}" 2>&1 || status=$?
  if [ "${expected}" = 0 ] && [ "${status}" != 0 ]; then
    cat "${log}"
    echo "FAIL: '$*' exited with status ${status}, not 0."
    exit 1
  fi
  if [ "${expected}" = fail ] && [ "${status}" = 0 ]; then
    cat "${log}"
    echo "FAIL: '$*' succeeded, but it must fail."
    exit 1
  fi
  if grep -q "Traceback (most recent call last)" "${log}"; then
    cat "${log}"
    echo "FAIL: the CLI printed a Python traceback."
    exit 1
  fi
}

expect_text() {
  if ! grep -qF -- "$1" "${log}"; then
    tail -n 100 "${log}"
    echo "FAIL: the output does not contain: $1"
    exit 1
  fi
  echo "Found: $1"
}

expect_no_text() {
  if grep -qF -- "$1" "${log}"; then
    cat "${log}"
    echo "FAIL: the output contains: $1"
    exit 1
  fi
}

# Prints PATH without the directories that have an executable with the name.
path_without() {
  local name="$1" directory kept=""
  local IFS=:
  for directory in ${PATH}; do
    [ -x "${directory}/${name}" ] || kept="${kept:+${kept}:}${directory}"
  done
  echo "${kept}"
}

# A CA that did not sign the certificate of Cloudsmith, as a TLS-intercepting proxy would present.
wrong_ca() {
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=Not the Cloudsmith CA" \
    -keyout "${scratch}/wrong-ca.key" -out "${scratch}/wrong-ca.pem" 2> /dev/null
  echo "${scratch}/wrong-ca.pem"
}

install_cli_setup() {
  cloudsmith --version
  cloudsmith credential-helper install "${tool}"
}

case "${scenario}" in
  cli-missing)
    install_cli_setup
    expect_status fail env PATH="$(path_without cloudsmith)" "${build[@]}"
    expect_text "The cloudsmith CLI is not on PATH, so no repository gets the CLI credential."
    ;;
  cli-unauthenticated)
    install_cli_setup
    expect_status fail "${build[@]}"
    expect_text "exited with status 1, so no repository gets the CLI credential."
    expect_text "Authentication credentials were not provided."
    ;;
  cli-invalid-certs)
    install_cli_setup
    expect_status fail env REQUESTS_CA_BUNDLE="$(wrong_ca)" "${build[@]}"
    expect_text "so no repository gets the CLI credential."
    expect_text "The TLS certificate is not from a trusted CA"
    ;;
  cli-timeout)
    install_cli_setup
    expect_status fail env CLOUDSMITH_MAVEN_TOOLS_TIMEOUT=0.001 "${build[@]}"
    expect_text "did not finish in 0.001 seconds, so no repository gets the CLI credential."
    ;;
  install-invalid-certs)
    expect_status fail env REQUESTS_CA_BUNDLE="$(wrong_ca)" \
      cloudsmith credential-helper install "${tool}" --dry-run
    expect_text "Hint: The TLS certificate is not from a trusted CA"
    ;;
  tool-missing)
    # Only the directory of the CLI stays on PATH, so the CLI cannot find the build tool.
    expect_status 0 env PATH="$(dirname "$(command -v cloudsmith)")" \
      cloudsmith credential-helper install "${tool}" --dry-run
    expect_text "${default_location}"
    expect_no_text "WARNING"
    ;;
  tool-broken)
    mkdir "${scratch}/bin"
    printf '#!/bin/sh\necho "%s: broken" >&2\nexit 1\n' "${executable}" > "${scratch}/bin/${executable}"
    chmod +x "${scratch}/bin/${executable}"
    expect_status 0 env PATH="${scratch}/bin:${PATH}" \
      cloudsmith credential-helper install "${tool}" --dry-run
    expect_text "WARNING: ${executable} did not report its"
    expect_text "${default_location}"
    ;;
  relative-location)
    expect_status fail env "${relative_option}" \
      cloudsmith credential-helper install "${tool}" --dry-run
    expect_text "is a relative path, so each build looks for the"
    ;;
  *)
    echo "${usage}"
    exit 2
    ;;
esac

echo "PASS: ${tool} ${scenario} failed cleanly."
