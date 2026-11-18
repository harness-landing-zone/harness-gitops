# Connectors and secrets the YAML refers to are created first (depends_on).
# Entities defined by the repo's own YAML, loaded at plan time (never copied).
# The YAML hardcodes orgIdentifier gitops_reference / projectIdentifier
# gitops_admin; replace() rewrites those two lines so changing var.org_id or
# var.project_id still works.
locals {
  harness_dir = "${path.module}/harness"

  yaml = { for name, rel in {
    environment       = "environments/${var.environment_id}.yaml"
    infra_hga_system  = "infrastructure/${var.environment_id}_hga_system.yaml"
    infra_agent       = "infrastructure/${var.environment_id}_account_agent.yaml"
    svc_controller    = "services/hga_controller.yaml"
    svc_account_agent = "services/hga_account_agent.yaml"
    pipeline          = "pipelines/hga_hub_bootstrap.yaml"
    input_set         = "input_sets/hga_hub_bootstrap_${var.environment_id}.yaml"
    } : name => replace(
    replace(file("${local.harness_dir}/${rel}"), "orgIdentifier: gitops_reference", "orgIdentifier: ${var.org_id}"),
    "projectIdentifier: gitops_admin", "projectIdentifier: ${var.project_id}"
  ) }
}

resource "harness_platform_environment" "this" {
  identifier = yamldecode(local.yaml.environment).environment.identifier
  name       = yamldecode(local.yaml.environment).environment.name
  type       = yamldecode(local.yaml.environment).environment.type
  org_id     = local.project_scope.org_id
  project_id = local.project_scope.project_id
  # The verify step must run on the hub's own delegate, the one the connector
  # selects; without a step selector Harness may pick any delegate in the account.
  yaml = replace(local.yaml.environment, "value: hga-test-hub", "value: ${var.hub_delegate_name}")
}

resource "harness_platform_infrastructure" "hga_system" {
  identifier = yamldecode(local.yaml.infra_hga_system).infrastructureDefinition.identifier
  name       = yamldecode(local.yaml.infra_hga_system).infrastructureDefinition.name
  # The API rejects an infrastructure without these ("Unable to process JSON").
  type            = yamldecode(local.yaml.infra_hga_system).infrastructureDefinition.type
  deployment_type = yamldecode(local.yaml.infra_hga_system).infrastructureDefinition.deploymentType
  org_id          = local.project_scope.org_id
  project_id      = local.project_scope.project_id
  env_id          = harness_platform_environment.this.id
  yaml            = local.yaml.infra_hga_system
  depends_on = [
    harness_platform_connector_github.this,
    harness_platform_connector_kubernetes.hub,
    harness_platform_secret_text.github_app,
    harness_platform_secret_text.controller_token,
  ]
}

resource "harness_platform_infrastructure" "account_agent" {
  identifier = yamldecode(local.yaml.infra_agent).infrastructureDefinition.identifier
  name       = yamldecode(local.yaml.infra_agent).infrastructureDefinition.name
  # The API rejects an infrastructure without these ("Unable to process JSON").
  type            = yamldecode(local.yaml.infra_agent).infrastructureDefinition.type
  deployment_type = yamldecode(local.yaml.infra_agent).infrastructureDefinition.deploymentType
  org_id          = local.project_scope.org_id
  project_id      = local.project_scope.project_id
  env_id          = harness_platform_environment.this.id
  yaml            = local.yaml.infra_agent
  depends_on = [
    harness_platform_connector_github.this,
    harness_platform_connector_kubernetes.hub,
    harness_platform_secret_text.github_app,
    harness_platform_secret_text.controller_token,
  ]
}

resource "harness_platform_service" "controller" {
  identifier = yamldecode(local.yaml.svc_controller).service.identifier
  name       = yamldecode(local.yaml.svc_controller).service.name
  # Mirror the YAML, or the next plan shows drift.
  description = yamldecode(local.yaml.svc_controller).service.description
  tags        = [for k, v in yamldecode(local.yaml.svc_controller).service.tags : "${k}:${v}"]
  org_id      = local.project_scope.org_id
  project_id  = local.project_scope.project_id
  yaml        = local.yaml.svc_controller
  depends_on = [
    harness_platform_connector_github.this,
    harness_platform_connector_kubernetes.hub,
    harness_platform_secret_text.github_app,
    harness_platform_secret_text.controller_token,
  ]
}

resource "harness_platform_service" "account_agent" {
  identifier = yamldecode(local.yaml.svc_account_agent).service.identifier
  name       = yamldecode(local.yaml.svc_account_agent).service.name
  # Mirror the YAML, or the next plan shows drift.
  description = yamldecode(local.yaml.svc_account_agent).service.description
  tags        = [for k, v in yamldecode(local.yaml.svc_account_agent).service.tags : "${k}:${v}"]
  org_id      = local.project_scope.org_id
  project_id  = local.project_scope.project_id
  yaml        = replace(local.yaml.svc_account_agent, "https://github.com/harness-landing-zone/harness-gitops.git", jsonencode("${local.github_owner_url}/harness-gitops.git"))
  depends_on = [
    harness_platform_connector_github.this,
    harness_platform_connector_kubernetes.hub,
    harness_platform_secret_text.github_app,
    harness_platform_secret_text.controller_token,
  ]
}

resource "harness_platform_pipeline" "hub_bootstrap" {
  identifier = yamldecode(local.yaml.pipeline).pipeline.identifier
  name       = yamldecode(local.yaml.pipeline).pipeline.name
  # Mirror the YAML, or the next plan shows drift.
  description = yamldecode(local.yaml.pipeline).pipeline.description
  tags        = [for k, v in yamldecode(local.yaml.pipeline).pipeline.tags : "${k}:${v}"]
  org_id      = local.project_scope.org_id
  project_id  = local.project_scope.project_id
  yaml        = local.yaml.pipeline
  depends_on = [
    harness_platform_service.controller,
    harness_platform_service.account_agent,
    harness_platform_infrastructure.hga_system,
    harness_platform_infrastructure.account_agent,
  ]
}

# Every run-time input filled in, so a run is one click.
resource "harness_platform_input_set" "hub_bootstrap" {
  identifier  = yamldecode(local.yaml.input_set).inputSet.identifier
  name        = yamldecode(local.yaml.input_set).inputSet.name
  description = yamldecode(local.yaml.input_set).inputSet.description
  tags        = [for k, v in yamldecode(local.yaml.input_set).inputSet.tags : "${k}:${v}"]
  org_id      = local.project_scope.org_id
  project_id  = local.project_scope.project_id
  pipeline_id = harness_platform_pipeline.hub_bootstrap.id
  yaml        = local.yaml.input_set
}
