# Harness GitOps Agents reference architecture

A reference architecture for running Harness GitOps Agents on many clusters
with the official HGA controller (`harness/gitops-agent-bootstrap-controller`),
modelled on EKS Fleet Management.

One account-level agent on a **hub** cluster deploys an agent onto every
**spoke** cluster, from files in this repo. Adding a cluster is one member
file. Adding a team is one team file.

**[docs/architecture.md](docs/architecture.md) is the full description**: who
holds what, every step from an empty machine, what has run and what has not,
and the open questions. This README is the short version.

## Status

Everything here has run only on local k3d clusters. Today that is one hub and
one spoke, `spoke-test`. Two models exist for a spoke's agent:

| Model | Member file | Where the controller and the Harness API key are | State |
|---|---|---|---|
| Self-managed | `agentModel: ""` | On the hub and on every spoke. Each spoke has its own key, which the hub pushes to it. | Running on `spoke-test` |
| Hub-managed | `agentModel: hub` | On the hub only. External Secrets pushes the agent's own token to the spoke. | No fleet member uses it. It ran on one spoke that has been removed. |

Hub-managed is the intended one: Harness API access belongs to the hub, and
a spoke only does GitOps.

```mermaid
flowchart LR
  git["This repo"] --> hubargo
  subgraph hub["Hub cluster"]
    ctrl["Controller + API keys<br/>hga-system"]
    hubargo["Hub agent + Argo CD<br/>hga-hub-agent"]
    eso["External Secrets + OpenBao<br/>cluster connections, spoke keys"]
  end
  subgraph spoke["Spoke cluster"]
    sctrl["Controller + API key<br/>self-managed only"]
    rt["Argo CD + agent<br/>namespace = cluster name"]
    teams["Team namespaces<br/>and AppProjects"]
  end
  eso -- "cluster Secret<br/>with labels" --> hubargo
  eso -- "pushes the key<br/>self-managed only" --> sctrl
  hubargo -- "installs" --> sctrl
  hubargo -- "installs" --> rt
  hubargo -- "installs" --> teams
  ctrl -. "registers hub agent" .-> harness["Harness"]
  sctrl -. "registers spoke agent" .-> harness
  rt -. "connects with its own token" .-> harness
```

## Layout

```
bootstrap/          applied by the hub's root Application: ESO, OpenBao,
                    cluster registration, agent registration (hub-managed), spokes
spoke-bootstrap/    ApplicationSets that install on spokes: controller
                    (self-managed only), runtime, teams
fleet-members/      one file per spoke: tenant, stage, gitopsAgent, agentModel,
                    harnessSecretName
decommissioned/     member files of removed spokes; nothing reads it
tenants/<tenant>/gitops-agents/
  defaults/         values for every spoke of the tenant
  defaults/teams/   one file per team, for every spoke of the tenant
  <stage>/          values, and optionally teams, for one stage
charts/             the official controller chart, gitops-agent (wraps the
                    official gitops-helm), cluster-registration,
                    fleet-member-registration, teams-bootstrap
hub/                values for the Day 0 pipeline
addons/hub/         values for the hub's add-ons (OpenBao)
workshop/1-harness-setup/   OpenTofu for every Harness entity, and the pipeline
workshop/2-clusters/        OpenTofu and k3d.sh for the local test clusters
docs/               the architecture document, an older page on people and
                    ownership, diagrams
```

Only files under `hub/` may use Harness expressions. Everything else is
rendered by Argo CD, which cannot resolve them.

## From zero to a hub

1. Create the Harness entities: `tofu apply` in
   [workshop/1-harness-setup/](workshop/1-harness-setup/README.md). It needs a
   Harness account, a personal access token and a GitHub App installed on
   this repo.
2. Have a cluster for the hub with a Harness delegate in it. For a local k3d
   hub, the `hub` workspace of
   [workshop/2-clusters/](workshop/2-clusters/README.md) creates both.
