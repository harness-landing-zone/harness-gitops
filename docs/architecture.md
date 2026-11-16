# Architecture: what is built, how it runs, what is not proven

This document describes the repository at commit `4d7badc` (branch `main`,
2026-11-16). Anything changed after that commit is not covered, with one
exception: the Application names and labels are those of commit `9de762e`.

It is written for a reader with no context, and for reviewers looking for
gaps. Every statement about the build carries one of four marks:

| Mark | Meaning |
|---|---|
| **[live]** | Run on the test setup: three local k3d clusters (one hub, two spokes). |
| **[built]** | In the repository, never run. |
| **[decided]** | Decided, not built. |
| **[theory]** | Reasoning only. |

## Design intent

One account-level agent on a **hub** cluster deploys an agent onto every
**spoke** cluster. Everything that talks to the Harness API with an API key
(registering agents, mapping projects) should belong to the hub. A spoke
should only do GitOps: run Argo CD and its agent, and hold nothing but that
agent's own token.

Today's running model does not meet that intent yet: every spoke runs its own
controller and holds a Harness API key that a person put there. A second
model that meets the intent is built but has not run. Both are described
below.

## Names

| Name | Meaning |
|---|---|
| Hub | The cluster that runs the hub agent, the controller, External Secrets Operator (ESO) and the secret store. |
| Hub agent | The Harness GitOps agent on the hub, with its Argo CD. Account scope. It applies everything in this repo. |
| Spoke | A workload cluster with its own Argo CD and agent. |
| Fleet member, member file | A cluster is a fleet member because `fleet-members/<cluster>.yaml` exists. The file name is the cluster's name. |
| Tenant | A business unit. One Harness organization. `bu1` is the example. |
| Stage | `nonprod` or `prod`. Chooses which values and which teams a spoke gets. |
| Team | One Harness project in the tenant's org, one Argo CD AppProject on the spoke. |
| Controller | The Harness GitOps Agent controller (`charts/harness-gitops-agent-controller`). It registers agents and project mappings in Harness, using an API key. |
| Agent object | A `HarnessGitopsAgent` resource. The controller registers it and writes the agent's token Secret beside it. |
| Mapping | A `HarnessGitopsProjectMapping` resource: one AppProject mapped to one Harness project. |
| Cluster Secret | An Argo CD cluster Secret on the hub. Its labels decide what gets installed on that cluster. |
| Store | OpenBao on the hub, read by ESO through `ClusterSecretStore` `hub-openbao`. |
| Today's model (v1) | A controller on every spoke. Member file `agentModel: ""`. |
| Hub model | Only the hub's controller. Member file `agentModel: hub`. |

## Repository layout

```
bootstrap/          applied by the hub's root Application
  hub-external-secrets.yaml   ESO on the hub
  hub-openbao.yaml            OpenBao (dev mode) and the store on the hub
  cluster-registration.yaml   one Application per member file: the cluster Secret
  agent-registration.yaml     hub model only: agent object and mappings on the hub
  spokes.yaml                 applies spoke-bootstrap/
spoke-bootstrap/    ApplicationSets that install things on spokes
  spoke-controller.yaml       today's model only: the controller on the spoke
  spoke-runtime.yaml          Argo CD, the agent, a locked default AppProject
  spoke-teams.yaml            team namespaces, AppProjects, mappings
fleet-members/<cluster>.yaml  one file per spoke: tenant, stage, gitopsAgent, agentModel
tenants/<tenant>/gitops-agents/
  defaults/values.yaml        values for every agent of the tenant
  <stage>/values.yaml         values for one stage (optional)
  <stage>/teams/<team>/values.yaml   one file per team
charts/
  harness-gitops-agent-controller   the official controller chart, unchanged
  gitops-agent                wraps the official gitops-helm chart (Argo CD and agent)
  cluster-registration        the store, and per member the ExternalSecret(s)
  fleet-member-registration   the agent object, the locked default AppProject, the token push
  teams-bootstrap             per team: namespaces, AppProject, mapping
hub/                values for the Day 0 pipeline: controller.yaml, account-agent.yaml
addons/hub/         values for the hub's add-ons (OpenBao)
workshop/1-harness-setup/     OpenTofu for every Harness entity, and the pipeline YAML
```

