terraform {
  required_version = ">= 1.5"

  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.47.0"
    }
  }
}

# Reads HARNESS_ACCOUNT_ID and HARNESS_PLATFORM_API_KEY from the environment.
provider "harness" {
  endpoint = "https://app.harness.io/gateway"
}
