resource "harness_platform_organization" "this" {
  identifier = var.org_id
  name       = "GitOps Reference Architecture"
  tags       = ["purpose:reference-architecture"]
}

resource "harness_platform_project" "this" {
  identifier = var.project_id
  name       = "GitOps Admin"
  org_id     = harness_platform_organization.this.id
  tags       = ["purpose:reference-architecture"]
}