`local/k3d.sh` creates the test clusters. It lives outside the repository.

## Who holds what

| Thing | Today's model (v1) [live] | Hub model [built] |
|---|---|---|
| Controller | Hub, and one on every spoke | Hub only |
| Account-level API key | Hub, namespace `hga-system` | Same |
| Tenant's API key | By hand on every spoke (`harness-api-key-secret` in `hga-system`). A copy also sits on the hub (`harness-api-key-bu1`), unused. | Hub only (`harness-api-key-<tenant>`) |
| Agent object | Spoke | Hub, in a namespace named after the spoke |
| Agent token | Written on the spoke by the spoke's controller | Written on the hub by the hub's controller, then copied to the spoke by ESO |
| Mappings | Spoke | Hub |
| Placeholder AppProjects | None | Hub: one deny-all AppProject per team (see caveat 2) |
| Argo CD and the agent pod | Spoke | Spoke |
| Team namespaces and real AppProjects | Spoke | Spoke |
| Spoke connection with cluster-admin | Hub: the cluster Secret and the store | Hub: the same, plus a kubeconfig Secret for ESO |

Caveats that apply to the design, not to a missing step:

1. **The hub holds cluster-admin on every spoke.** It needs it to install the
   agent there. Whoever controls the hub controls every spoke. This is true
   in both models; in the hub model ESO holds the same credential as well.
2. **The hub model needs placeholder AppProjects.** The controller marks a
   mapping Ready only when an AppProject of that name exists beside the agent
   object. In the hub model the real AppProject is on the spoke, so the hub
   carries an empty one of the same name. A Ready mapping on the hub then no
   longer proves that the real AppProject exists on the spoke. The controller
   does not document this check, so a controller change could break it.
3. **A team's fence on a spoke is Argo CD policy.** The spoke's Argo CD has
   cluster-wide rights. What keeps a team in its own namespaces is its
   AppProject.
4. **In the hub model a spoke cannot be registered while the hub is down.**
   Agents that are already running keep working in both models.

## Part 1. From zero to a hub that manages spokes

| # | Who | Does what | Where | Mark |
|---|---|---|---|---|
| 1 | A person | Creates and installs a GitHub App for the repo and saves its private key. Has a Harness account and a personal access token. | GitHub, Harness | [live] |
| 2 | Script | `local/k3d.sh up` creates three clusters on one Docker network: `hga-hub`, `hga-spoke-nonprod`, `hga-spoke-prod`. | Laptop | [live] |
| 3 | A person, OpenTofu | `tofu apply` in `workshop/1-harness-setup/`. Creates the platform org and project, the account-level role, service account and API key for the controller, the Harness secrets, the GitHub and Kubernetes connectors, a delegate token, and the environment, infrastructures, services, pipeline and input set. | Harness | [live] |
| 4 | Same apply | Per tenant (`business-units.tf`, only `bu1`): the org, one project per team (`team_a`, `team_b`), and an org-level role, service account, API key and token. | Harness | [live] |
| 5 | A person | Installs a Harness delegate on the hub. The OpenTofu module prints the command. | Hub | [live] with a delegate installed earlier; the printed command is [built] |
| 6 | A person | Pushes this repo to `main`. The pipeline fetches charts and values from `main`. | GitHub | [live] |
| 7 | Pipeline `hga_hub_bootstrap`, stage 1 | Installs the controller and its CRDs into `hga-system` (`hub/controller.yaml`). | Hub | [live] |
| 8 | Pipeline, stage 2 | Installs `charts/gitops-agent` into `hga-hub-agent` (`hub/account-agent.yaml`): Argo CD, the hub agent and its agent object, one mapping, the API key Secrets in `hga-system`, the repo credential, the cluster Secret `hub-cluster`, and the root ApplicationSet. | Hub | [live] |
| 9 | Controller | Registers the hub agent in Harness and writes its token. The agent connects. The pipeline's last step waits for that. | Hub, Harness | [live] |
| 10 | Hub Argo CD | The root Application `cluster-application-sets` applies `bootstrap/`: five ApplicationSets. | Hub | [live] |
| 11 | Hub Argo CD | `hub-external-secrets` installs ESO. `hub-openbao` installs OpenBao and the store `hub-openbao`. | Hub | [live] |
| 12 | Hub Argo CD | `spokes` makes Application `hub-cluster-spokes`, which applies `spoke-bootstrap/`: three more ApplicationSets. | Hub | [live] |

