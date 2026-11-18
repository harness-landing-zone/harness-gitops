# gitops-agent

The official `gitops-helm` 1.2.12 chart, vendored as its released tarball
(`charts/gitops-helm-1.2.12.tgz`, from github.com/harness/gitops-helm/releases)
under alias `gitopsAgent`, plus four optional templates for the hub. It
installs Argo CD, the Harness GitOps agent and, from gitops-helm's own
bootstrap templates, the `HarnessGitopsAgent`, its
`HarnessGitopsProjectMapping`s and (optionally) the `AppProject`.

| Template | Values | Renders |
|---|---|---|
| `apikey-secret.yaml` | `apiKeySecret` | the controller's API-key Secret (name from `gitopsAgent.harnessAgent.spec.apiKeySecretRef`, key `api_key`) |
| `bootstrap-repo.yaml` | `gitSecret` | repository (and `repo-creds`) Secret for the bundled Argo CD |
| `hub-cluster-secret.yaml` | `hubCluster` | labelled `hub-cluster` cluster Secret |
| `root-appset.yaml` | `rootAppSet` | root ApplicationSet (and with `createProject` its AppProject) as hooks |

All four are off by default. Only the hub release (`hub/account-agent.yaml`)
turns them on. The runtime entry in `groups/agents.yaml` uses this chart
for Argo CD and the running agent, and uses `charts/agent-registration` for
the registration resources. The group uses `charts/teams-bootstrap` for team
mappings.

## Why the extras exist

The hub is installed in one Native Helm release with no manual step after it:

- The controller needs the API key as a Secret; Harness injects it at deploy
  time into the controller's namespace (`hga-system`).
- A fresh Argo CD needs a credential for this repo before it can sync anything.
- The root ApplicationSet `groups` is the group installer: it makes one
  Application per file in `groups/`, named after the group, on the hub, from
  the repository and revision in `rootAppSet`.
- The root ApplicationSet and its AppProject are Argo CRs. gitops-helm's
  `appProject` template refuses to render until the AppProject CRD exists,
  and this release installs that CRD, so they are post-install hooks here.

## Values

Everything for gitops-helm goes under `gitopsAgent:` (including
`gitopsAgent.harnessAgent`, `gitopsAgent.projectMappings`,
`gitopsAgent.appProject`); `global` stays at the root. `values.yaml` documents
the four extras and the few gitops-helm defaults this chart changes
(`harnessAgent.enabled: true`, upgrader off, the agent HTTP target, log level,
smaller resource requests).

## Updating gitops-helm

1. Download the release asset `gitops-helm-<version>.tgz` from
   github.com/harness/gitops-helm/releases and replace the tarball in
   `charts/`.
2. Bump the version in `Chart.yaml` and `Chart.lock`. Once Harness's chart
   index lists the version, `helm dependency update` does both (and fixes the
   lock digest); until then the lock is written by hand.
3. Diff the old and new `values.yaml` and `templates/bootstrap/`, then render
   the hub (`hub/account-agent.yaml`) and a spoke runtime and compare.
