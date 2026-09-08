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

## GitHub Actions — Maven shell-plugin (download + native upload)

[`.github/workflows/maven-oidc.yml`](.github/workflows/maven-oidc.yml) installs the CLI from
[`maven-shell-plugin`](https://github.com/cloudsmith-io/cloudsmith-cli/tree/maven-shell-plugin)
and proves the Maven shell-plugin credential helper end-to-end with **GitHub OIDC only** (no
API key anywhere). Against org `iduffy-demo` / repo `default` / service slug `github-c3xe`, it:

1. `cloudsmith credential-helper install maven --org iduffy-demo --repo default` and puts the
   shim dir on `PATH` (the CI equivalent of `eval "$(cloudsmith credential-helper shell-init)"`),
2. runs a plain `mvn clean deploy` in [`maven-example/`](maven-example) — the shadowed `mvn`
   transparently **downloads** `io.cloudsmith.maven.example:cloudsmith-maven-cli:1.0.1090591`
   from the download CDN and **uploads** the freshly built jar to the native Maven endpoint
   (`https://maven.cloudsmith.io/iduffy-demo/default/`), authenticated via an ephemeral
   settings.xml minted from the OIDC token.

Prerequisite: the `github-c3xe` service in `iduffy-demo` trusts GitHub's issuer
(`https://token.actions.githubusercontent.com`) with audience `cloudsmith`, and can read/write
the `default` repo.

## GitHub Actions

[`.github/workflows/oidc-smoke-test.yml`](.github/workflows/oidc-smoke-test.yml) installs
the CLI from [`iduffy/github-actions`](https://github.com/cloudsmith-io/cloudsmith-cli/tree/iduffy/github-actions)
and exercises OIDC auto-discovery against org `iduffy-demo` / service slug `github-09kg`.
Trigger it from the **Actions** tab (`workflow_dispatch`) or by pushing to `main`.

Success: Phase 1 (`whoami --debug`) logs `Detected OIDC environment: GitHub Actions` with
no "Failed to retrieve identity token"; Phase 2 (`whoami --verbose`) reports
`Source: OIDC via GitHub Actions` and `list repos` succeeds.

Prerequisite: the `github-09kg` service in `iduffy-demo` trusts GitHub's issuer
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
