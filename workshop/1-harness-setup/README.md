# 1. Harness setup

Start with the [workshop guide](../README.md) for prerequisites and commands.
This stage creates the Harness resources for the hub and the example tenant.
Stage 2 creates the local hub and installs the controller and hub agent using
this stage's outputs.

## What it creates

| Scope | Entity | Identifier |
|---|---|---|
| Account | Workshop organization | `gitops_reference` |
| Workshop organization | Workshop project | `gitops_admin` |
| Account | Custom role (GitOps agent + Argo project view/edit/delete only) | `hga_controller` |
| Account | Service account, API key, token, role assignment on `_all_resources_including_child_scopes` | `hga_controller` |
| Account | Example tenant organization | `bu1` |
| Tenant | Team projects | `team_a`, `team_b` |
| Tenant | Controller role, service account, API key, token and role assignment | `hga_controller_bu1` (role, service account, API key and token) |

The tenant resources are defined in [`business-units.tf`](business-units.tf).
Stage 2 binds each spoke's own service account to the tenant role
`hga_controller_<bu>` by name.

## Outputs for stage 2

| Output | Used for |
|---|---|
| `controller_token` (sensitive) | Secret `harness-api-key-secret` in `hga-system` |
| `tenant_controller_tokens` (sensitive) | Secret `harness-api-key-<bu>` in `hga-system`, one per tenant |
| `environment_id` | The hub agent's name `hga-<env>-hub` and identifier `hga_<env>_hub` |
| `org_id`, `project_id` | The project the hub's AppProject `default` maps to |
| `repo_url` | `https://github.com/<github_org>/harness-gitops.git`, the repository the hub's Argo CD follows |

The Harness provider reads `HARNESS_ACCOUNT_ID` and
`HARNESS_PLATFORM_API_KEY` from the environment. Set `account_id` in
`terraform.tfvars` to the same account as `HARNESS_ACCOUNT_ID`. Stage 2
expects the default workspace's local state at `terraform.tfstate` in this
directory.

## State holds secrets

The service-account tokens are stored in state. Keep state and plans private.
Git ignores local state and `terraform.tfvars`.

## Already created by hand?

If a workshop entity already exists in your test account, use the state that
created it or verify it belongs to this workshop before importing it. For
example, the workshop project imports by organization and ID.

```bash
tofu import harness_platform_project.this gitops_reference/gitops_admin
```
