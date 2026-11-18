variable "account_id" {
  description = "Harness account id (same value as HARNESS_ACCOUNT_ID)."
  type        = string
}

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
  description = "Identifier of the platform's admin project; the hub's AppProject default maps to it."
  type        = string
  default     = "gitops_admin"
}

variable "project_name" {
  description = "Display name of the admin project."
  type        = string
  default     = "GitOps Admin"
}

variable "business_units" {
  description = "One Harness organization per tenant, keyed by its identifier, with one project per team (identifier = display name). The identifiers must match the repository: tenants/<tenant>/, tenant in fleet-members/*.yaml, bu in workshop/2-clusters/cluster-values/*.yaml and projectId in the team files."
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
        [can(regex("^[a-z][a-z0-9_]*$", bu))],
        [for id, _ in v.projects : can(regex("^[a-z][a-z0-9_]*$", id))],
      )
    ]))
    error_message = "Tenant and project identifiers must start with a lowercase letter and use only lowercase letters, digits and underscores."
  }
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