After step 12 the hub waits for member files.

- **The cluster Secret `hub-cluster` is the hub's only input.** Its
  annotations carry the repo URL and the Harness account id. The hub-level
  ApplicationSets (`hub-external-secrets`, `hub-openbao`,
  `cluster-registration`, `spokes`) read them from there.
  `cluster-registration` copies them onto every spoke's cluster Secret, and
  the ApplicationSets that work per spoke (`spoke-controller`,
  `spoke-runtime`, `spoke-teams`, `agent-registration`) read them from that
  Secret. [live]
- **The store is OpenBao in dev mode.** It keeps everything in memory, is
  opened with the chart's published dev token, and is empty after every
  restart. It holds only cluster connections, at `clusters/<cluster>` with
  keys `server`, `caData` and `token`. Harness API keys never enter it. Only
  ExternalSecrets in `hga-hub-agent` may read it. [live]
- **A pipeline run against a completely empty hub has not been recorded.**
  The successful runs upgraded an earlier install.

## Part 2. Onboarding a cluster with an agent

### Today's model [live]

| # | Who | Does what | Where |
|---|---|---|---|
| 1 | A person, OpenTofu | Only for a new tenant: its org, team projects and API key. | Harness |
| 2 | Script | `local/k3d.sh register` creates ServiceAccount `argocd-manager` with cluster-admin on the spoke and writes the spoke's connection into the store at `clusters/<cluster>`. The script knows only the two test spokes (`spoke-nonprod`, `spoke-prod`); any other cluster needs its entry written another way. | Spoke, hub |
| 3 | **A person, by hand** | Creates namespace `hga-system` and Secret `harness-api-key-secret` on the spoke from the tenant's API key. Never in git. | Spoke |
| 4 | A person | Commits `fleet-members/<cluster>.yaml` with `tenant`, `stage`, `gitopsAgent: true` and `agentModel: ""`. | Git |
| 5 | Hub Argo CD | `cluster-registration` makes Application `<cluster>-cluster`: one ExternalSecret in `hga-hub-agent`. | Hub |
| 6 | ESO | Builds the cluster Secret `<cluster>`: the connection from the store, labels `fleet_member: spoke`, `tenant`, `stage` from the member file, annotations copied from the hub. | Hub |
| 7 | Hub Argo CD | The labels make three Applications for the spoke: `<cluster>-controller`, `<cluster>-runtime`, `<cluster>-teams`. | Hub to spoke |
| 8 | Hub Argo CD | `<cluster>-controller` installs the controller and its CRDs into `hga-system`. | Spoke |
| 9 | Hub Argo CD | `<cluster>-runtime`, into namespace `<cluster>`: Argo CD with its CRDs, then the agent object and a locked `default` AppProject, then the agent pod. | Spoke |
| 10 | Spoke's controller | Registers the agent in Harness under org `<tenant>` at ORG scope, and writes `<cluster>-agent-token`. The agent pod starts and connects. | Spoke, Harness |
| 11 | Hub Argo CD | `<cluster>-teams`: for each team file, the team's namespaces, its AppProject and its mapping. The controller marks the mapping Ready once the agent is healthy. | Spoke |

