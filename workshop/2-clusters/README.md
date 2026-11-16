# 2. Clusters

Local k3d clusters, one OpenTofu workspace each: the workspace name is the
cluster name, and `cluster-values/<name>.yaml` says what it is (`role: hub` or
`role: spoke`). OpenTofu runs `k3d.sh` for the cluster work and makes the
Harness side.

- **hub**: k3d cluster `hga-hub` and the Harness delegate (its token comes from
  `../1-harness-setup`).
- **spoke-&lt;name&gt;**: k3d cluster `hga-spoke-<name>`, its connection in OpenBao
  on the hub (`clusters/<name>`), and its own Harness API key, scoped to its
  business unit's org, in OpenBao at its `harnessSecretName` (default
  `harness-api-keys/<name>`; `tofu output harness_secret_name` shows it). The
  member file `fleet-members/<name>.yaml` names the same path, and the hub
  pushes the key to the spoke.

## What you need first

- `../1-harness-setup` applied.
- The same Harness credentials in the environment as there
  (`HARNESS_ACCOUNT_ID`, `HARNESS_PLATFORM_API_KEY`).
- docker, k3d, kubectl, helm and jq.

## Up

```bash
tofu init
tofu workspace select -or-create hub && tofu apply
```

Then run pipeline `hga_hub_bootstrap` with input set `hga_hub_bootstrap_test`.
The hub's Argo CD then installs OpenBao (`bootstrap/hub-openbao.yaml`), which
the spokes write into, so wait for pod `openbao-0` before adding a spoke.

For each spoke, add `cluster-values/<spoke>.yaml` (see `spoke-test.yaml`), then:

```bash
tofu workspace select -or-create <spoke> && tofu apply
```

Registering the spoke in GitOps is a commit: add `fleet-members/<spoke>.yaml`
and push.

## Down

Every spoke workspace first, then the hub:

```bash
tofu workspace select <spoke> && tofu destroy
tofu workspace select hub && tofu destroy
```

## After a hub restart

The dev-mode OpenBao forgets everything. Write it again:

```bash
./k3d.sh register
tofu workspace select <spoke> && tofu apply -replace='terraform_data.spoke_key[0]'   # per spoke
```

## State holds secrets

Each spoke's API key is in its workspace state (`terraform.tfstate.d/`), which
git ignores. Never commit it.
