# 1. Harness setup

One `tofu apply` creates everything Harness needs before the hub can be
bootstrapped. Nothing here touches a cluster.

## What it creates

| Scope | Entity | Identifier |
|---|---|---|
| Account | Organization / project | `gitops_reference` / `gitops_admin` |
| Account | Custom role (GitOps agent + Argo project view/edit/delete only) | `hga_controller` |
| Account | Service account, API key, token, role assignment on `_all_resources_including_child_scopes` | `hga_controller` |
| Project | Secret text: the controller's token | `HGA-Token` |
| Project | Secret text: GitHub App JSON for the controller | `hga_github_app` |
| Project | Secret file: GitHub App key for the connector | `hga_github_app_key` |
| Project | GitHub connector (GitHub App, API access on) | `hga_github` |
| Project | Delegate token | `hga_test_hub` |
| Project | Kubernetes connector (inherits from delegate `hga-test-hub`) | `hga_test_hub` |
| Project | Environment, 2 infrastructures, 2 services, pipeline, read from `../../../harness/` | `test`, `hga_system`, `account_agent`, `hga_controller`, `hga_account_agent`, `hga_hub_bootstrap` |

The environment, infrastructures, services and pipeline are read from the
repo's `harness/` YAML at plan time, so edit the YAML, not this folder.

## What you need first

- A Harness account and a personal access token that may create orgs, roles
  and service accounts:

  ```bash
  export HARNESS_ACCOUNT_ID=<account id>
  export HARNESS_PLATFORM_API_KEY=<pat>
  ```

- The GitHub App installed on the repo's GitHub org, with its private key PEM
  on disk. The Harness connector wants the key in PKCS#8; if yours starts with
  `BEGIN RSA PRIVATE KEY`, convert a copy and set
  `github_app_private_key_pkcs8_file` to it:

  ```bash
  openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in app.pem -out app.pkcs8.pem
  ```

## Run

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in the placeholders
tofu init
tofu plan
tofu apply
```

## Next

1. Install the delegate in the hub cluster: `tofu output -raw delegate_install_command`
   prints the `helm upgrade -i` command; it reads the token with
   `tofu output -raw delegate_token`, so run it from this folder.
2. When the delegate is connected, run the `hga_hub_bootstrap` pipeline.

## State holds secrets

The service-account token, the delegate token and the GitHub App private key
end up in Terraform state in plain text. Keep the state private (never commit
it; use an encrypted, access-controlled backend for anything shared). `.gitignore`
here keeps local state and `terraform.tfvars` out of git.

## Already created by hand?

Terraform fails on entities that already exist. Import them, or delete them in
Harness first. A project-scoped entity imports as `<org_id>/<project_id>/<id>`:

```bash
tofu import harness_platform_connector_kubernetes.hub gitops_reference/gitops_admin/hga_test_hub
```