Every Application of a cluster is named `<cluster>-<part>` and carries the
labels `cluster`, `tenant` and `stage`. In the Harness GitOps list a cluster's
Applications therefore sort together, and the label filter `cluster:<name>`
returns all of them. [live]

What is live and what is not:

- Both spokes run this model: twelve Applications Synced and Healthy, both
  agents healthy in Harness under org `bu1`. [live]
- Steps 4 to 6 have only run as a **takeover**: both spokes already had a
  hand-made cluster Secret, which ESO adopted. Registering a cluster that the
  hub has never seen is [built].
- `nonprod` has teams `team-a` and `team-b`, both mapped. `prod` has no teams
  folder. [live]
- Step 3 is the manual step the design intent wants gone. The hub model
  removes it.

### Hub model [built, never run]

The member file says `agentModel: hub`. That adds the label
`agent_model: hub` to the cluster Secret, and the ApplicationSets branch on it.

| Step | What differs from today's model |
|---|---|
| Step 3 | Gone. No API key and no controller on the spoke. `spoke-controller` skips the cluster. |
| Step 5 | `<cluster>-cluster` also renders a second ExternalSecret, `<cluster>-kubeconfig`, built from the same store entry, and a `ClusterSecretStore` `push-<cluster>` that lets ESO write into namespace `<cluster>` on the spoke. Only the hub namespace `<cluster>` may use that store. |
| New, on the hub | `agent-registration` makes Application `<cluster>-agent` in hub namespace `<cluster>`: the agent object (using `harness-api-key-<tenant>` from the hub's `hga-system`), a `PushSecret`, and per team a mapping with a placeholder AppProject. |
| Hub's controller | Registers the agent and writes `<cluster>-agent-token` on the hub. |
| ESO | The `PushSecret` copies that Secret to the same name and namespace on the spoke. |
| Step 9 | `<cluster>-runtime` installs Argo CD, the locked `default` AppProject and the agent pod, but no agent object. The pod starts once the pushed token arrives. |
| Step 11 | `<cluster>-teams` installs only namespaces and real AppProjects. The mappings are on the hub. |

The namespace has the same name on the hub and on the spoke, because the
controller registers the agent with its object's namespace.

Token delivery has one implementation: **push**, as above. The chart has a
key `tokenDelivery` that accepts only `push`. **Pull** (the hub pushes the
token into the store and an ESO on the spoke reads it) is [theory]: it needs
ESO on every spoke, a store the spokes can reach, and a login per spoke.

### Moving a running spoke from today's model to the hub model [theory, planned]

A takeover is not possible. The controller treats a Harness agent as its own
only if it created it, so the hub's controller cannot adopt an agent that a
spoke's controller registered. The move is: switch the agent off in the
member file, delete the agent object on the spoke so its controller
deregisters it, remove the controller, its CRDs and the key Secret from the
spoke, then switch the member file to `agentModel: hub`. The agent is
registered again with a new token. Applications that teams created on the old
agent are not covered by this plan.

### Onboarding a team [live on nonprod]

1. OpenTofu creates the team's Harness project in the tenant's org.
2. A person commits
   `tenants/<tenant>/gitops-agents/<stage>/teams/<team>/values.yaml` with the
   project id, the source repos, the namespaces and the destinations.
3. `<cluster>-teams` applies it on every spoke of that tenant and stage.

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
  Harness. Offboarding is a manual sequence that is not written down. [live]
- **Never delete the ExternalSecret of a live spoke.** It owns the cluster
  Secret; deleting it removes the hub's access to the spoke. [built]
- **No old `<cluster>-agent-token` may exist** where a controller is about to
  register an agent. The controller never overwrites one. [live]
- **After a hub restart, run `local/k3d.sh register` again.** The store is
  empty. Existing cluster Secrets stay in place meanwhile. [built]
- **This repo's own charts and values follow `HEAD` of `main`.** Nothing pins
  a revision per stage, so a chart change reaches nonprod and prod together.
  The two upstream charts are pinned: ESO `2.15.0` in
  `bootstrap/hub-external-secrets.yaml` and OpenBao `0.30.7` in
  `bootstrap/hub-openbao.yaml`. [built]

## Part 3. Later [theory]

Kept simple on purpose. None of this is planned work yet.

- **Pull delivery of the agent token**, as described above.
- **A persistent store.** Replace dev-mode OpenBao with a store that survives
  restarts, and replace the dev token with Kubernetes auth for ESO.
- **Staged upgrades.** A pinned revision per stage, so nonprod moves before
  prod.
- **Two agents in one cluster: one cluster-wide, one namespaced.** The
  namespaced one would run without ClusterRoles, without installing CRDs and
  without the built-in cluster destination, behind Roles limited to its own
  namespaces. What stands in the way: such an agent has never run; a cluster
  Secret describes exactly one agent today; the Argo CD CRDs can have only
  one owner per cluster; two Argo CDs on one cluster can claim each other's
  resources; and the cluster-wide one can still reach into the other's
  namespaces. The hub model makes this easier, because nothing of the
  controller remains on the spoke.

## Not proven yet

1. Registering a cluster from nothing through a member file (only takeovers
   have run).
2. Everything in the hub model: the `PushSecret` through ESO's Kubernetes
   store, the kubeconfig Secret ESO builds, the agent pod starting on a
   pushed token without a manual restart, and mappings going Ready on the hub
   against placeholder AppProjects in this layout. (A similar layout ran on
   2026-11-13 with a hand-carried token; it was removed since.)
3. Moving a running spoke from today's model to the hub model.
4. A pipeline run on an empty hub.
5. The delegate install command the OpenTofu module prints.
6. Any upgrade of Argo CD, the agent or the controller on a spoke.
7. Offboarding a team, a spoke or a tenant.
8. Teams on a `prod` spoke, and a second tenant (`tenants/bu2/` is empty).
9. A team deploying from its own repository. The only Application that has
   run is one example created by hand.
10. The store after a restart: that ESO keeps the cluster Secrets and
    recovers once `register` has run again.
11. Anything outside k3d: a real cloud cluster, a persistent store, a
    network where the hub cannot reach a spoke's API.

## Open questions

1. When does the first spoke move to the hub model, and which one?
2. Placeholder AppProjects: accept them, or change the controller so a
   mapping for an agent on another cluster needs none?
3. One API key per tenant (as `bu1` has) or one per spoke?
4. Is cluster-admin for the hub on every spoke acceptable in the reference,
   or should the agent be installed when the cluster is created, so the hub
   needs less?
5. Who writes a new cluster's connection into the store in a real setup: the
   provisioning that creates the cluster?
6. Which store does the workshop use once dev-mode OpenBao is replaced?
7. Does the reference need staged upgrades (a pinned revision per stage)
   before it is published?
8. What may a team's users do in Harness? No Harness roles are designed for
   them.
9. Who raises changes to a tenant's files: the tenant by pull request, or
   only the platform team?
10. What is the offboarding sequence for a team, a spoke and a tenant?

## Inconsistencies in the repository at this commit

These are comments and files that say something the build no longer does.

- `bootstrap/spokes.yaml` says an ApplicationSet named `spoke-bootstrap`
  still owns the spokes' Applications. It no longer exists on the hub.
- `spoke-bootstrap/spoke-runtime.yaml` says in its header that nothing
  carries a token between clusters. In the hub model ESO does.
- `tenants/bu1/gitops-agents/defaults/values.yaml` says it is read by
  `bootstrap/spoke-runtime.yaml`. The file is
  `spoke-bootstrap/spoke-runtime.yaml`.
- `examples/org/` describes an earlier pattern and a chart
  (`charts/org-platform`) that is no longer in the repository.
- `workshop/1-harness-setup/README.md` does not mention the per-tenant
  entities that `business-units.tf` creates.
- [People and ownership](people-and-ownership.md) and its diagram describe an
  earlier state.
