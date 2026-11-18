# Read by ../2-clusters (workspace hub) from this folder's local state.

output "controller_token" {
  description = "The controller's account-level key (Secret harness-api-key-secret in hga-system)."
  value       = harness_platform_token.controller.value
  sensitive   = true
}

output "tenant_controller_tokens" {
  description = "Each tenant's org-scoped controller key, by tenant (Secret harness-api-key-<bu> in hga-system)."
  value       = { for bu, t in harness_platform_token.bu_controller : bu => t.value }
  sensitive   = true
}

output "environment_id" {
  value = var.environment_id
}

output "org_id" {
  value = harness_platform_organization.this.id
}

output "project_id" {
  value = harness_platform_project.this.id
}

output "repo_url" {
  value = "https://github.com/${var.github_org}/harness-gitops.git"
}
