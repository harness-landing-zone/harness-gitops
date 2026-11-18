resource "harness_platform_organization" "this" {
  identifier = var.org_id
  name       = var.org_name
  tags       = ["purpose:reference-architecture"]
}

resource "harness_platform_project" "this" {
  identifier = var.project_id
  name       = var.project_name
  org_id     = harness_platform_organization.this.id
  tags       = ["purpose:reference-architecture"]
}
