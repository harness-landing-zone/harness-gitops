resource "harness_platform_connector_github" "this" {
  identifier      = "hga_github"
  name            = "hga_github"
  org_id          = local.project_scope.org_id
  project_id      = local.project_scope.project_id
  url             = "https://github.com/${var.github_org}"
  connection_type = "Account"
  validation_repo = "harness-gitops"

  credentials {
    http {
      github_app {
        application_id  = var.github_app_id
        installation_id = var.github_app_installation_id
        private_key_ref = harness_platform_secret_file.github_app_key.id
      }
    }
  }

  api_authentication {
    github_app {
      application_id  = var.github_app_id
      installation_id = var.github_app_installation_id
      private_key_ref = harness_platform_secret_file.github_app_key.id
    }
  }
}

# Anonymous: the controller image is public. Anonymous pulls are rate-limited.
resource "harness_platform_connector_docker" "dockerhub" {
  identifier = "hga_dockerhub"
  name       = "hga_dockerhub"
  org_id     = local.project_scope.org_id
  project_id = local.project_scope.project_id
  type       = "DockerHub"
  url        = "https://index.docker.io/v2/"
}

resource "harness_platform_connector_kubernetes" "hub" {
  identifier = "hga_test_hub"
  name       = "hga_test_hub"
  org_id     = local.project_scope.org_id
  project_id = local.project_scope.project_id

  inherit_from_delegate {
    delegate_selectors = [var.hub_delegate_name]
  }
}
