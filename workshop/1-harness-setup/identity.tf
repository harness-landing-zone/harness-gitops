# The controller's Harness identity: an account-scope service account that may
# only manage GitOps agents and Argo projects, everywhere in the account.

resource "harness_platform_roles" "controller" {
  identifier = "hga_controller"
  name       = "HGA Controller"
  permissions = [
    "gitops_agent_view",
    "gitops_agent_edit",
    "gitops_agent_delete",
    "gitops_argoproject_view",
    "gitops_argoproject_edit",
    "gitops_argoproject_delete",
  ]
  allowed_scope_levels = ["account"]
}

resource "harness_platform_service_account" "controller" {
  identifier = "hga_controller"
  name       = "HGA Controller"
  email      = "hga_controller@service.harness.io"
  account_id = data.harness_platform_current_account.this.account_id
}

resource "harness_platform_role_assignments" "controller" {
  resource_group_identifier = "_all_resources_including_child_scopes"
  role_identifier           = harness_platform_roles.controller.id
  principal {
    identifier  = harness_platform_service_account.controller.id
    type        = "SERVICE_ACCOUNT"
    scope_level = "account"
  }
}

resource "harness_platform_apikey" "controller" {
  identifier  = "hga_controller"
  name        = "HGA Controller"
  account_id  = data.harness_platform_current_account.this.account_id
  parent_id   = harness_platform_service_account.controller.id
  apikey_type = "SERVICE_ACCOUNT"
}

resource "harness_platform_token" "controller" {
  identifier  = "hga_controller"
  name        = "HGA Controller"
  account_id  = data.harness_platform_current_account.this.account_id
  parent_id   = harness_platform_service_account.controller.id
  apikey_id   = harness_platform_apikey.controller.id
  apikey_type = "SERVICE_ACCOUNT"
}
