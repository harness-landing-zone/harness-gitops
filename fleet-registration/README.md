# Fleet registration

Data only: every agent and cluster registration, one file each. The
plain ApplicationSets in `../bootstrap/` read it: `fleet-agents.yaml`,
`fleet-members.yaml`, `fleet-registrations.yaml`.

```
fleet-registration/
  <cluster>.yaml             fleet member: <cluster> registered with the hub's
                             PE admin agent (hga-hub-agent), with its admin token
  <agent>/                   an agent on the hub; the folder is its immutable
                             name and its namespace
    agent.yaml               the agent itself
    clusters/
      <cluster>.yaml         <cluster> registered into <agent>; the file name is
                             the Argo CD cluster Secret name there
```

The same cluster can be registered with the admin agent and into several
agents: one file each, each with its own token.

## Fleet member (admin registration)

`spoke-1.yaml`. The cluster's `tofu` (`workshop/2-clusters`,
workspace `spoke-1`) writes its server, CA and admin token to OpenBao on the
hub; the file names that store entry, never relying on the file name:

```yaml
remote:
  remoteKey: clusters/spoke-1
  labels:
    enable_external_secrets: "true"   # hub add-ons to install on this cluster
```

Removing a member file leaves the registration in place: offboarding a cluster
is deliberate (`create-update`, preserve).

## Agent

`bu1-dev/agent.yaml` runs agent `bu1-dev` on this hub (namespace
`bu1-dev`, Harness agent `bu1_dev`, org from `tenant`):

```yaml
tenant: bu1          # Harness organization identifier (^[a-z][a-z0-9]*$)
environment: dev     # optional
```

The agent is deployed once and maintained; its clusters come and go
separately. Deleting `agent.yaml` never deregisters a live Harness agent
(`create-update`, preserve): offboarding an agent is deliberate.

## Agent registration

`bu1-dev/clusters/bu1-workloads.yaml`: lets agent `bu1-dev` deploy to
the hub itself, with least privilege.

```yaml
mode: local
tenant: bu1
environment: dev
```

`mode: local` creates a delivery ServiceAccount and token in the agent's
namespace, the team namespaces from `tenants/<tenant>/teams/*/values.yaml`, and
RoleBindings there to ClusterRole `gitops-delivery`; ESO builds the restricted
cluster Secret (`namespaces: ...`, `clusterResources: "false"`). Registering a
spoke into an agent with a delivery identity on the spoke is the next step.

Deleting an agent registration file deregisters the cluster from that agent:
its ExternalSecret owns the cluster Secret (`creationPolicy: Owner`).
`deletionPolicy: Retain` only keeps the Secret when the store loses the entry
(dev OpenBao restarting empty). Team `Namespace`s keep `Delete=false`, so
running workloads are never deleted.
