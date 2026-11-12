variable "account_id" {
  description = "Harness account id (same value as HARNESS_ACCOUNT_ID)."
  type        = string
}

variable "org_id" {
  description = "Organization identifier."
  type        = string
  default     = "gitops_reference"
}

variable "project_id" {
  description = "Project identifier."
  type        = string
  default     = "gitops_admin"
}

variable "environment_id" {
  description = "Environment identifier; must match harness/environments/<id>.yaml."
  type        = string
  default     = "test"
}

variable "controller_token_secret_id" {
  description = "Project secret holding the controller's service-account token."
  type        = string
  default     = "HGA-Token"
}

variable "github_org" {
  description = "GitHub organization that owns the repo."
  type        = string
  default     = "harness-landing-zone"
}

variable "github_app_id" {
  description = "GitHub App ID."
  type        = string
}

variable "github_app_installation_id" {
  description = "GitHub App installation ID on var.github_org."
  type        = string
}

variable "github_app_private_key_file" {
  description = "Path to the GitHub App private key PEM, as downloaded from GitHub."
  type        = string
}

variable "github_app_private_key_pkcs8_file" {
  description = "Path to the same key converted to PKCS#8 for the Harness GitHub connector. Defaults to github_app_private_key_file."
  type        = string
  default     = null
}

variable "hub_delegate_name" {
  description = "Name of the delegate installed in the hub cluster; the Kubernetes connector selects it."
  type        = string
  default     = "hga-test-hub"
}
