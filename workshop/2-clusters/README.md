# 2. Clusters

Start with the [workshop guide](../README.md) for setup and verification.
This stage provisions local k3d clusters. Each OpenTofu workspace uses the
configuration in `cluster-values/<workspace>.yaml`.

- The `hub` workspace creates k3d cluster `hga-hub` (context `k3d-hga-hub`)
  and installs two Helm releases from this checkout
  ([`hub.tf`](hub.tf)): `hga-controller` (`charts/harness-gitops-agent-controller`,
  values `hub/controller.yaml`) in `hga-system`, then `hga-hub-agent`
  (`charts/gitops-agent`, values `hub/account-agent.yaml`) in
  `hga-hub-agent`. The per-hub inputs and keys come from the default
  workspace's local state in `../1-harness-setup/terraform.tfstate`; the keys
  are passed only as sensitive Helm values. `revision` in
  `cluster-values/hub.yaml` (default `main`) is the branch the hub's Argo CD
  follows.
- Each spoke workspace creates a k3d cluster and a tenant-scoped Harness API
  key. For `spoke-test`, the cluster is `hga-spoke-test` (context
  `k3d-hga-spoke-test`) and its connection details go to
  `clusters/spoke-test` in the hub's OpenBao. The key goes to
  `harness-api-keys/spoke-test` by default. The member file's
  `harnessSecretName` must match the key path used by the workspace.

Use the same `HARNESS_ACCOUNT_ID` and `HARNESS_PLATFORM_API_KEY` as Stage 1.
Create the hub before applying any spoke workspace. A spoke needs OpenBao
running on the hub to store its connection and API key. The repository
already contains the `spoke-test` member file.

## Destroy the local infrastructure

Follow the [workshop teardown](../README.md#5-tear-down-the-workshop) to
remove the GitOps mappings and agents in Harness before destroying the spoke
and hub workspaces.

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

The hub workspace's state holds the controller and tenant keys (as Helm
values), and each spoke's API key is in its workspace state
(`terraform.tfstate.d/`), which git ignores. Never commit it.
