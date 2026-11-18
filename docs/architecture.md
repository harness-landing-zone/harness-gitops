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

The build does not meet that intent yet: each spoke runs its own controller
and holds a Harness API key, scoped to its tenant's org.

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

## Repository layout

```
bootstrap/groups.yaml   group installer ApplicationSet applied by the root Application
groups/
  addons.yaml   ESO and OpenBao on the hub
  fleet.yaml    one Application per member file to register its cluster Secret
  agents.yaml   spoke controller, runtime and teams
fleet-members/<cluster>.yaml  one file per spoke: tenant, stage, gitopsAgent,
                              harnessSecretName
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
  agent-registration          the agent object and the locked default AppProject
  teams-bootstrap             per team: namespaces, AppProject, mapping
hub/                values for the Day 0 pipeline: controller.yaml, account-agent.yaml
addons/hub/defaults/openbao/values.yaml   values for OpenBao, the hub's only add-on with a values file
workshop/README.md            local workshop and verification
workshop/1-harness-setup/     OpenTofu for shared Harness entities and the pipeline YAML
workshop/2-clusters/          OpenTofu and k3d.sh: the test clusters, the delegate,
                              and each spoke's connection and API key in the store
docs/               this document, an older page on people and ownership, diagrams
```

## Who holds what

| Thing | Where [live] |
|---|---|
| Controller | Hub, and one on every spoke |
| Account-level API key | Hub, namespace `hga-system` |
| API key that registers the spoke's agent | The spoke's own key, scoped to the tenant's org. It is in the store at `harness-api-keys/<cluster>` and on the spoke as `harness-api-key-secret` in `hga-system`. The hub pushes it there when the member file sets `harnessSecretName`; without that setting a person creates the Secret. |
| Agent object | Spoke |
| Agent token | Written on the spoke by the spoke's controller |
| Mappings | Spoke |
| Argo CD and the agent pod | Spoke |
| Team namespaces and AppProjects | Spoke |
| Spoke connection with cluster-admin | Hub: the cluster Secret and the store, plus a kubeconfig Secret for ESO when the key is pushed |

Caveats that apply to the design, not to a missing step:

1. **The hub holds cluster-admin on every spoke.** It needs it to install the
   agent there. Whoever controls the hub controls every spoke. ESO holds the
   same credential when it pushes the API key to a spoke.
2. **A team's fence on a spoke is Argo CD policy.** The spoke's Argo CD has
   cluster-wide rights. What keeps a team in its own namespaces is its
   AppProject.

## Part 1. From zero to a hub that manages spokes

| # | Who | Does what | Where | Mark |
|---|---|---|---|---|
| 1 | A person | Makes the grouped branch available in the GitHub repository, installs a GitHub App for that repo, and saves its private key. Uses a test Harness account and a personal access token. | GitHub, Harness | [built] for the grouped branch. The GitHub App was used in earlier runs. |
| 2 | A person, OpenTofu | `tofu apply` in `workshop/1-harness-setup/`. Creates the platform org and project, the account-level role, service account and API key for the controller, the Harness secrets, the GitHub and Kubernetes connectors, a delegate token, and the environment, infrastructures, services, pipeline and input set. | Harness | [live] |
| 3 | Same apply | Per tenant (`business-units.tf`, only `bu1`): the org, one project per team (`team_a`, `team_b`), and an org-level role, service account, API key and token. | Harness | [live] |
| 4 | A person, OpenTofu | `tofu apply` in workspace `hub` of `workshop/2-clusters/`. Creates the k3d cluster `hga-hub` and installs the Harness delegate using its name and token from the local state in step 2. | Laptop, hub | [built]. The earlier hub and its delegate were made by hand. |
| 5 | A person | Confirms that the hub delegate is connected, then runs `hga_hub_bootstrap` with the `hga_hub_bootstrap_test` input set. The input set fills `git_ref` with `main`. Select `workshop-appsets-groups` in the run dialog for the grouped test. | Harness | [built] |
| 6 | Pipeline `hga_hub_bootstrap`, stage 1 | Installs the controller and its CRDs into `hga-system` (`hub/controller.yaml`). | Hub | [live] |
| 7 | Pipeline, stage 2 | Installs `charts/gitops-agent` into `hga-hub-agent` (`hub/account-agent.yaml`): Argo CD, the hub agent and its agent object, one mapping, the API key Secrets in `hga-system`, the repo credential, the cluster Secret `hub-cluster`, and the root Application. | Hub | [live] |
| 8 | Controller | Registers the hub agent in Harness and writes its token. The agent connects. The pipeline's last step waits for that. | Hub, Harness | [live] |
| 9 | Hub Argo CD | The root Application `cluster-application-sets` applies `bootstrap/groups.yaml` from `git_ref`. The `groups` ApplicationSet creates three Applications: `hub-cluster-addons`, `hub-cluster-fleet` and `hub-cluster-agents`. | Hub | [built] |
| 10 | Hub Argo CD | Each group Application renders `charts/application-sets` with its `groups/<group>.yaml` values from the same branch. The addons group installs ESO, OpenBao and its store. | Hub | [built] |
| 11 | Hub Argo CD | The fleet group's `cluster-registration` reads the member files. The agents group generates workload Applications for the resulting spoke cluster Secrets. | Hub | [built] |

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
  `server`, `caData`, `token`) and each spoke's API key at
  `harness-api-keys/<cluster>` (property `api_key`). Only ExternalSecrets in
  `hga-hub-agent` may read it. [live]
