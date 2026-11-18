# 1. Harness setup

Start with the [workshop guide](../README.md) for prerequisites and commands.
This stage creates the Harness resources for the hub and the example tenant.
Stage 2 creates the local hub and installs its delegate using this stage's
outputs.

## What it creates

| Scope | Entity | Identifier |
|---|---|---|
| Account | Workshop organization | `gitops_reference` |
| Workshop organization | Workshop project | `gitops_admin` |
| Account | Custom role (GitOps agent + Argo project view/edit/delete only) | `hga_controller` |
| Account | Service account, API key, token, role assignment on `_all_resources_including_child_scopes` | `hga_controller` |
| Project | Secret text: the controller's token | `HGA-Token` |
| Project | Secret text: GitHub App JSON for the controller | `hga_github_app` |
| Project | Secret file: GitHub App key for the connector | `hga_github_app_key` |
| Project | GitHub connector (GitHub App, API access on) | `hga_github` |
| Project | Delegate token | `hga_test_hub` |
| Project | Kubernetes connector (selects delegate `hga-test-hub` by default) | `hga_test_hub` |
| Project | Environment, two infrastructures, two services, pipeline and input set | `test`, `hga_system`, `account_agent`, `hga_controller`, `hga_account_agent`, `hga_hub_bootstrap`, `hga_hub_bootstrap_test` |
| Account | Example tenant organization | `bu1` |
| Tenant | Team projects | `team_a`, `team_b` |
| Tenant | Controller role, service account, API key, token and role assignment | `hga_controller_bu1` (role, service account, API key and token) |
| Project | Secret text for the tenant controller token | `hga_controller_bu1_token` |

The environment, infrastructures, services, pipeline and input set are read
from [`harness/`](harness/) at plan time. The tenant resources are defined in
[`business-units.tf`](business-units.tf).

The Harness provider reads `HARNESS_ACCOUNT_ID` and
`HARNESS_PLATFORM_API_KEY` from the environment. Set `account_id` in
`terraform.tfvars` to the same account as `HARNESS_ACCOUNT_ID`. Stage 2
expects the default workspace's local state at `terraform.tfstate` in this
directory.

## State holds secrets

The service-account tokens, delegate token and GitHub App private key are
stored in state. Keep state and plans private. Git ignores local state and
`terraform.tfvars`. Keep the PEM files outside the checkout.

## Already created by hand?

If a workshop entity already exists in your test account, use the state that
created it or verify it belongs to this workshop before importing it. For
example, the Kubernetes connector imports by organization, project and ID.

```bash
tofu import harness_platform_connector_kubernetes.hub gitops_reference/gitops_admin/hga_test_hub
```
