# Architecture: what is built, how it runs, what is not proven

This document describes the grouped bootstrap on this branch. Its [live]
marks refer to workshop runs of the earlier layout on `main`.
Use the [workshop guide](../workshop/README.md) to run the grouped bootstrap
on local k3d clusters.

It is written for a reader with no context, and for reviewers looking for
gaps. Every statement about the build carries one of four marks:

| Mark | Meaning |
|---|---|
| **[live]** | Run on the earlier local k3d setup with hub `hga-hub` and spoke `spoke-test`. A statement about an earlier spoke says so. |
| **[built]** | In the repository, with live validation pending. The grouped bootstrap has been rendered locally with Helm. |
| **[decided]** | Decided, not built. |
| **[theory]** | Reasoning only. |

## Design intent

One account-level agent on a **hub** cluster deploys an agent onto every
**spoke** cluster. Everything that talks to the Harness API with an API key
(registering agents, mapping projects) should belong to the hub. A spoke
should only do GitOps: run Argo CD and its agent, and hold nothing but that
agent's own token.

Two models exist. In the **self-managed** model the spoke runs its own
controller and holds a Harness API key, so it does not meet the intent. The
one fleet member runs it. In the **hub-managed** model, the default, the key
and the agent objects stay on the hub, which meets the intent. No fleet member uses it
today. Both are described below.

## Names

| Name | Meaning |
|---|---|
| Hub | The cluster that runs the hub agent, the controller, External Secrets Operator (ESO) and the secret store. |
| Hub agent | The Harness GitOps agent on the hub, with its Argo CD. Account scope. It applies everything in this repo. |
| Spoke | A workload cluster with its own Argo CD and agent. |
| Fleet member, member file | A cluster is a fleet member because `fleet-members/<cluster>.yaml` exists. The file name is the cluster's name. |
| Tenant | Who owns a spoke. One Harness org. A business unit can be a tenant; `bu1` is the example. |
| Stage | A spoke's level, for example `test`, `nonprod` or `prod`. Chooses which values and which teams a spoke gets. |
| Environment | The Harness Environment the hub was bootstrapped with (`test`). The word is not used for spokes. |
| Team | One Harness project in the tenant's org, one Argo CD AppProject on the spoke. |
| Controller | The Harness GitOps Agent controller (`charts/harness-gitops-agent-controller`). It registers agents and project mappings in Harness, using an API key. |
| Agent object | A `HarnessGitopsAgent` resource. The controller registers it and writes the agent's token Secret beside it. |
| Mapping | A `HarnessGitopsProjectMapping` resource: one AppProject mapped to one Harness project. |
| Cluster Secret | An Argo CD cluster Secret on the hub. Its labels decide what gets installed on that cluster. |
| Store | OpenBao on the hub, read by ESO through `ClusterSecretStore` `hub-openbao`. |
| Self-managed | Controller, API key and agent objects are on the spoke. Member file `controller: self`, cluster Secret label `controller: self`. |
| Hub-managed | API key and agent objects stay on the hub; only the hub's controller runs. Member file `controller: hub` (the default), cluster Secret label `controller: hub`. |

## Repository layout

