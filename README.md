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

## GitHub Actions

The GitHub Actions workflows use
[`cloudsmith-io/cloudsmith-cli-action@v3`](https://github.com/cloudsmith-io/cloudsmith-cli-action)
to sign in through OIDC as the `github-c3xe` service in `iduffy-demo`. No workflow has a secret.

Prerequisite: the `github-c3xe` service trusts GitHub's issuer
(`https://token.actions.githubusercontent.com`) for this repository, and can read and write the
`default` repository.

### cli-action-v3

[`.github/workflows/cli-action-v3.yml`](.github/workflows/cli-action-v3.yml) tests the moving `v3`
tag of the action on Linux, macOS, and Windows. Each job checks that the action installs the CLI
version that it reports, and that `whoami` and `list repos` work as the `github-c3xe` service. The
workflow does not use `--debug`, because the CLI then prints the exchanged Cloudsmith token, and
the build log is public.

### maven-tools

[`.github/workflows/maven-tools.yml`](.github/workflows/maven-tools.yml) tests the
[Cloudsmith Maven tools](https://cloudsmith.io/~cloudsmith/repos/maven-tools/packages/) from end to
end. Each job starts with `cloudsmith credential-helper install`, downloads a package from the
private `default` repository, publishes a new version of the example to that repository, and ends
with `cloudsmith credential-helper uninstall`. The Maven extension and the Gradle and sbt plugins
get the credential from `cloudsmith credential-helper generic`, so no build file or settings file
has a credential.

The released CLI does not have `credential-helper install maven` yet. Until it does, `mise run cli`
installs the CLI from
[cloudsmith-io/cloudsmith-cli#520](https://github.com/cloudsmith-io/cloudsmith-cli/pull/520), and
the action supplies only the OIDC settings.

[mise](https://mise.jdx.dev/) installs Java, Maven, Gradle, sbt, and uv from
[`mise.toml`](mise.toml). There is one example project for each tool in
[`maven-tools/`](maven-tools). Each `mise run` task is a job in the workflow:

| Task | Command | Changes |
| -- | -- | -- |
| `example:maven-global` | `install maven` | `~/.m2/extensions.xml` (Maven 3.10) |
| `example:maven-mavenrc` | `install maven --mavenrc` | `~/.mavenrc` (Maven 3.9) |
| `example:maven-local` | `install maven --local` | `.mvn/extensions.xml` of the project (Maven 3.9) |
| `example:gradle-global` | `install gradle` | `~/.gradle/init.d/cloudsmith.init.gradle.kts` |
| `example:sbt-global` | `install sbt` | `~/.sbt/1.0/plugins/cloudsmith.sbt` |
| `example:sbt-local` | `install sbt --local` | `project/cloudsmith.sbt` of the project |

Each task runs [`maven-tools/run.sh`](maven-tools/run.sh). The script checks that the build log
shows `Using the cloudsmith CLI credential for` both the download URL and the upload URL. The job
fails if one of these lines is missing, or if a `cloudsmith` command fails.

To run an example on your machine, sign in to the CLI, set the repository, and run the task:

```sh
mise run cli
export CLOUDSMITH_ORG=iduffy-demo CLOUDSMITH_REPO=default
mise run example:maven-local
```

The script removes the setup when the example passes. If it fails, run
`cloudsmith credential-helper uninstall maven`, `gradle`, or `sbt` to undo the changes in `~/.m2`,
`~/.mavenrc`, `~/.gradle`, or `~/.sbt`. The uninstall also removes a setup that you made before
you ran the example.

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

[`azure-pipelines.yml`](azure-pipelines.yml) is the end-to-end test of
[cloudsmith-io/cloudsmith-cli#425](https://github.com/cloudsmith-io/cloudsmith-cli/pull/425). It
checks that an OIDC run never prompts for a keyring password. It compares the released CLI with a
pinned commit, against org `iduffy-demo` / service slug `azure-devops-0v19`. Run it from the
`cloudsmith-oidc-test` Azure DevOps project with `az pipelines run --id 3 --branch main`. The
pipeline runs on the self-hosted `Default` pool.

Prerequisite — the `azure-devops-0v19` service in `iduffy-demo` must trust:

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