- **An empty hub, repeat run and migration from the earlier layout still need
  live validation.** The historical runs upgraded an earlier install. With
  pruning disabled, the old `hub-cluster-spokes` Application can remain and
  track the same spoke ApplicationSets as the new group Application. Start on
  an empty hub and follow the [workshop guide](../workshop/README.md).

## Part 2. Onboarding a cluster with an agent [live]

| # | Who | Does what | Where |
|---|---|---|---|
| 1 | A person, OpenTofu | Only for a new tenant: its org, team projects, role and tenant key (`workshop/1-harness-setup/business-units.tf`). | Harness |
| 2 | A person, OpenTofu | Adds `workshop/2-clusters/cluster-values/<cluster>.yaml` (`role: spoke`, the tenant's org under the key `bu`, optionally `harnessSecretName`) and runs `tofu apply` in workspace `<cluster>`. The name must be `spoke-<name>`. That creates the k3d cluster `hga-<cluster>`, ServiceAccount `argocd-manager` with cluster-admin on it, and the spoke's own service account, API key and token in the tenant's org. It writes the connection into the store at `clusters/<cluster>` and the key at `harness-api-keys/<cluster>`. | Laptop, spoke, Harness, hub |
| 3 | A person | Commits `fleet-members/<cluster>.yaml` with `tenant`, `stage`, `gitopsAgent: true` and `harnessSecretName: harness-api-keys/<cluster>`. | Git |
| 4 | Hub Argo CD | `cluster-registration` makes Application `<cluster>-cluster` in `hga-hub-agent`: an ExternalSecret for the cluster Secret and, because `harnessSecretName` is set, what pushes the key (a kubeconfig ExternalSecret, an ExternalSecret for the key, `ClusterSecretStore` `push-<cluster>-hga-system` and a `PushSecret`). | Hub |
| 5 | ESO | Builds the cluster Secret `<cluster>`: the connection from the store, labels `fleet_member: spoke`, `tenant`, `stage` from the member file, annotations copied from the hub. | Hub |
| 6 | Hub Argo CD | The labels make three Applications for the spoke: `<cluster>-controller`, `<cluster>-runtime`, `<cluster>-teams`. | Hub to spoke |
| 7 | Hub Argo CD | `<cluster>-controller` installs the controller and its CRDs into `hga-system`. | Spoke |
| 8 | ESO | Pushes the key to the spoke as `harness-api-key-secret` in `hga-system`. It retries until step 7 has created the namespace. | Hub to spoke |
| 9 | Hub Argo CD | `<cluster>-runtime`, into namespace `<cluster>`: Argo CD with its CRDs, then the agent object and a locked `default` AppProject, then the agent pod. | Spoke |
| 10 | Spoke's controller | Registers the agent in Harness under org `<tenant>` at ORG scope, and writes `<cluster>-agent-token`. The agent pod starts and connects. | Spoke, Harness |
| 11 | Hub Argo CD | `<cluster>-teams`: for each team file, the team's namespaces, its AppProject and its mapping. The controller marks the mapping Ready once the agent is healthy. | Spoke |

Every Application of a cluster is named `<cluster>-<part>` and carries the
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
- **The workshop uses one `git_ref` across its own chart sources and values.**
  It defaults to `main` for every stage. The two upstream chart versions are
  in `groups/addons.yaml`: ESO `2.15.0` and OpenBao `0.30.7`. [built]

## Part 3. Later [theory]

Kept simple on purpose. None of this is planned work yet.

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
  namespaces.

## Not proven yet

1. Grouped bootstrap on an empty hub, a repeat run and migration from the
   earlier layout.
2. The `hub` workspace of `workshop/2-clusters` (cluster and delegate).
3. Any upgrade of Argo CD, the agent or the controller on a spoke.
4. Offboarding a team or a tenant. Spokes have been removed by hand.
5. A second tenant (`tenants/bu2/` is empty), a second stage running beside
   `test`, and a teams folder for one stage.
6. A team deploying from its own repository. The only Application that has
   run is one example created by hand on an earlier spoke.
7. The store after a restart: that ESO keeps the cluster Secrets and the
   pushed keys, and recovers once the entries are written again.
8. Anything outside k3d: a real cloud cluster, a persistent store, a
    network where the hub cannot reach a spoke's API.

## Open questions

1. Is cluster-admin for the hub on every spoke acceptable in the reference,
   or should the agent be installed when the cluster is created, so the hub
   needs less?
2. Who writes a new cluster's connection and key into the store in a real
   setup: the provisioning that creates the cluster?
3. Which store does the workshop use once dev-mode OpenBao is replaced?
4. Does the reference need staged upgrades (a pinned revision per stage)
   before it is published?
5. What may a team's users do in Harness? No Harness roles are designed for
   them.
6. Who raises changes to a tenant's files: the tenant by pull request, or
   only the platform team?
7. What is the offboarding sequence for a team, a spoke and a tenant?

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
