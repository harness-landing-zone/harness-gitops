# Fleet Clusters

One YAML file per cluster registration: `clusters/<agent>/<cluster>.yaml`.

- **Parent folder (`<agent>`)** is the target Agent's namespace (e.g. `clusters/bu1-dev/` registers into the `bu1-dev` Org Agent; `clusters/hga-hub-agent/` registers into the PE Admin Hub Agent).
- **Filename (`<cluster>`)** is the Argo CD Cluster Secret name inside that agent's namespace. The same physical cluster can be registered into multiple agents by placing a file in each agent's folder.
- **Independent lifecycle:** `fleet/clusters.yaml` uses `applicationsSync: sync`, `preserveResourcesOnDeletion: false`, and `ExternalSecret.target.deletionPolicy: Delete`. Adding a file registers the cluster immediately; deleting a file removes the Argo CD Cluster Secret (while local team workload `Namespace`s keep `Delete=false` so running workloads are never deleted).

## `mode: local` (restricted target on the same cluster)

Used for least-privilege Org Agents running on the hub cluster (`createClusterRoles: false`, `cluster.inClusterEnabled: "false"`). Provisions a dedicated `<cluster>-delivery` ServiceAccount, team workload namespaces (`tenants/<tenant>/teams/*/values.yaml`) with PSA + least-privilege `RoleBinding`s, and a namespace-scoped ESO `SecretStore`/`ExternalSecret` building `Secret/<cluster>` (`server: https://kubernetes.default.svc.cluster.local`, `namespaces: ...`, `clusterResources: "false"`):

```yaml
# clusters/bu1-dev/bu1-workloads.yaml
mode: local
tenant: bu1
environment: dev
```

## `mode: remote` (external cluster via ESO)

Registers an external cluster into `hga-hub-agent` (for hub-managed add-ons) or into an Org Agent (so one Org Agent can deploy to multiple remote clusters). Expects `server`, `caData`, and `token` at `remote.remoteKey` (defaults to `clusters/<cluster>`) in the configured `ClusterSecretStore`:

```yaml
# clusters/hga-hub-agent/spoke-eu-1.yaml
mode: remote
environment: dev
remote:
  secretStore: hub-secret-store
  remoteKey: clusters/spoke-eu-1
  labels:
    enable_external_secrets: "true"
```

```yaml
# clusters/bu1-dev/bu1-eks-dev.yaml
mode: remote
tenant: bu1
environment: dev
remote:
  secretStore: hub-secret-store
  remoteKey: clusters/bu1-eks-dev
  namespaces: "team-a-apps,team-b-apps"
  clusterResources: "false"
```
