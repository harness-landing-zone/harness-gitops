# 2. Clusters

Start with the [workshop guide](../README.md) for setup and verification.
This stage provisions local k3d clusters. Each OpenTofu workspace uses the
configuration in `cluster-values/<workspace>.yaml`.

- The `hub` workspace creates k3d cluster `hga-hub` (context
  `k3d-hga-hub`). It installs the delegate using the token and name from the
  default workspace's local state in `../1-harness-setup/terraform.tfstate`.
  The Harness setup variable `hub_delegate_name` defaults to `hga-test-hub`.
- Each spoke workspace creates a k3d cluster and a tenant-scoped Harness API
  key. For `spoke-test`, the cluster is `hga-spoke-test` (context
  `k3d-hga-spoke-test`) and its connection details go to
  `clusters/spoke-test` in the hub's OpenBao. The key goes to
  `harness-api-keys/spoke-test` by default. The member file's
  `harnessSecretName` must match the key path used by the workspace.

Use the same `HARNESS_ACCOUNT_ID` and `HARNESS_PLATFORM_API_KEY` as Stage 1.
For an existing workshop hub using the Helm release `local-hub-delegate`,
set `hub_delegate_name = "local-hub-delegate"` in the Stage 1
`terraform.tfvars` and reapply Stage 1 first. Stage 2 will reuse that release.
Create the hub and run its bootstrap pipeline before applying any spoke
workspace. A spoke needs OpenBao running on the hub to store its connection
and API key. The grouped branch already contains the `spoke-test` member file.

## Destroy the local infrastructure

Complete remote offboarding while the controllers and their credentials are
still available. Confirm the workshop agent registrations and their project
mappings have been cleaned up in Harness. From `workshop/2-clusters`, review
and destroy each workshop spoke workspace. For the default workshop spoke,
run the following.

```bash
tofu workspace select spoke-test && tofu destroy
```

Once all workshop spoke destroys have succeeded, review and destroy the hub
workspace.

```bash
tofu workspace select hub && tofu destroy
```

## After a hub restart

OpenBao runs in dev mode and loses its entries on restart. In
`workshop/2-clusters`, restore every local spoke connection and then restore
each key from its workspace. For the default workshop spoke, run the following
after the OpenBao pod is Ready.

```bash
kubectl --context k3d-hga-hub -n openbao wait --for=condition=Ready pod/openbao-0 --timeout=120s
./k3d.sh register
tofu workspace select spoke-test && tofu apply -replace='terraform_data.spoke_key[0]'
```

## State holds secrets

Each spoke's API key is in its workspace state (`terraform.tfstate.d/`), which
git ignores. Never commit it.
