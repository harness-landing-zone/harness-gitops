# People and ownership

> This page records the workshop at commit `0b56780`. The diagram records the
> state of 2026-11-13. See [Architecture](architecture.md) for the grouped
> bootstrap and current repository layout.

> Status words used on this page: **proven** means run on the local test
> clusters; **built** means in the repo but not run; **open** means not
> decided or not built.

This architecture starts from who owns what, not from the tooling. There are
three actors. Each owns a short list of things, and the design keeps
everything else out of their hands.

Diagram: [diagrams/people-and-ownership.drawio](diagrams/people-and-ownership.drawio)
(open it in Draw.io).

## The three actors

| Actor | In Harness | In one sentence |
|---|---|---|
| **Platform team** | The account and its own admin project | Runs the hub, onboards every spoke and installs everything on it. |
| **Tenant** | One org | Owns spokes: it gets its own Harness org and its own spoke clusters. A business unit can be a tenant. |
| **Team** | One project in the tenant's org | Builds services and deploys them through its own Harness project. |

One rule ties the names together and is used everywhere in this guide:

- tenant = one Harness org = the only tenant on its spoke clusters;
- team = one Harness project = one Argo CD AppProject on each of its tenant's
  spokes.

Every spoke has a **stage** (for example `test`, `nonprod`, `prod`). The
stage chooses which values and which teams the spoke gets. Nothing is
upgraded stage by stage yet: every stage follows `main`.

A spoke's agent is either **self-managed** (the spoke runs its own controller
and holds its own API key) or **hub-managed** (the key and the agent objects
stay on the hub). The table says where the two differ.

## Who owns what

| Thing | Where it lives | Owner | Status |
|---|---|---|---|
| The hub's controller, the account-level API key and each tenant's API key | Hub cluster, namespace `hga-system` | Platform team | proven |
| Hub agent and its Argo CD | Hub cluster | Platform team | proven |
| The ApplicationSets and the charts | This repo, `groups/` and `charts/` | Platform team | proven |
| Member file `fleet-members/<cluster>.yaml`: tenant, stage and model of one spoke | This repo | Platform team | proven |
| Spoke cluster Secret, labelled `tenant` and `stage` | Hub cluster | Platform team; External Secrets builds it from the store and the member file | proven |
| Tenant files under `tenants/<tenant>/gitops-agents/`: agent values, and one file per team with its Harness project, namespaces and source repos | This repo | Platform team reviews every change | proven; who raises the change is open |
| Agent object, project mappings and, when self-managed, the spoke's controller and API key | Self-managed: the spoke. Hub-managed: the hub, one namespace per spoke | Platform team; the controller writes the agent token | self-managed proven; no current spoke is hub-managed |
| Argo CD, agent, agent token, AppProjects and team namespaces on a spoke | Spoke cluster | Platform team; nobody edits them by hand | proven |
| Harness org and its projects | Harness | Platform team creates them with OpenTofu; the tenant asks | proven |
| Applications | The spoke's agent, shown under the team's Harness project | Team | proven with one test Application on an earlier spoke |
| Source repositories | Git | Team | n/a |

## What each actor never needs

- **A team** never needs a Harness API key, a cluster credential or write
  access to this repo. It works in its Harness project and its own repos.
- **A tenant** never holds an API key. Keys are created in its org, but only
  controllers read them.
- **A hub-managed spoke** holds one credential for Harness: its own agent's
  token. It has no API key and no controller. **A self-managed spoke** also
  runs a controller and holds its own API key, scoped to the tenant's org.
- **The platform team** does not create Applications for teams.

## What is not true yet

- **A team's fence is Argo CD policy only.** Each team has its own
  namespaces, source repos and AppProject, but the spoke's Argo CD has
  cluster-wide rights.
- **The tenant has nothing it changes itself.** Its files live in the
  platform's repo. Open: whether a tenant raises pull requests against its
  own files, with the platform team as reviewer.
- **What a team's users may do in Harness is not designed.** Open: the
  Harness roles that let a team manage Applications but not agents, clusters
  or AppProjects.
- **Removing a spoke, a team or a tenant is done by hand.**
