# cloudsmith-cli OIDC smoke tests

Throwaway repo to validate the cloudsmith-cli OIDC detectors before merge/release.

## Buildkite

[`.buildkite/pipeline.yml`](.buildkite/pipeline.yml) exercises automatic Buildkite OIDC
detection using the public Linux x86_64 GNU standalone CLI built from
`cloudsmith-io/cloudsmith-cli@ff2c7ceabcb6126643fc6c0e1b92b620eee0be1b`. The pipeline
downloads version `1.26.0-dev.13.gff2c7ce` and verifies its pinned SHA256 before extracting
or running it.

Configure these values in the Buildkite pipeline environment; do not commit their values:

- `CLOUDSMITH_WORKSPACE`
- `CLOUDSMITH_SERVICE_SLUG`

`CLOUDSMITH_API_KEY` must not be configured. The test runs the standalone binary's version
command followed by `cloudsmith --debug whoami --verbose`, captures the debug output to avoid
printing credentials, isolates the CLI from persisted local credentials, and passes only when
the Buildkite detector activates and `whoami` returns the configured service slug.

The Cloudsmith service must trust issuer `https://agent.buildkite.com`, audience
`cloudsmith`, and the stable Buildkite claims `organization_slug=ian-duffy` and
`pipeline_slug=cloudsmith-oidc-test`.

If the Buildkite pipeline is not already repository-backed, set its uploaded steps to:

```yaml
steps:
  - label: ":pipeline: Pipeline upload"
    command: buildkite-agent pipeline upload
```

