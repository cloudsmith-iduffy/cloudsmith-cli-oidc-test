# cloudsmith-cli OIDC smoke tests

Throwaway repo to validate the cloudsmith-cli OIDC detectors before merge/release.

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
