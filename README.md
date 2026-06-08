# cloudsmith-cli OIDC smoke test

Throwaway repo to validate the GitHub Actions OIDC detector added in
[`cloudsmith-io/cloudsmith-cli@iduffy/github-actions`](https://github.com/cloudsmith-io/cloudsmith-cli/tree/iduffy/github-actions)
before merge/release.

The [`oidc-smoke-test`](.github/workflows/oidc-smoke-test.yml) workflow installs the CLI
from the feature branch and exercises OIDC auto-discovery against:

- Org: `iduffy-demo`
- Service slug: `github-09kg`

Trigger it manually from the **Actions** tab (`workflow_dispatch`) or by pushing to `main`.

## What success looks like

- **Phase 1** (`whoami --debug`): logs `Detected OIDC environment: GitHub Actions`
  and never logs "Failed to retrieve identity token" — proves detection + the runtime
  HTTP token fetch work.
- **Phase 2** (`whoami --verbose`): prints `Authentication Method: OIDC Auto-Discovery`
  with `Source: OIDC via GitHub Actions (org: iduffy-demo, ...)`, and `list repos`
  succeeds — proves the full token exchange round-trip.

## Prerequisite

The `github-09kg` service account in `iduffy-demo` must have an OIDC provider trusting
GitHub's issuer (`https://token.actions.githubusercontent.com`) with claims scoped to
this repo and audience `cloudsmith`.
