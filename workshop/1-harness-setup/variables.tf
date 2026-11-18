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
  description = "Environment identifier; names the hub agent (hga-<id>-hub). Lowercase letters and digits only."
  type        = string
  default     = "test"
}

variable "github_org" {
  description = "GitHub organization or user that owns the harness-gitops repository the hub follows."
  type        = string
  default     = "harness-landing-zone"
}
