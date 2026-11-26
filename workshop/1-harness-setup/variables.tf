variable "org_id" {
  description = "Identifier of the platform organization."
  type        = string
  default     = "gitops_reference"
}

variable "org_name" {
  description = "Display name of the platform organization."
  type        = string
  default     = "GitOps Reference Architecture"
}

variable "project_id" {
  description = "Identifier of the platform's admin project; the hub's platform-admin AppProject maps to it."
  type        = string
  default     = "gitops_admin"
}

variable "project_name" {
  description = "Display name of the admin project."
  type        = string
  default     = "GitOps Admin"
}

variable "business_units" {
  description = "One Harness organization per tenant, keyed by its identifier (lowercase letters and digits only so it is valid in both Harness org IDs and Kubernetes names), with one project per team."
  type = map(object({
    name     = string
    projects = map(string)
  }))
  default = {
    bu1 = {
      name     = "Business Unit 1"
      projects = { team_a = "Team A", team_b = "Team B" }
    }
  }

  validation {
    condition = alltrue(flatten([
      for bu, v in var.business_units : concat(
        [can(regex("^[a-z][a-z0-9]*$", bu))],
        [for id, _ in v.projects : can(regex("^[a-z][a-z0-9_]*$", id))],
      )
    ]))
    error_message = "Tenant identifiers must use lowercase letters and digits only (valid in both Harness and Kubernetes names); project identifiers may also use underscores."
  }
}

variable "environment_id" {
  description = "Environment identifier; names the hub agent (hga-<id>-hub). Lowercase letters and digits only."
  type        = string
  default     = "test"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment_id))
    error_message = "environment_id must use lowercase letters and digits only."
  }
}

variable "github_org" {
  description = "GitHub organization or user that owns the harness-gitops repository the hub follows."
  type        = string
  default     = "harness-landing-zone"
}

variable "gitops_server_host" {
  description = "Harness GitOps service host for your account's cluster (e.g. prod1, prod2, prod3, or app3.harness.io)."
  type        = string
  default     = "https://app.harness.io/prod1/gitops"
}

variable "agent_http_target" {
  description = "Harness GitOps agent HTTP target for your account's cluster."
  type        = string
  default     = "https://app.harness.io/gitops"
}