```
groups/
  addons.yaml   ESO and OpenBao on the hub
  fleet.yaml    one Application per member file to register its cluster Secret
  agents.yaml   spoke controller, runtime and teams, plus hub-managed agent registration
fleet-members/<cluster>.yaml  one file per spoke: tenant, stage, model,
                              controller, harnessSecretName
decommissioned/     member files of removed spokes; nothing reads it
tenants/<tenant>/gitops-agents/
  defaults/values.yaml                values for every agent of the tenant
  defaults/teams/<team>/values.yaml   a team on every spoke of the tenant
  <stage>/values.yaml                 values for one stage (optional)
  <stage>/teams/<team>/values.yaml    a team on one stage only (optional)
charts/
  application-sets           renders ApplicationSets from one group file per release
  harness-gitops-agent-controller   the official controller chart, unchanged
  gitops-agent                wraps the official gitops-helm chart (Argo CD and agent)
  cluster-registration        the store, each spoke's Argo CD connection on the hub, and push setup
  agent-registration          the agent object, the locked default AppProject, and the token push
  teams-bootstrap             per team: namespaces, AppProject, mapping
hub/                static values for the hub's day-0 install: controller.yaml, account-agent.yaml
addons/defaults/openbao/values.yaml       values for OpenBao, the only add-on with a values file
workshop/README.md            local workshop and verification
workshop/1-harness-setup/     OpenTofu for the shared Harness entities
workshop/2-clusters/          OpenTofu and k3d.sh: the test clusters, the hub install,
                              and each spoke's connection and API key in the store
docs/               this document, an older page on people and ownership, diagrams
```

## Who holds what

| Thing | Self-managed (`controller: self`) [live] | Hub-managed (`controller: hub`) |
|---|---|---|
| Controller | Hub, and one on every spoke | Hub only |
| Account-level API key | Hub, namespace `hga-system` | Same |
| API key that registers the spoke's agent | The spoke's own key, scoped to the tenant's org. It is in the store at `harness-api-keys/<cluster>` and on the spoke as `harness-api-key-secret` in `hga-system`. The hub pushes it there when the member file sets `harnessSecretName`; without that setting a person creates the Secret. | The tenant's key, on the hub only (`harness-api-key-<tenant>` in `hga-system`) |
| Agent object | Spoke | Hub, in a namespace named after the spoke |
| Agent token | Written on the spoke by the spoke's controller | Written on the hub by the hub's controller, then copied to the spoke by ESO |
| Mappings | Spoke | Hub |
| Placeholder AppProjects | None | Hub: one deny-all AppProject per team (see caveat 2) |
| Argo CD and the agent pod | Spoke | Spoke |
| Team namespaces and real AppProjects | Spoke | Spoke |
| Spoke connection with cluster-admin | Hub: the cluster Secret and the store, plus a kubeconfig Secret for ESO when the key is pushed | Hub: the cluster Secret and the store, plus a kubeconfig Secret for ESO |

Caveats that apply to the design, not to a missing step:

1. **The hub holds cluster-admin on every spoke.** It needs it to install the
   agent there. Whoever controls the hub controls every spoke. This is true
   in both models. ESO holds the same credential whenever it pushes to a
   spoke: the agent token when hub-managed, the API key when self-managed.
2. **Hub-managed needs placeholder AppProjects.** The controller marks a
   mapping Ready only when an AppProject of that name exists beside the agent
   object. When hub-managed the real AppProject is on the spoke, so the hub
   carries an empty one of the same name. A Ready mapping on the hub then no
   longer proves that the real AppProject exists on the spoke. The controller
   does not document this check, so a controller change could break it.
3. **A team's fence on a spoke is Argo CD policy.** The spoke's Argo CD has
   cluster-wide rights. What keeps a team in its own namespaces is its
   AppProject.
4. **A hub-managed spoke cannot be registered while the hub is down.**
   Agents that are already running keep working in both models.

## Part 1. From zero to a hub that manages spokes

