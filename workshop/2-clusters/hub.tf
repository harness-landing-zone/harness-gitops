# The hub's day-0 install: the controller, then the ACCOUNT-scoped hub agent
# with its Argo CD. Argo CD bootstraps everything else from the repository.
# Static values come from hub/; the per-hub inputs below come from
# ../1-harness-setup and cluster-values/hub.yaml. The keys go in only through
# set_sensitive.
locals {
  setup        = one(data.terraform_remote_state.setup[*].outputs)
  env          = try(local.setup.environment_id, "")
  agent_name   = "hga-${local.env}-hub"
  agent_id     = "hga_${local.env}_hub"
  token_secret = "hga-${local.env}-hub-token"
  hub_dir      = "${path.module}/../../hub"
  # The branch the hub follows (cluster-values/hub.yaml).
  revision = try(local.values.revision, "main")
}

resource "helm_release" "controller" {
  count            = local.role == "hub" ? 1 : 0
  name             = "hga-controller"
  chart            = "${path.module}/../../charts/harness-gitops-agent-controller"
  namespace        = "hga-system"
  create_namespace = true
  wait             = true
  values           = [file("${local.hub_dir}/controller.yaml")]

  depends_on = [terraform_data.hub_cluster]
}

# Destroyed before the controller (depends_on), so the controller is still
# there to deregister the agent in Harness when its object goes.
resource "helm_release" "agent" {
  count            = local.role == "hub" ? 1 : 0
  name             = "hga-hub-agent"
  chart            = "${path.module}/../../charts/gitops-agent"
  namespace        = "hga-hub-agent"
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [
    file("${local.hub_dir}/account-agent.yaml"),
    yamlencode({
      hubCluster = {
        labels = { environment = local.env }
        annotations = {
          repo_url           = local.setup.repo_url
          repo_revision      = local.revision
          harness_account_id = data.harness_platform_current_account.this.account_id
        }
      }
      rootAppSet = {
        repoURL        = local.setup.repo_url
        targetRevision = local.revision
      }
      gitopsAgent = {
        harnessAgent = {
          metadata = { name = local.agent_name }
          spec     = { name = local.agent_name, tokenSecretRef = local.token_secret }
        }
        # AppProject default to the platform project; everything this hub
        # bootstraps is filed under it. rootAppSet.project names the same
        # AppProject.
        projectMappings = [{
          name                 = "hub-admin"
          appProject           = "default"
          orgId                = local.setup.org_id
          projectId            = local.setup.project_id
          autoCreateServiceEnv = false
        }]
        harness = {
          # No orgIdentifier or projectIdentifier: ACCOUNT scope requires both
          # omitted, not set to an empty string.
          identity = {
            accountIdentifier = data.harness_platform_current_account.this.account_id
            agentIdentifier   = local.agent_id
          }
        }
        agent = {
          harnessName     = local.agent_name
          existingSecrets = { agentToken = local.token_secret }
        }
      }
    }),
  ]

  # The controller's account-level key, and one org-scoped key per tenant
  # (harness-api-key-<bu>, named by its hub-managed spokes' agent objects).
  set_sensitive = concat(
    [{ name = "apiKeySecret.value", value = local.setup.controller_token, type = "string" }],
    [for bu, token in local.setup.tenant_controller_tokens :
    { name = "apiKeySecret.extra.harness-api-key-${bu}", value = token, type = "string" }],
  )

  depends_on = [helm_release.controller, terraform_data.hub_cluster]
}
