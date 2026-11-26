# Fleet Members

Every `*.yaml` file in this directory registers one fleet member with `fleet/members.yaml`. The filename (without `.yaml`) is the member's immutable identity.

Set `type` to declare what PE Admin Argo CD deploys for the member:

## 1. `type: agent` — Local lower-privilege Org GitOps Agent

Deploys an ORG-scoped GitOps Agent + Argo CD into `namespace` on the hub cluster using official upstream `harness/gitops-helm` (`createClusterRoles: false`, `argo-cd.crds.install: false`, `cluster.inClusterEnabled: "false"`) plus `charts/fleet-member` (`mode: agent`):

```yaml
# fleet-members/bu1-dev.yaml
type: agent
tenant: bu1
environment: dev
namespace: org-bu1
clusterSecretName: bu1-workloads  # optional; defaults to <filename>-workloads
```

## 2. `type: cluster` — Remote cluster registration via ESO

Creates an `ExternalSecret` in `hga-hub-agent` that reads `server`, `caData`, and `token` from `remoteCluster.secretStore` and builds a labelled Argo CD cluster Secret (`fleet_member: cluster`, `type: cluster`, `tenant`, `environment`, plus any `remoteCluster.labels` such as `enable_external_secrets: "true"`):

```yaml
# fleet-members/spoke-dev.yaml
type: cluster
tenant: bu1
environment: dev
remoteCluster:
  secretStore: hub-secret-store   # ClusterSecretStore name (e.g. Vault / AWS Secrets Manager / OpenBao)
  remoteKey: clusters/spoke-dev   # optional; defaults to clusters/<filename>
  labels:
    enable_external_secrets: "true"
```