| # | Who | Does what | Where | Mark |
|---|---|---|---|---|
| 1 | A person | Uses a test Harness account and a personal access token. Forks the repository only to change groups or fleet members. | GitHub, Harness | [built] |
| 2 | A person, OpenTofu | `tofu apply` in `workshop/1-harness-setup/`. Creates the platform org and project and the account-level role, service account, API key and token for the controller. | Harness | [built]; the pipeline-era entities are still in the test account |
| 3 | Same apply | Per tenant (`business-units.tf`, only `bu1`): the org, one project per team (`team_a`, `team_b`), and an org-level role, service account, API key and token. | Harness | [live] |
| 4 | A person, OpenTofu | `tofu apply` in workspace `hub` of `workshop/2-clusters/`. Creates the k3d cluster `hga-hub`, then installs two Helm releases on it with values from `hub/` plus the per-hub inputs and keys read from step 2's state. | Laptop, hub | [built], not applied yet. The running hub was installed by the earlier pipeline. |
| 5 | Same apply | Sets the branch the hub follows from `revision` in `cluster-values/hub.yaml` (default `main`). | Laptop | [built] |
| 6 | Same apply, release `hga-controller` | Installs the controller and its CRDs into `hga-system` (`hub/controller.yaml`). | Hub | [built] |
| 7 | Same apply, release `hga-hub-agent` | Installs `charts/gitops-agent` into `hga-hub-agent` (`hub/account-agent.yaml`): Argo CD, the hub agent and its agent object, one mapping, the API key Secrets in `hga-system`, the cluster Secret `hub-cluster`, and the root ApplicationSet `groups`. | Hub | [built] |
| 8 | Controller | Registers the hub agent in Harness and writes its token. The agent connects. The apply waits for that. | Hub, Harness | [live] with the earlier install |
| 9 | Hub Argo CD | The root ApplicationSet `groups`, made by the hub release, reads `groups/*.yaml` from the hub's `revision` and creates three Applications: `addons`, `fleet` and `agents`. | Hub | [built] |
| 10 | Hub Argo CD | Each group Application renders `charts/application-sets` with its `groups/<group>.yaml` values from the same branch. The addons group installs ESO, OpenBao and its store. | Hub | [built] |
| 11 | Hub Argo CD | The fleet group's `registration` reads the member files. The agents group generates workload Applications for the resulting spoke cluster Secrets. | Hub | [built] |

The fleet group waits for member files and the corresponding OpenBao entries.

- **The cluster Secret `hub-cluster` carries the hub configuration.** Its
  annotations include the repo URL, Harness account id and `repo_revision`.
  The installer takes its branch from `repo_revision` and passes it to the
  chart for Git-based generators and sources. `cluster-registration` copies
  the repo URL and account id to each spoke Secret for per-spoke generators.
  [built]
- **The store is OpenBao in dev mode.** It keeps everything in memory, is
  opened with the chart's published dev token, and is empty after every
  restart. It holds cluster connections at `clusters/<cluster>` (keys
  `server`, `caData`, `token`) and each self-managed spoke's API key at
  `harness-api-keys/<cluster>` (property `api_key`). Only ExternalSecrets in
  `hga-hub-agent` may read it. [live]
- **An empty hub, repeat run and migration from the earlier layout still need
  live validation.** The historical runs upgraded an earlier install. With
  pruning disabled, the old `hub-cluster-spokes` Application can remain and
  track the same spoke ApplicationSets as the new group Application. Start on
  an empty hub and follow the [workshop guide](../workshop/README.md).

## Part 2. Onboarding a cluster with an agent

### Self-managed [live]

