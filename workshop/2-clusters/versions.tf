terraform {
  required_version = ">= 1.5"

  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.47.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}

# Reads HARNESS_ACCOUNT_ID and HARNESS_PLATFORM_API_KEY from the environment.
provider "harness" {
  endpoint = "https://app.harness.io/gateway"
}

# This workspace's cluster, as k3d.sh merges it into ~/.kube/config.
provider "helm" {
  kubernetes = {
    config_path    = pathexpand("~/.kube/config")
    config_context = "k3d-hga-${local.name}"
  }
}
