# Fleet registration

Data only: agents, and the clusters added to each agent. Read by the plain
ApplicationSets in `../bootstrap/`.

```
fleet-registration/
  hga-hub-agent/                   PE admin agent (installed on Day 0 by tofu,
                                   so no agent.yaml)
    cluster-members/
      <cluster>.yaml               <cluster> added with cluster-admin
                                   (bootstrap/fleet-members.yaml)
  <agent>/                         a workload agent; the folder is its immutable
                                   name and its namespace on the hub
    agent.yaml                     the agent itself (bootstrap/fleet-agents.yaml)
    cluster-members/
      <cluster>.yaml               <cluster> added with least privilege
                                   (bootstrap/fleet-registrations.yaml)
```

Every agent has the same shape. One rule: `<agent>/cluster-members/<cluster>.yaml`
adds `<cluster>` to `<agent>`, and the file name is the cluster. Whether that is admin or
restricted comes from the agent. The same cluster is usually in two agents:

| File | Cluster Secret | Rights on the cluster |
|---|---|---|
| `hga-hub-agent/cluster-members/spoke-1.yaml` | `hga-hub-agent/spoke-1` | cluster-admin (`argocd-manager`) |
| `bu1-dev/cluster-members/spoke-1.yaml` | `bu1-dev/spoke-1` | its teams' namespaces only |

A cluster gets its admin membership first: the admin agent creates every
workload agent's restricted identity on it.

## Admin member

`hga-hub-agent/cluster-members/spoke-1.yaml`. The cluster's `tofu`
(`workshop/2-clusters`, workspace `spoke-1`) writes its server, CA and admin
token to OpenBao on the hub; the file names that store entry, never relying on
the file name:

```yaml
remote:
  remoteKey: clusters/spoke-1
  labels:
    enable_external_secrets: "true"   # hub add-ons to install on this cluster
    enable_workload_edit: "true"      # ClusterRole workload-edit, for workload agents
```

Removing the file leaves the registration in place: offboarding a cluster is
deliberate (`create-update`, preserve).

## Workload agent

`bu1-dev/agent.yaml` runs agent `bu1-dev` on the hub (namespace
`bu1-dev`, Harness agent `bu1_dev`, org from `tenant`):

```yaml
tenant: bu1          # Harness organization identifier (^[a-z][a-z0-9]*$)
environment: dev     # optional
```

The agent is deployed once and maintained; its cluster members come and go
separately. Deleting `agent.yaml` never deregisters a live Harness agent
(`create-update`, preserve): offboarding an agent is deliberate.

## Workload cluster member

`<agent>/cluster-members/<cluster>.yaml` lets the agent deploy only into
its teams' namespaces (`tenants/<tenant>/teams/*/values.yaml`) on that cluster,
with no cluster-scoped resources.

The workshop shows the push to a spoke: `bu1-dev/cluster-members/spoke-1.yaml`
(next step: the admin agent creates a deployer ServiceAccount on spoke-1, and
its token is read back to the hub).

### Same cluster (reference, not used in the workshop)

An agent can also be given the hub it runs on, with
`bu1-dev/cluster-members/hub-cluster.yaml`:

```yaml
mode: local
tenant: bu1
```

The hub then needs ClusterRole `workload-edit` too: add
`enable_workload_edit: "true"` to `hubCluster.labels` in `hub/bootstrap.yaml`.
`mode: local` creates a deployer ServiceAccount and token in the agent's
namespace, the team namespaces, and RoleBindings there; ESO copies the token
into the restricted cluster Secret (server
`https://kubernetes.default.svc.cluster.local`, `namespaces: ...`,
`clusterResources: "false"`).

### Removing

Deleting a workload cluster member file removes the cluster from that agent:
its ExternalSecret owns the cluster Secret (`creationPolicy: Owner`).
`deletionPolicy: Retain` only keeps the Secret when the store loses the entry
(dev OpenBao restarting empty). Team `Namespace`s keep `Delete=false`, so
running workloads are never deleted.