Trigger a build with Buildkite's
[`Create a build`](https://buildkite.com/docs/apis/rest-api/builds#create-a-build) API:

```bash
curl --fail-with-body --request POST \
  --header "Authorization: Bearer $BUILDKITE_API_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{\"commit\":\"$GIT_COMMIT\",\"branch\":\"$GIT_BRANCH\",\"message\":\"Buildkite OIDC smoke test\"}" \
  https://api.buildkite.com/v2/organizations/ian-duffy/pipelines/cloudsmith-oidc-test/builds
```

Success is `PASS: Cloudsmith authenticated through Buildkite OIDC`; a missing Buildkite
token, rejected OIDC exchange, anonymous response, or fallback authentication fails the job.

## GitHub Actions — Cloudsmith Maven tools

[`.github/workflows/maven-tools.yml`](.github/workflows/maven-tools.yml) tests the Cloudsmith
Maven tools with the CLI from
[`iduffy/credential-helper-jvm`](https://github.com/cloudsmith-io/cloudsmith-cli/pull/520).
The Maven extension and the Gradle and sbt plugins get their credential from the generic
credential helper, `cloudsmith credential-helper generic`. In CI, the CLI gets that credential
through GitHub OIDC, so no build file, settings file, or secret has a credential.

[mise](https://mise.jdx.dev/) installs Java, Maven, Gradle, sbt, and uv from
[`mise.toml`](mise.toml). Each example in [`maven-tools/`](maven-tools) is a `mise run` task
and a job in the workflow:

| Task | Set up with | Scope |
| -- | -- | -- |
| `example:maven-global` | `install maven`, which writes `~/.m2/extensions.xml` (Maven 3.10) | Every Maven build |
| `example:maven-mavenrc` | `install maven --mavenrc`, which adds a block to `~/.mavenrc` (Maven 3.9) | Every Maven build |
| `example:maven-local` | `install maven --local`, which writes `.mvn/extensions.xml` (Maven 3.9) | One project |
| `example:gradle-global` | `install gradle`, which writes `~/.gradle/init.d/cloudsmith.init.gradle.kts` | Every Gradle build |
| `example:gradle-local` | The `plugins` block in `settings.gradle.kts`, which `install gradle --local` prints | One build |
| `example:sbt-global` | `install sbt`, which writes `~/.sbt/1.0/plugins/cloudsmith.sbt` | Every sbt build |
| `example:sbt-local` | `install sbt --local`, which writes `project/cloudsmith.sbt` | One build |

Each task runs [`maven-tools/run.sh`](maven-tools/run.sh). The script sets up the tool, downloads
`io.cloudsmith.maven.example:cloudsmith-maven-cli` from the `default` repository, and publishes
the example with a new version. Then it checks that the build log shows
`Using the cloudsmith CLI credential for` both the download URL and the upload URL. The job
fails if one of these lines is missing.

To run an example on your machine, set the repository and run the task:

```sh
mise run cli
export CLOUDSMITH_ORG=iduffy-demo CLOUDSMITH_REPO=default
mise run example:maven-local
```

The global examples change `~/.m2`, `~/.mavenrc`, `~/.gradle`, or `~/.sbt` on your machine. To
undo them, run `cloudsmith credential-helper uninstall maven`, `gradle`, or `sbt`.

Prerequisite: the `github-c3xe` service in `iduffy-demo` trusts GitHub's issuer with audience
`cloudsmith`, and can read and write the `default` repository.

## GitHub Actions

[`.github/workflows/oidc-smoke-test.yml`](.github/workflows/oidc-smoke-test.yml) installs
the latest release of the CLI from PyPI and exercises OIDC auto-discovery against org `iduffy-demo` / service slug `github-c3xe`.
Trigger it from the **Actions** tab (`workflow_dispatch`) or by pushing to `main`.

Success: Phase 1 (`whoami --verbose`) reports the `github-c3xe` service as the user, and Phase 2
(`list repos`) succeeds. The workflow does not use `--debug`, because the CLI then prints the
exchanged Cloudsmith token in the request headers, and the build log is public.

Prerequisite: the `github-c3xe` service in `iduffy-demo` trusts GitHub's issuer
(`https://token.actions.githubusercontent.com`) with audience `cloudsmith`.

## Google Cloud Build

[`cloudbuild.yaml`](cloudbuild.yaml) installs the CLI (with the `[gcp]` extra) from
[`iduffy/gcp-oidc`](https://github.com/cloudsmith-io/cloudsmith-cli/tree/iduffy/gcp-oidc)
and exercises OIDC auto-discovery against org `iduffy-demo` / service slug `google-10rf`.
Run it with `gcloud builds submit --config cloudbuild.yaml --no-source`. On Cloud Build the
detector resolves the ambient identity from the metadata server and mints a Google ID token
(`iss: https://accounts.google.com`, `aud: cloudsmith`).

The first step prints the decoded `iss`/`sub`/`aud`/`email` claims (never the raw JWT) so the
runtime service account's `sub` can be bound in Cloudsmith.

Success: Phase 1 prints the OIDC claims; Phase 2 (`whoami --verbose`) reports
`Source: OIDC via Google Cloud` and `list repos` succeeds.

Prerequisites:

- The build's runtime service account needs `roles/iam.serviceAccountTokenCreator`
  **on itself** — Cloud Build's metadata server has no ID-token endpoint, so the CLI
  mints the token via the IAM Credentials API (`generateIdToken`) instead.
- The `google-10rf` service in `iduffy-demo` must trust:
  - **Issuer:** `https://accounts.google.com`
  - **Audience:** `cloudsmith`
  - **Subject:** the Cloud Build runtime service account's numeric unique id (the `sub`
    printed by the first build step)

## Azure DevOps

[`azure-pipelines.yml`](azure-pipelines.yml) installs the CLI from
[`iduffy/azure-devops`](https://github.com/cloudsmith-io/cloudsmith-cli/tree/iduffy/azure-devops)
and exercises OIDC auto-discovery against org `iduffy-demo` / service slug `azure-devops-gqgp`.
Run it from the `cloudsmith-oidc-test` Azure DevOps project (this repo must be connected
as the pipeline source). The pipeline runs on the self-hosted `Default` pool and maps
`System.AccessToken` and `System.OidcRequestUri` into the step environment so the detector
can read them.

Success: Phase 1 authenticates as `User: azure-devops (slug: azure-devops-gqgp)`; Phase 2
reports `Source: OIDC ... azure-devops-gqgp` and `list repos` returns repositories.

Prerequisite — the `azure-devops-gqgp` service in `iduffy-demo` must trust:

- **Issuer:** `https://vstoken.dev.azure.com/<accountId>`
- **Audience:** `api://AzureADTokenExchange` (Azure DevOps ignores any requested audience)
- **Subject:** `p://<org>/<project>/<pipeline>`, e.g. `p://iduffy-demo/cloudsmith-oidc-test/cloudsmith-cli-oidc-test`

### Self-hosted agent (required for Azure DevOps)

This account has no hosted parallelism, so the pipeline runs on the self-hosted
`Default` pool. Bring an agent up locally with Docker Compose
([`docker-compose.yml`](docker-compose.yml), agent image in [`azp-agent/`](azp-agent)):

```bash
cp .env.example .env          # put an Azure DevOps PAT (Agent Pools: Read & manage) in .env
docker compose up -d --build  # registers a `compose-local-agent` in the Default pool
# ... run the pipeline ...
docker compose down           # deregisters and removes the agent
```

The PAT is read from `.env` (gitignored) — it is never stored in the compose file.
A new pipeline also needs one-time authorization to use the `Default` pool (the
"This pipeline needs permission to access a resource" prompt, or via the REST API
`pipelinePermissions/queue/<queueId>`).
