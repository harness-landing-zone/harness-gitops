# One Harness org per tenant (here a business unit), one project per team.
# The teams are AppProjects mapped onto these projects.
locals {
  bu_projects = merge([
    for bu, v in var.business_units : {
      for id, name in v.projects : "${bu}/${id}" => { org = bu, id = id, name = name }
    }
  ]...)
}

resource "harness_platform_organization" "bu" {
  for_each   = var.business_units
  identifier = each.key
  name       = each.value.name
  tags       = ["purpose:reference-architecture"]
}

resource "harness_platform_project" "team" {
  for_each   = local.bu_projects
  identifier = each.value.id
  name       = each.value.name
  org_id     = harness_platform_organization.bu[each.value.org].id
  tags       = ["purpose:reference-architecture"]
}

# Each tenant's own controller identity: an org-scoped service account that may
# only manage GitOps agents and their project mappings inside that org. Its
# token is the key the hub's controller uses for that tenant's hub-managed
# spokes (apiKeySecretRef harness-api-key-<bu>), so their agents never ride on
# the account-level key.
resource "harness_platform_roles" "bu_controller" {
  for_each   = var.business_units
  identifier = "hga_controller_${each.key}"
  name       = "HGA Controller ${each.key}"
  org_id     = harness_platform_organization.bu[each.key].id
  permissions = [
    "gitops_agent_view",
    "gitops_agent_edit",
    "gitops_agent_delete",
    "gitops_argoproject_view",
    "gitops_argoproject_edit",
    "gitops_argoproject_delete",
  ]
  allowed_scope_levels = ["organization"]
}

resource "harness_platform_service_account" "bu_controller" {
  for_each   = var.business_units
  identifier = "hga_controller_${each.key}"
  name       = "HGA Controller ${each.key}"
  email      = "hga_controller_${each.key}@service.harness.io"
  account_id = var.account_id
  org_id     = harness_platform_organization.bu[each.key].id
}

resource "harness_platform_role_assignments" "bu_controller" {
  for_each                  = var.business_units
  org_id                    = harness_platform_organization.bu[each.key].id
  resource_group_identifier = "_all_resources_including_child_scopes"
  role_identifier           = harness_platform_roles.bu_controller[each.key].id
  principal {
    identifier  = harness_platform_service_account.bu_controller[each.key].id
    type        = "SERVICE_ACCOUNT"
    scope_level = "organization"
  }
}

resource "harness_platform_apikey" "bu_controller" {
  for_each    = var.business_units
  identifier  = "hga_controller_${each.key}"
  name        = "HGA Controller ${each.key}"
  account_id  = var.account_id
  org_id      = harness_platform_organization.bu[each.key].id
  parent_id   = harness_platform_service_account.bu_controller[each.key].id
  apikey_type = "SERVICE_ACCOUNT"
}

resource "harness_platform_token" "bu_controller" {
  for_each    = var.business_units
  identifier  = "hga_controller_${each.key}"
  name        = "HGA Controller ${each.key}"
  account_id  = var.account_id
  org_id      = harness_platform_organization.bu[each.key].id
  parent_id   = harness_platform_service_account.bu_controller[each.key].id
  apikey_id   = harness_platform_apikey.bu_controller[each.key].id
  apikey_type = "SERVICE_ACCOUNT"
}