| # | Who | Does what | Where |
|---|---|---|---|
| 1 | A person, OpenTofu | Only for a new tenant: its org, team projects, role and tenant key (`workshop/1-harness-setup/business-units.tf`). | Harness |
| 2 | A person, OpenTofu | Adds `workshop/2-clusters/cluster-values/<cluster>.yaml` (`role: spoke`, the tenant's org under the key `bu`, optionally `harnessSecretName`) and runs `tofu apply` in workspace `<cluster>`. The name must be `spoke-<name>`. That creates the k3d cluster `hga-<cluster>`, ServiceAccount `argocd-manager` with cluster-admin on it, and the spoke's own service account, API key and token in the tenant's org. It writes the connection into the store at `clusters/<cluster>` and the key at `harness-api-keys/<cluster>`. | Laptop, spoke, Harness, hub |
| 3 | A person | Commits `fleet-members/<cluster>.yaml` with `tenant`, `stage`, `model: agent`, `controller: self` and `harnessSecretName: harness-api-keys/<cluster>`. | Git |
| 4 | Hub Argo CD | `registration` makes Application `<cluster>-registration` in `hga-hub-agent`: an ExternalSecret for the cluster Secret and, because `harnessSecretName` is set, what pushes the key (a kubeconfig ExternalSecret, an ExternalSecret for the key, `ClusterSecretStore` `push-<cluster>-hga-system` and a `PushSecret`). | Hub |
| 5 | ESO | Builds the cluster Secret `<cluster>`: the connection from the store, labels `fleet_member: spoke`, `model`, `addons`, `controller`, `tenant`, `stage` from the member file, annotations copied from the hub. | Hub |
| 6 | Hub Argo CD | The labels make three Applications for the spoke: `<cluster>-controller`, `<cluster>-runtime`, `<cluster>-teams`. | Hub to spoke |
| 7 | Hub Argo CD | `<cluster>-controller` installs the controller and its CRDs into `hga-system`. | Spoke |
| 8 | ESO | Pushes the key to the spoke as `harness-api-key-secret` in `hga-system`. It retries until step 7 has created the namespace. | Hub to spoke |
| 9 | Hub Argo CD | `<cluster>-runtime`, into namespace `<cluster>`: Argo CD with its CRDs, then the agent object and a locked `default` AppProject, then the agent pod. | Spoke |
| 10 | Spoke's controller | Registers the agent in Harness under org `<tenant>` at ORG scope, and writes `<cluster>-agent-token`. The agent pod starts and connects. | Spoke, Harness |
| 11 | Hub Argo CD | `<cluster>-teams`: for each team file, the team's namespaces, its AppProject and its mapping. The controller marks the mapping Ready once the agent is healthy. | Spoke |

Every Application of a cluster is named `<cluster>-<thing>` and carries the
labels `cluster`, `tenant` and `stage`. In the Harness GitOps list a cluster's
Applications therefore sort together, and the label filter `cluster:<name>`
returns all of them. [live]

What is live and what is not:

- `spoke-test` (tenant `bu1`, stage `test`) is the only fleet member. Its
  four Applications and the hub's four are Synced and Healthy, its agent is
  healthy, and both team mappings are verified. [live]
- `spoke-test` was registered from nothing: ESO created its cluster Secret.
  Two earlier spokes, `spoke-nonprod` and `spoke-prod`, were registered as a
  **takeover** of a hand-made cluster Secret. They have been removed; their
  member files are in `decommissioned/`.
- No person creates the key Secret on `spoke-test`: ESO pushed it. [live]
  A member file without `harnessSecretName` still works if a person creates
  `harness-api-key-secret` on the spoke, which is how the two earlier spokes
  ran.
- Step 2 is specific to the k3d test setup. Who writes a real cluster's
  connection and key into the store is an open question.

### Hub-managed

The member file says `controller: hub`, or leaves `controller` out. That adds
the label `controller: hub` to the cluster Secret, and the ApplicationSets
branch on it.

No fleet member uses this model today. `spoke-prod` ran it on 2026-11-16
and has since been removed. What was checked on that run is not
recorded in this repository, so the steps below are described from the code.

| Step | What differs from self-managed |
|---|---|
| Step 2 | `workshop/2-clusters` still makes a key for the spoke and stores it. Nothing uses it. |
| Step 3 | The member file sets `controller: hub` and leaves `harnessSecretName` out. The chart refuses a file that has both. |
| Step 4 | `<cluster>-registration` renders, beside the cluster Secret's ExternalSecret, a second ExternalSecret `<cluster>-kubeconfig`, built from the same store entry, and a `ClusterSecretStore` `push-<cluster>` that lets ESO write into namespace `<cluster>` on the spoke. Only the hub namespace `<cluster>` may use that store. No key is pushed. |
| Steps 7 and 8 | Gone. No controller and no API key on the spoke. `controller` skips the cluster. |
| New, on the hub | `agent` makes Application `<cluster>-agent` in hub namespace `<cluster>`: the agent object (using `harness-api-key-<tenant>` from the hub's `hga-system`), a `PushSecret`, and per team a mapping with a placeholder AppProject. |
| Hub's controller | Registers the agent and writes `<cluster>-agent-token` on the hub. |
| ESO | The `PushSecret` copies that Secret to the same name and namespace on the spoke. |
| Step 9 | `<cluster>-runtime` installs Argo CD, the locked `default` AppProject and the agent pod, but no agent object. The pod starts once the pushed token arrives. |
| Step 11 | `<cluster>-teams` installs only namespaces and real AppProjects. The mappings are on the hub. |

The namespace has the same name on the hub and on the spoke, because the
controller registers the agent with its object's namespace.

Token delivery has one implementation: **push**, as above. **Pull** (the hub pushes the
token into the store and an ESO on the spoke reads it) is [theory]: it needs
ESO on every spoke, a store the spokes can reach, and a login per spoke.

### Moving a running spoke from self-managed to hub-managed [theory]

A takeover is not possible. The controller treats a Harness agent as its own
only if it created it, so the hub's controller cannot adopt an agent that a
spoke's controller registered. The move is: switch the agent off in the
member file, delete the agent object on the spoke so its controller
deregisters it, remove the controller, its CRDs and the key Secret from the
spoke, then remove `harnessSecretName` from the member file and set
`controller: hub`. The agent is registered again with a new token.
Applications that teams created on the old agent are not covered by this plan.

### Onboarding a team [live on `spoke-test`]

1. OpenTofu creates the team's Harness project in the tenant's org.
2. A person commits a team file with the project id, the source repos, the
   namespaces and the destinations:
   `tenants/<tenant>/gitops-agents/defaults/teams/<team>/values.yaml` for
   every spoke of the tenant, or
   `tenants/<tenant>/gitops-agents/<stage>/teams/<team>/values.yaml` for one
   stage.
3. `<cluster>-teams` applies it on every spoke it covers.

`bu1` has `team-a` and `team-b` under `defaults/teams/`. No stage has a teams
folder of its own, so that path is [built].

`charts/teams-bootstrap` refuses a team file whose namespaces or destinations
do not start with `<team>-`, whose source repos contain patterns, or whose
destination is another cluster. Every team AppProject forbids cluster-scoped
resources and every resource in the `gitops.harness.io` group.

## Rules that follow from the build

- **A spoke's identity is its member file name.** It becomes the cluster
  Secret, the namespace, the agent's name and (with `_` for `-`) its Harness
  identifier. It cannot be renamed, and its tenant cannot be changed. [live]
- **Nothing is deleted automatically.** No ApplicationSet prunes. Removing a
  member file or a team file leaves everything in place. Agent objects and
  mappings carry `Delete=false`, because deleting one deregisters it in
  Harness. Offboarding is manual. [live]
- **A removed spoke's member file goes to `decommissioned/`, not to a
  subfolder of `fleet-members/`.** The generator's pattern
  `fleet-members/*.yaml` also matched files in a subfolder. [live]
- **Never delete the ExternalSecret of a live spoke.** It owns the cluster
  Secret; deleting it removes the hub's access to the spoke. [built]
- **No old `<cluster>-agent-token` may exist** where a controller is about to
  register an agent. The controller never overwrites one. [live]
- **After a hub restart the store is empty.** `./k3d.sh register` in
  `workshop/2-clusters/` writes every spoke's connection again, and
  `tofu apply -replace='terraform_data.spoke_key[0]'` in each spoke's
  workspace writes its key again. Existing cluster Secrets stay in place
  meanwhile. [built]
- **The hub follows one branch for the group files, its own charts and their values.**
  It is `revision` in `cluster-values/hub.yaml`, default `main`. The two upstream chart versions are
  in `groups/addons.yaml`: ESO `2.15.0` and OpenBao `0.30.7`. [built]

## Part 3. Later [theory]

Kept simple on purpose. None of this is planned work yet.

- **Pull delivery of the agent token**, as described above.
- **A persistent store.** Replace dev-mode OpenBao with a store that survives
  restarts, and replace the dev token with Kubernetes auth for ESO.
- **Staged upgrades.** A pinned revision per stage, so one stage moves before
  the next.
- **Two agents in one cluster: one cluster-wide, one namespaced.** The
  namespaced one would run without ClusterRoles, without installing CRDs and
  without the built-in cluster destination, behind Roles limited to its own
  namespaces. What stands in the way: such an agent has never run; a cluster
  Secret describes exactly one agent today; the Argo CD CRDs can have only
  one owner per cluster; two Argo CDs on one cluster can claim each other's
  resources; and the cluster-wide one can still reach into the other's
  namespaces. Hub-managed makes this easier, because nothing of the
  controller remains on the spoke.

## Not proven yet

1. The hub-managed model on a current fleet member: the `PushSecret` through
   ESO's Kubernetes store, the agent pod starting on a pushed token without
   a manual restart, and mappings going Ready on the hub against placeholder
   AppProjects. It ran on one spoke that no longer exists, with no record
   here of what was checked.
2. Moving a running spoke from self-managed to hub-managed.
3. Grouped bootstrap on an empty hub, a repeat run and migration from the
   earlier layout.
4. The `hub` workspace of `workshop/2-clusters` (cluster and the two Helm releases).
5. Any upgrade of Argo CD, the agent or the controller on a spoke.
6. Offboarding a team or a tenant. Spokes have been removed by hand.
7. A second tenant (`tenants/bu2/` is empty), a second stage running beside
   `test`, and a teams folder for one stage.
8. A team deploying from its own repository. The only Application that has
   run is one example created by hand on an earlier spoke.
9. The store after a restart: that ESO keeps the cluster Secrets and the
   pushed keys, and recovers once the entries are written again.
10. Anything outside k3d: a real cloud cluster, a persistent store, a
    network where the hub cannot reach a spoke's API.

## Open questions

1. Which spoke runs hub-managed next? None does today.
2. Placeholder AppProjects: accept them, or change the controller so a
   mapping for an agent on another cluster needs none?
3. API keys: a self-managed spoke has its own key, hub-managed agents share
   the tenant's key. Should hub-managed also use one key per spoke?
4. Is cluster-admin for the hub on every spoke acceptable in the reference,
   or should the agent be installed when the cluster is created, so the hub
   needs less?
5. Who writes a new cluster's connection and key into the store in a real
   setup: the provisioning that creates the cluster?
6. Which store does the workshop use once dev-mode OpenBao is replaced?
7. Does the reference need staged upgrades (a pinned revision per stage)
   before it is published?
8. What may a team's users do in Harness? No Harness roles are designed for
   them.
9. Who raises changes to a tenant's files: the tenant by pull request, or
   only the platform team?
10. What is the offboarding sequence for a team, a spoke and a tenant?

## Inconsistencies in the repository at this commit

These are files that say or do something the build no longer matches.

- `workshop/1-harness-setup/k3d.sh` is an older copy of the cluster script.
  Its `register` reads an OpenTofu output `spoke_api_keys` that no file
  defines. `workshop/2-clusters/k3d.sh` is the one OpenTofu runs.
- `workshop/2-clusters/cluster-values/*.yaml` names the tenant `bu`; member
  files name it `tenant`.
- `tenants/bu1/gitops-agents/nonprod/values.yaml` applies to no fleet member:
  none has stage `nonprod`.
- The diagram of [People and ownership](people-and-ownership.md) shows the
  state of 2026-11-13.
