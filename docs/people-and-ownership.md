# People and ownership

> **Outdated.** This page and its diagram describe the state of 2026-11-13.
> Since then the Harness API key moved onto each spoke, `spokes.yaml` was
> replaced by member files and team files, and teams got their own
> namespaces. Read [Architecture](architecture.md) for the current state. The
> three actors and the rule "tenant = Harness org, team = Harness project"
> still hold.

> Draft for review. Status words used on this page: **proven** means run on
> the local test clusters (one hub, two spokes); **built** means in the repo
> but not run; **open** means not decided or not built.

This architecture starts from who owns what, not from the tooling. There are
three actors. Each owns a short list of things, and the design keeps
everything else out of their hands.

Diagram: [diagrams/people-and-ownership.drawio](diagrams/people-and-ownership.drawio)
(open it in Draw.io).

## The three actors

| Actor | In Harness | In one sentence |
|---|---|---|
| **Platform team** | The account and its own admin project | Runs the hub, registers every agent and installs everything on every spoke. |
| **Tenant** | One organization | A group that gets its own Harness org, its own spoke clusters and its own API key. A business unit is the usual example. |
| **Team** | One project in the tenant's org | Builds services and deploys them through its own Harness project. |

One rule ties the names together and is used everywhere in this guide:

- tenant = one Harness org = one org-scoped API key = the only tenant on its
  spoke clusters;
- team = one Harness project = one Argo CD AppProject on each of its tenant's
  spokes.

A tenant's spokes are grouped by **stage** (`nonprod`, `prod`). The stage is
the unit the platform team upgrades together.

## Who owns what

| Thing | Where it lives | Owner | Status |
|---|---|---|---|
| Controller and every Harness API key (one for the hub, one per tenant) | Hub cluster, namespace `hga-system` | Platform team | proven |
| Hub agent and its Argo CD | Hub cluster | Platform team | proven |
| ApplicationSets `agent-registration` and `spoke-runtime`, and the charts | This repo, `bootstrap/` and `charts/` | Platform team | proven |
| Spoke cluster Secret, labelled `tenant` and `stage` | Hub cluster | Platform team | proven; written by a local script today, by cluster provisioning later |
| Tenant file `tenants/<tenant>/<stage>/spokes.yaml`: teams, namespaces, source repos, pinned revision | This repo | Platform team reviews every change | proven; who raises the change is open |
| Agent object, project mappings and agent token for each spoke | Hub cluster, one namespace per spoke | Platform team; the controller writes them | proven |
| Argo CD, agent, AppProjects and team namespaces on a spoke | Spoke cluster | Platform team; nobody edits them by hand | proven |
| Harness org and its projects | Harness | Platform team creates them with OpenTofu; the tenant asks | proven |
| Applications | The spoke's agent, shown under the team's Harness project | Team | proven with one test Application |
| Source repositories | Git | Team | n/a |

## What each actor never needs

- **A team** never needs a Harness API key, a cluster credential or write
  access to this repo. It works in its Harness project and its own repos.
- **A tenant** never holds its org's API key. The key is created for the
  tenant, but it lives only on the hub and only the controller reads it.
- **A spoke** holds one credential for Harness: its own agent's token. It has
  no API key and no controller.
- **The platform team** does not create Applications for teams.

## What is not true yet

- **Teams are not fenced from each other.** Every team of a tenant gets the
  same namespaces and the same source repos on a spoke, and the spoke's Argo
  CD has cluster-wide rights. The tenant is the smallest unit with a real
  wall around it (its own cluster). Open: per-team namespaces.
- **The tenant has nothing it changes itself.** Its file lives in the
  platform's repo. Open: whether a tenant raises pull requests against its
  own file, with the platform team as reviewer.
- **What a team's users may do in Harness is not designed.** Open: the
  Harness roles that let a team manage Applications but not agents, clusters
  or AppProjects.
- **Two steps are still done by hand:** carrying a new agent's token from the
  hub to its spoke, and removing a spoke, a team or a tenant.
