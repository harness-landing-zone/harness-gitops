locals {
  project_scope = {
    org_id     = harness_platform_organization.this.id
    project_id = harness_platform_project.this.id
  }
}

# The single central key the controller uses.
resource "harness_platform_secret_text" "controller_token" {
  identifier                = var.controller_token_secret_id
  name                      = var.controller_token_secret_id
  org_id                    = local.project_scope.org_id
  project_id                = local.project_scope.project_id
  secret_manager_identifier = "harnessSecretManager"
  value_type                = "Inline"
  value                     = harness_platform_token.controller.value
}

# Read by the controller: one single-line JSON, ids as strings, PEM base64-encoded.
resource "harness_platform_secret_text" "github_app" {
  identifier                = "hga_github_app"
  name                      = "hga_github_app"
  org_id                    = local.project_scope.org_id
  project_id                = local.project_scope.project_id
  secret_manager_identifier = "harnessSecretManager"
  value_type                = "Inline"
  value = jsonencode({
    githubAppID             = var.github_app_id
    githubAppInstallationID = var.github_app_installation_id
    githubAppPrivateKeyB64  = base64encode(file(pathexpand(var.github_app_private_key_file)))
  })
}

# The GitHub connector wants the App key as an encrypted FILE secret in PKCS#8 PEM.
resource "harness_platform_secret_file" "github_app_key" {
  identifier                = "hga_github_app_key"
  name                      = "hga_github_app_key"
  org_id                    = local.project_scope.org_id
  project_id                = local.project_scope.project_id
  secret_manager_identifier = "harnessSecretManager"
  file_path                 = pathexpand(coalesce(var.github_app_private_key_pkcs8_file, var.github_app_private_key_file))
}
