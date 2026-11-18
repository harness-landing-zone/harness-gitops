# Harness GitOps workshop

Start with a non-production Harness SaaS account with Continuous Delivery and GitOps enabled. OpenTofu creates the local k3d hub and installs its first Harness delegate. The bootstrap pipeline then installs the GitOps controller and account-scoped agent. A successful run brings up Argo CD, External Secrets Operator and OpenBao on the hub. The example spoke is optional.

## Before you start

Install Git, OpenTofu (`tofu`), Docker, k3d, `kubectl`, Helm, `jq` and OpenSSL. Run the commands in Bash or Zsh with Docker running locally. You also need permission to create and install a GitHub App on the repository you use for the workshop.

### Fork the workshop repository

On GitHub, fork [`harness-landing-zone/harness-gitops`](https://github.com/harness-landing-zone/harness-gitops) into an account or organization where you can install the app. Keep the repository name `harness-gitops` and clear **Copy the main branch only** so the fork includes `workshop-appsets-groups`. Use the revision on that branch that includes this guide and the companion workshop setup changes. Harness and Argo CD fetch the branch from GitHub, so the fork must contain that revision too. [GitHub fork instructions](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo)

Replace `YOUR_GITHUB_OWNER` with your fork's owner, then run:

```bash
git clone --branch workshop-appsets-groups https://github.com/YOUR_GITHUB_OWNER/harness-gitops.git
cd harness-gitops
git rev-parse HEAD
git ls-remote --exit-code origin refs/heads/workshop-appsets-groups
```

The local and remote commit IDs should match. If you already have a main-only fork, run the following from a clone whose `origin` points to your fork:

```bash
git fetch https://github.com/harness-landing-zone/harness-gitops.git workshop-appsets-groups
git switch -c workshop-appsets-groups FETCH_HEAD
git push -u origin workshop-appsets-groups
```

Run the remaining commands from the repository root.

### Get a Harness account ID and personal access token

1. Sign in to the workshop account at `app.harness.io`. In the account URL, copy the ID after `/account/`.
2. Use an existing valid PAT or create one in your Harness profile. Under **My API Keys**, select **API Key**, give it a name and save. Under that key, select **Token**, set an expiration long enough for the workshop, then generate and copy the token. [Harness API key instructions](https://developer.harness.io/docs/platform/automation/api/add-and-manage-api-keys/)
3. Use the token of an **Account Admin** or a user with equivalent permissions on the workshop account. The PAT inherits that user's permissions. Setup creates organizations, projects, roles, role assignments, service accounts and API tokens, as well as project secrets, connectors, a delegate token and CD resources. The person running the pipeline also needs permission to execute it. [Harness access control](https://developer.harness.io/docs/platform/role-based-access-control/rbac-in-harness/)

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

### Create and install a GitHub App

Reuse an existing GitHub App installation that can read the fork if you have its two IDs and private key. To create one:

1. In GitHub, open the fork owner's settings and go to **Developer settings → GitHub Apps → New GitHub App**. Give it a name and a homepage URL, such as the fork URL. Clear **Active** under **Webhook**, use the repository permissions documented for the Harness connector and select **Any account** under **Where can this GitHub App be installed?** [GitHub App registration](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app) · [Harness GitHub App connector permissions](https://developer.harness.io/harness-platform/use-harness-platform/connectors/code-repositories/add-a-github-connector/git-hub-app-support#create-the-github-app)
2. From the app's settings, select **Install App** and choose the fork owner. Select **Only select repositories**, choose `harness-gitops` and install. Copy the numeric **App ID** from the app's **General** tab and the numeric **installation ID** from the end of the `/settings/installations/…` URL for the installed app. [GitHub App installation instructions](https://docs.github.com/en/apps/using-github-apps/installing-your-own-github-app)
3. In the app's settings, open **Credentials → Key pairs → New key** to download a PEM private key. Create a private folder outside the checkout for the key and its PKCS#8 copy. [GitHub private key instructions](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps)

   ```bash
   umask 077
   mkdir -p "$HOME/.config/harness-gitops-workshop"
   ```

   Save or move the downloaded file to `~/.config/harness-gitops-workshop/github-app.pem`. Argo CD uses the original PEM in its repository credential. Convert a copy to unencrypted PKCS#8 PEM (`BEGIN PRIVATE KEY`) for the Harness GitHub connector:

   ```bash
   chmod 600 "$HOME/.config/harness-gitops-workshop/github-app.pem"
   openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
     -in "$HOME/.config/harness-gitops-workshop/github-app.pem" \
     -out "$HOME/.config/harness-gitops-workshop/github-app.pkcs8.pem"
   ```

## 1. Create the Harness resources

Create `workshop/1-harness-setup/terraform.tfvars` from the [example](1-harness-setup/terraform.tfvars.example) if you don't already have it.

```bash
if [ ! -e workshop/1-harness-setup/terraform.tfvars ]; then
  cp workshop/1-harness-setup/terraform.tfvars.example workshop/1-harness-setup/terraform.tfvars
fi
```

Edit the copy with your values. Keep the IDs in quotes and use the same `account_id` as `HARNESS_ACCOUNT_ID`.

```hcl
account_id                        = "YOUR_HARNESS_ACCOUNT_ID"
github_org                        = "YOUR_GITHUB_OWNER"
github_app_id                     = "YOUR_GITHUB_APP_ID"
github_app_installation_id        = "YOUR_GITHUB_INSTALLATION_ID"
github_app_private_key_file       = "~/.config/harness-gitops-workshop/github-app.pem"
github_app_private_key_pkcs8_file = "~/.config/harness-gitops-workshop/github-app.pkcs8.pem"
```

Use the defaults for the Harness organization `gitops_reference`, project `gitops_admin`, environment `test` and delegate `hga-test-hub`. Apply in the `default` workspace with local state. The hub module reads `workshop/1-harness-setup/terraform.tfstate` for the delegate credentials and name.

```bash
unset TF_WORKSPACE
tofu -chdir=workshop/1-harness-setup init
tofu -chdir=workshop/1-harness-setup workspace select default
tofu -chdir=workshop/1-harness-setup plan
tofu -chdir=workshop/1-harness-setup apply
```

Review the plan for the intended account before confirming. Keep both modules' state, saved plans, `terraform.tfvars` and your PEM files private. Local state contains generated tokens and GitHub App credentials. [Harness setup resources](1-harness-setup/README.md)

## 2. Create the local hub

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

Apply the `hub` workspace. It creates `hga-hub`, adds `k3d-hga-hub` to `~/.kube/config` and installs the Harness delegate in `harness-delegate-ng`.

```bash
export KUBECONFIG="$HOME/.kube/config"
tofu -chdir=workshop/2-clusters init
tofu -chdir=workshop/2-clusters workspace select -or-create hub
tofu -chdir=workshop/2-clusters apply
hub_delegate_name=$(tofu -chdir=workshop/1-harness-setup output -raw hub_delegate_name)
kubectl --context k3d-hga-hub -n harness-delegate-ng rollout status \
  deployment/"$hub_delegate_name" --timeout=5m
```

Wait for the delegate to show **Connected** in Harness and confirm the `hga_test_hub` Kubernetes connector uses it.

## 3. Deploy the hub from Harness

1. In organization **GitOps Reference Architecture** (`gitops_reference`) and project **GitOps Admin** (`gitops_admin`), verify the `hga_github` connector can connect to your fork. Open **Continuous Delivery → Pipelines → HGA Hub Bootstrap** (`hga_hub_bootstrap`). Select **Run**, then **Use existing Input Sets**, and choose **HGA Hub Bootstrap test** (`hga_hub_bootstrap_test`).
2. After selecting the input set, change **`git_ref`** from `main` to **`workshop-appsets-groups`**. Keep `image_tag` at `v0.1.0` and `deploy_agent` at `true`. Both stages use environment `test`, with infrastructure `hga_system` for the controller and `account_agent` for the hub agent.
3. Select **Run Pipeline**. Check that **Deploy Controller** and **Deploy Account Agent** succeed, including **Verify Agent Registration**. The Helm steps fetch the selected branch through the GitHub connector. [Harness input set instructions](https://developer.harness.io/docs/platform/pipelines/input-sets/)

## 4. Verify the hub and its secret store

```bash
kubectl --context k3d-hga-hub -n hga-system get pods
kubectl --context k3d-hga-hub -n hga-hub-agent get applications,applicationsets
kubectl --context k3d-hga-hub -n hga-hub-agent get application cluster-application-sets \
  -o jsonpath='{.spec.source.repoURL}{" "}{.spec.source.targetRevision}{"\n"}'
kubectl --context k3d-hga-hub -n hga-hub-agent get application \
  hub-cluster-addons hub-cluster-fleet hub-cluster-agents \
  -o 'custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,REVISIONS:.spec.sources[*].targetRevision'
```

Expect the root Application `cluster-application-sets` to point to your fork at `workshop-appsets-groups`. Wait for the root and all three group Applications to be **Synced** and check that the group's Git revisions match. The add-on Applications `hub-cluster-external-secrets` and `hub-cluster-openbao` should be **Synced** and **Healthy**. The example `spoke-test-cluster` Application may report a missing secret until you add the optional spoke.

```bash
kubectl --context k3d-hga-hub -n openbao wait --for=condition=Ready pod/openbao-0 --timeout=5m
kubectl --context k3d-hga-hub wait --for=condition=Ready clustersecretstore/hub-openbao --timeout=5m
kubectl --context k3d-hga-hub -n hga-hub-agent wait --for=condition=Ready \
  harnessgitopsprojectmappings.gitops.harness.io --all --timeout=5m
```

In Harness GitOps, confirm agent `hga_test_hub` (`hga-test-hub`) is connected and healthy at account scope and the hub's `default` AppProject is mapped to `gitops_reference/gitops_admin`.

## 5. Add the example spoke (optional)

Once OpenBao and `hub-openbao` are ready, apply the `spoke-test` workspace. It creates `hga-spoke-test`, adds `k3d-hga-spoke-test` to your kubeconfig and writes the cluster connection and its org-scoped controller key to OpenBao. The selected branch already contains [`fleet-members/spoke-test.yaml`](../fleet-members/spoke-test.yaml), so the hub can discover the spoke as soon as the store entries are available.

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