3. Push this repo to `main`. The pipeline fetches charts and values from there.
4. Run pipeline `hga_hub_bootstrap` with input set `hga_hub_bootstrap_test`.
   It installs the controller into `hga-system`, then the hub agent with its
   Argo CD into `hga-hub-agent`.
5. The hub's Argo CD then applies `bootstrap/` by itself: External Secrets
   Operator, OpenBao with its store, and the ApplicationSets that register
   and bootstrap spokes.

Check:

```bash
kubectl -n hga-hub-agent get applications,applicationsets
```

The hub agent shows CONNECTED and HEALTHY in Harness.

## Add a cluster with an agent

Self-managed:

1. Write two entries into the store: the cluster's connection at
   `clusters/<cluster>` (keys `server`, `caData`, `token`) and the spoke's own
   Harness API key at `harness-api-keys/<cluster>` (property `api_key`). For a
   local k3d spoke, [workshop/2-clusters/](workshop/2-clusters/README.md)
   creates the cluster and the key and writes both entries.
2. Commit `fleet-members/<cluster>.yaml`:

   ```yaml
   tenant: bu1        # the Harness org
   stage: test        # which values and teams it gets
   gitopsAgent: true  # install an agent
   agentModel: ""     # "" = self-managed, hub = hub-managed
   harnessSecretName: harness-api-keys/<cluster>   # the key the hub pushes
   ```

External Secrets builds the Argo CD cluster Secret from the store and the
file. Its labels make three Applications for the spoke: `<cluster>-controller`,
`<cluster>-runtime` and `<cluster>-teams`. External Secrets pushes the key to
the spoke, the spoke's controller registers the agent under the tenant's org,
and the agent connects. Every Application of a cluster carries the label
`cluster`, so the filter `cluster:<name>` in the Harness GitOps list shows
them together.

Without `harnessSecretName`, create Secret `harness-api-key-secret` in
namespace `hga-system` on the spoke by hand.

With `agentModel: hub`, leave `harnessSecretName` out: no key and no
controller go to the spoke. See the architecture document for what that model
installs where, and for what is not proven.

## Add a team

1. Create the team's Harness project in the tenant's org (OpenTofu,
   `workshop/1-harness-setup/business-units.tf`).
2. Commit `tenants/<tenant>/gitops-agents/defaults/teams/<team>/values.yaml`
   with the project id, the source repos, the namespaces and the destinations.
   `tenants/bu1/gitops-agents/defaults/teams/team-a/values.yaml` is an example.

Every spoke of that tenant gets the team's namespaces, its AppProject and its
mapping to the Harness project. A team file under `<stage>/teams/` reaches
only the spokes of that stage. Namespaces must start with `<team>-`.

## Things that bite

- A spoke's name is its member file name. It becomes the namespace, the agent
  name and the Harness identifier, and can never change. Neither can its
  tenant.
- Nothing is deleted automatically. Removing a member file or a team file
  leaves everything in place. Offboarding is manual.
- Move a removed spoke's member file to `decommissioned/`. A subfolder of
  `fleet-members/` is still read.
- Never delete the ExternalSecret of a live spoke: it owns the cluster Secret,
  and with it the hub's access to the spoke.
- No old `<cluster>-agent-token` Secret may exist where a controller is about
  to register an agent. The controller never overwrites one.
- OpenBao runs in dev mode and is empty after every restart. Write the cluster
  connections and the keys again; `workshop/2-clusters/README.md` has the two
  commands.
- An ApplicationSet that matches nothing still reports success. Check
  `kubectl get applications`.
- Harness expressions in comments under `hub/` are evaluated. Never write
  expression syntax in a comment there.
- The hub holds cluster-admin on every spoke.
- This repo's own charts and values follow `HEAD` of `main`; nothing is pinned
  per stage. Only the two upstream charts are pinned (ESO `2.15.0`, OpenBao
  `0.30.7`).

## Not included yet

- Hub-managed on a current fleet member, and moving a spoke to it.
- A persistent secret store.
- Staged upgrades across stages.
- Offboarding a team, a spoke or a tenant.
- Team repositories feeding Applications, and Harness roles for team users.
- Anything outside local k3d clusters.
