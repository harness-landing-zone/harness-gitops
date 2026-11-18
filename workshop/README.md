# Harness GitOps workshop

Start with a non-production Harness SaaS account with GitOps enabled. OpenTofu creates the Harness organization, project and controller identities, then creates the local k3d hub and installs the GitOps controller and the account-scoped hub agent on it with Helm. Argo CD on the hub then installs everything else from this repository: External Secrets Operator, OpenBao and the fleet. The example spoke is optional.

## Before you start

Install Git, OpenTofu (`tofu`), Docker, k3d, `kubectl`, Helm and `jq`. Run the commands in Bash or Zsh with Docker running locally.

### Get the repository

OpenTofu installs the two hub charts from your local checkout. Argo CD reads the rest from GitHub, at the branch in `workshop/2-clusters/cluster-values/hub.yaml` (`revision`, default `main`).

```bash
git clone https://github.com/harness-landing-zone/harness-gitops.git
cd harness-gitops
```

If you check out another branch, set `revision` in `workshop/2-clusters/cluster-values/hub.yaml` to that branch, so the hub follows the same files you are reading. Run the remaining commands from the repository root.

A fork is optional: you need one only to change the groups or the fleet members the hub reads. Fork [`harness-landing-zone/harness-gitops`](https://github.com/harness-landing-zone/harness-gitops), keep the name `harness-gitops`, clone the fork instead, push the branch you use, and set `github_org` to the fork's owner in step 1. [GitHub fork instructions](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo)

### Get a Harness account ID and personal access token

1. Sign in to the workshop account at `app.harness.io`. In the account URL, copy the ID after `/account/`.
2. Use an existing valid PAT or create one in your Harness profile. Under **My API Keys**, select **API Key**, give it a name and save. Under that key, select **Token**, set an expiration long enough for the workshop, then generate and copy the token. [Harness API key instructions](https://developer.harness.io/docs/platform/automation/api/add-and-manage-api-keys/)
3. Use the token of an **Account Admin** or a user with equivalent permissions on the workshop account. The PAT inherits that user's permissions. Setup creates organizations, projects, roles, role assignments, service accounts and API tokens. [Harness access control](https://developer.harness.io/docs/platform/role-based-access-control/rbac-in-harness/)

Paste this block into your workshop terminal, then enter the values when prompted. The token prompt hides what you type and keeps it out of shell history.

```bash
{
  set +x
  printf 'Harness account ID: '
  IFS= read -r HARNESS_ACCOUNT_ID
  printf 'Harness personal access token: '
  IFS= read -rs HARNESS_PLATFORM_API_KEY
  printf '\n'
  export HARNESS_ACCOUNT_ID HARNESS_PLATFORM_API_KEY
}
```

## 1. Create the Harness resources

Create `workshop/1-harness-setup/terraform.tfvars` from the [example](1-harness-setup/terraform.tfvars.example) if you don't already have it.

```bash
if [ ! -e workshop/1-harness-setup/terraform.tfvars ]; then
  cp workshop/1-harness-setup/terraform.tfvars.example workshop/1-harness-setup/terraform.tfvars
fi
```

Edit the copy: set `account_id` to the same value as `HARNESS_ACCOUNT_ID`, and `github_org` to your fork's owner if you use a fork.

```hcl
account_id = "YOUR_HARNESS_ACCOUNT_ID"
# github_org = "YOUR_GITHUB_OWNER"
```

The defaults create the Harness organization `gitops_reference`, project `gitops_admin`, environment `test` and one tenant organization `bu1` with projects `team_a` and `team_b`. To use your own names, see [Your own names](#your-own-names) before you apply. Apply in the `default` workspace with local state. The hub workspace reads `workshop/1-harness-setup/terraform.tfstate` for the keys and identifiers.

```bash
unset TF_WORKSPACE
tofu -chdir=workshop/1-harness-setup init
tofu -chdir=workshop/1-harness-setup workspace select default
tofu -chdir=workshop/1-harness-setup plan
tofu -chdir=workshop/1-harness-setup apply
```

Review the plan for the intended account before confirming. Keep both modules' state, saved plans and `terraform.tfvars` private. Local state contains the generated tokens. [Harness setup resources](1-harness-setup/README.md)

### Your own names

Set any of these in `terraform.tfvars`:

| Variable | What it names | Default |
|---|---|---|
| `org_id`, `org_name` | The platform organization | `gitops_reference`, "GitOps Reference Architecture" |
| `project_id`, `project_name` | The admin project that the hub's AppProject `default` maps to | `gitops_admin`, "GitOps Admin" |
| `environment_id` | The hub: its agent is `hga-<id>-hub` | `test` |
| `business_units` | The tenant organizations and their team projects | `bu1` with `team_a`, `team_b` |

The platform organization, project and environment need nothing else: the hub install reads them from this stage's outputs.

The tenant and team identifiers are also written in the repository, so changing `business_units` needs a fork (set `github_org`) with the same names in:

- the folder `tenants/<tenant>/`;
- `tenant:` in each `fleet-members/*.yaml`;
- `bu:` in each spoke's `workshop/2-clusters/cluster-values/*.yaml`;
- `projectId:` in `tenants/<tenant>/gitops-agents/defaults/teams/<team>/values.yaml`.

The controller's role, service account and key are named `hga_controller` at account level, so one Harness account holds one workshop.

## 2. Create the hub

The hub and spoke share the `hga` Docker bridge. The cluster script pins container IPs, so create the bridge with an explicitly selected IPv4 subnet. Check for an existing network, local clusters, and subnet overlaps before creating anything:

```bash
docker info --format '{{.Name}}'
k3d cluster list
docker network inspect $(docker network ls -q) \
  --format '{{.Name}} driver={{.Driver}} internal={{.Internal}} {{range .IPAM.Config}}subnet={{.Subnet}} {{end}}'
```

Check your host and VPN routes with `netstat -rn -f inet` on macOS or `ip -4 route` on Linux. If `hga` is absent, choose an unused private range outside the non-default routes, the existing Docker subnets and the k3s pod and service networks (`10.42.0.0/16` and `10.43.0.0/16`). Substitute your own subnet if the example overlaps:

```bash
docker network create --driver bridge --subnet 172.30.80.0/24 hga
```

If `hga` already exists, reuse it only if it's a workshop bridge with an explicitly configured, non-overlapping IPv4 subnet and external access (`internal=false`). If the network or the `hga-hub` cluster belongs to another setup, use a separate Docker environment. [Docker bridge network settings](https://docs.docker.com/reference/cli/docker/network/create/)

Apply the `hub` workspace. It creates `hga-hub`, adds `k3d-hga-hub` to `~/.kube/config`, then installs Helm release `hga-controller` (the controller, namespace `hga-system`) and Helm release `hga-hub-agent` (the hub agent and its Argo CD, namespace `hga-hub-agent`). The keys reach the cluster only as Kubernetes Secrets.

```bash
export KUBECONFIG="$HOME/.kube/config"
tofu -chdir=workshop/2-clusters init
tofu -chdir=workshop/2-clusters workspace select -or-create hub
tofu -chdir=workshop/2-clusters apply
```

### A private fork

Argo CD reads a public repository without credentials. For a private fork, give the hub's Argo CD a credential for the fork's owner right after the apply. Replace `YOUR_GITHUB_OWNER`, and enter a GitHub token that can read the repository when prompted:

```bash
printf 'GitHub token: '; IFS= read -rs GITHUB_TOKEN; printf '\n'
printf '%s' "$GITHUB_TOKEN" | kubectl --context k3d-hga-hub -n hga-hub-agent \
  create secret generic fork-repo-creds \
  --from-literal=type=git \
  --from-literal=url=https://github.com/YOUR_GITHUB_OWNER \
  --from-literal=username=git \
  --from-file=password=/dev/stdin
unset GITHUB_TOKEN
kubectl --context k3d-hga-hub -n hga-hub-agent label secret fork-repo-creds \
  argocd.argoproj.io/secret-type=repo-creds
```

The root ApplicationSet retries until the credential is there.

## 3. Verify the hub and its secret store

```bash
kubectl --context k3d-hga-hub -n hga-system get pods
kubectl --context k3d-hga-hub -n hga-hub-agent get harnessgitopsagent hga-test-hub \
  -o jsonpath='{.status.agentIdentifier}{"\n"}'
kubectl --context k3d-hga-hub -n hga-hub-agent wait --for=condition=Ready \
  harnessgitopsprojectmappings.gitops.harness.io/hub-admin --timeout=5m
kubectl --context k3d-hga-hub -n hga-hub-agent get applicationset groups
kubectl --context k3d-hga-hub -n hga-hub-agent get application addons fleet agents \
  -o 'custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISIONS:.spec.sources[*].targetRevision'
```

Expect the agent identifier `hga_test_hub`, the `hub-admin` mapping Ready, and the three group Applications `addons`, `fleet` and `agents` **Synced** at your `revision`. The add-on Applications `hub-cluster-external-secrets` and `hub-cluster-openbao` should be **Synced** and **Healthy**. The example `spoke-test-registration` Application may report a missing secret until you add the optional spoke.

```bash
kubectl --context k3d-hga-hub -n hga-hub-agent get applications
kubectl --context k3d-hga-hub -n openbao wait --for=condition=Ready pod/openbao-0 --timeout=5m
kubectl --context k3d-hga-hub wait --for=condition=Ready clustersecretstore/hub-openbao --timeout=5m
```

In Harness GitOps, confirm agent `hga_test_hub` (`hga-test-hub`) is connected and healthy at account scope and the hub's `default` AppProject is mapped to `gitops_reference/gitops_admin`.

## 4. Add the example spoke (optional)

Once OpenBao and `hub-openbao` are ready, apply the `spoke-test` workspace. It creates `hga-spoke-test`, adds `k3d-hga-spoke-test` to your kubeconfig and writes the cluster connection and its org-scoped controller key to OpenBao. The repository already contains [`fleet-members/spoke-test.yaml`](../fleet-members/spoke-test.yaml), so the hub can discover the spoke as soon as the store entries are available.

```bash
tofu -chdir=workshop/2-clusters workspace select -or-create spoke-test
tofu -chdir=workshop/2-clusters apply
kubectl --context k3d-hga-hub -n hga-hub-agent wait --for=condition=Ready \
  externalsecret/spoke-test --timeout=5m
kubectl --context k3d-hga-hub -n hga-hub-agent get secret spoke-test
kubectl --context k3d-hga-hub -n hga-hub-agent get applications -l cluster=spoke-test
kubectl --context k3d-hga-spoke-test -n spoke-test get \
  pods,appprojects,harnessgitopsagents,harnessgitopsprojectmappings
kubectl --context k3d-hga-spoke-test -n spoke-test wait --for=condition=Ready \
  harnessgitopsprojectmappings.gitops.harness.io --all --timeout=5m
```

If the spoke namespace or CRDs are still being created, wait for `spoke-test-controller`, `spoke-test-runtime` and `spoke-test-teams` to appear on the hub and retry the spoke checks. In Harness, verify `spoke_test` (`spoke-test`) is connected and healthy in org `bu1`, with mappings for `team-a` and `team-b` to projects `team_a` and `team_b`.

OpenBao runs in dev mode and loses its entries on restart. See the cluster notes for workspace cleanup and restoring those entries. [Local cluster details](2-clusters/README.md)
