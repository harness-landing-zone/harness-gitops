resource "harness_platform_delegatetoken" "hub" {
  name       = "hga_test_hub"
  account_id = var.account_id
  org_id     = local.project_scope.org_id
  project_id = local.project_scope.project_id
}
