# Day-0 PE Admin Hub install on k3d-hga-hub:
#   1. Official upstream harness-gitops-agent-controller (0.1.0) in hga-system
#   2. Official upstream gitops-helm (1.3.0) in hga-hub-agent (installs Argo CD
#      CRDs, PE Admin Argo CD, and ACCOUNT HarnessGitopsAgent + project mapping)
#   3. Local charts/hub-bootstrap in hga-hub-agent (API-key Secrets in
#      hga-system, hub-cluster Secret, platform-admin AppProject, root groups
#      ApplicationSet — plain Helm resources, zero hooks)
locals {
  setup              = one(data.terraform_remote_state.setup[*].outputs)
  env                = try(local.setup.environment_id, "")
  agent_name         = "hga-${local.env}-hub"
  agent_id           = "hga_${local.env}_hub"
  token_secret       = "hga-${local.env}-hub-token"
  hub_dir            = "${path.module}/../../hub"
  revision           = try(local.values.revision, "main")
  gitops_server_host  = try(local.setup.gitops_server_host, "https://app.harness.io/prod1/gitops")
  agent_http_target   = try(local.setup.agent_http_target, "https://app.harness.io/gitops")
  harness_helm_repo   = "https://harness.github.io/gitops-helm"
  bootstrap_chart_dir = "${path.module}/../../charts/hub-bootstrap"
  bootstrap_chart_sha = sha256(join("", [
    for f in sort(fileset(local.bootstrap_chart_dir, "**")) :
    filesha256("${local.bootstrap_chart_dir}/${f}")
  ]))
}

resource "helm_release" "controller" {
  count            = local.role == "hub" ? 1 : 0
  name             = "hga-controller"
  repository       = local.harness_helm_repo
  chart            = "harness-gitops-agent-controller"
  version          = "0.1.0"
  namespace        = "hga-system"
  create_namespace = true
  wait             = true
  values           = [file("${local.hub_dir}/controller.yaml")]

  depends_on = [terraform_data.hub_cluster]
}

# Applies Argo CD CRDs + PE Admin Argo CD + ACCOUNT HarnessGitopsAgent.
# wait = false so hub_bootstrap can immediately create the API-key Secret in
# hga-system (allowing the controller to register hga-test-hub and write its
# token) and create AppProject platform-admin + root ApplicationSet groups as
# plain resources once CRDs are in place.
resource "helm_release" "agent" {
  count            = local.role == "hub" ? 1 : 0
  name             = "hga-hub-agent"
  repository       = local.harness_helm_repo
  chart            = "gitops-helm"
  version          = "1.3.0"
  namespace        = "hga-hub-agent"
  create_namespace = true
  wait             = false

  values = [
    file("${local.hub_dir}/account-agent.yaml"),
    yamlencode({
      harnessAgent = {
        metadata = { name = local.agent_name }
        spec     = { name = local.agent_name, tokenSecretRef = local.token_secret }
      }
      projectMappings = [{
        name                 = "hub-admin"
        appProject           = "platform-admin"
        orgId                = local.setup.org_id
        projectId            = local.setup.project_id
        autoCreateServiceEnv = false
      }]
      harness = {
        gitopsServerHost = local.gitops_server_host
        configMap = {
          http = { agentHttpTarget = local.agent_http_target }
        }
        identity = {
          accountIdentifier = data.harness_platform_current_account.this.account_id
          agentIdentifier   = local.agent_id
        }
      }
      agent = {
        harnessName     = local.agent_name
        existingSecrets = { agentToken = local.token_secret }
      }
    }),
  ]

  depends_on = [helm_release.controller, terraform_data.hub_cluster]
}

# Day-0 hub glue: API-key Secrets (account + per-tenant org keys) in hga-system,
# hub-cluster Secret, platform-admin AppProject, and root ApplicationSet groups.
resource "helm_release" "hub_bootstrap" {
  count            = local.role == "hub" ? 1 : 0
  name             = "hga-hub-bootstrap"
  chart            = local.bootstrap_chart_dir
  namespace        = "hga-hub-agent"
  create_namespace = false
  wait             = true
  timeout          = 300

  values = [
    file("${local.hub_dir}/bootstrap.yaml"),
    yamlencode({
      # Triggers Helm upgrade when any local template in charts/hub-bootstrap changes.
      _chartSha = local.bootstrap_chart_sha
      hubCluster = {
        labels = { environment = local.env }
        annotations = {
          repo_url           = local.setup.repo_url
          repo_revision      = local.revision
          harness_account_id = data.harness_platform_current_account.this.account_id
          gitops_server_host = local.gitops_server_host
          agent_http_target  = local.agent_http_target
        }
      }
      rootAppSet = {
        repoURL        = local.setup.repo_url
        targetRevision = local.revision
      }
    }),
  ]

  set_sensitive = concat(
    [{ name = "apiKeySecret.value", value = local.setup.controller_token, type = "string" }],
    [for bu, token in local.setup.tenant_controller_tokens :
    { name = "apiKeySecret.extra.harness-api-key-${bu}", value = token, type = "string" }],
  )

  depends_on = [helm_release.agent]
}
