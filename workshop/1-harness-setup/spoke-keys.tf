# Spokes that run their own controller. Each gets its own Harness key, scoped
# to its business unit's org, so no spoke holds a key that reaches beyond its
# org or that another spoke shares. OpenTofu also makes the spoke's k3d cluster
# and writes its connection and key into OpenBao on the hub (k3d-cluster/k3d.sh),
# as it would write AWS Secrets Manager on EKS. No Harness secret: nothing in
# Harness reads the key. Registering the spoke in GitOps stays a commit of
# fleet-members/<name>.yaml.
variable "spokes" {
  description = "Spokes with their own controller: spoke name (its fleet-member name) => business unit (a key of local.business_units)."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for name in keys(var.spokes) : can(regex("^spoke-[a-z0-9]([-a-z0-9]*[a-z0-9])?$", name))])
    error_message = "Every spoke name must be a DNS label starting with spoke- (it names the k3d cluster and the OpenBao paths)."
  }
}

locals {
  spoke_ids    = { for name, bu in var.spokes : name => "hga_agent_${replace(name, "-", "_")}" }
  spoke_script = abspath("${path.module}/k3d-cluster/k3d.sh")
}

resource "harness_platform_service_account" "spoke_agent" {
  for_each   = var.spokes
  identifier = local.spoke_ids[each.key]
  name       = "HGA Agent ${each.key}"
  email      = "${local.spoke_ids[each.key]}@service.harness.io"
  account_id = var.account_id
  org_id     = harness_platform_organization.bu[each.value].id
}

# The BU controller's role: the same rights, only inside the BU's org.
resource "harness_platform_role_assignments" "spoke_agent" {
  for_each                  = var.spokes
  org_id                    = harness_platform_organization.bu[each.value].id
  resource_group_identifier = "_all_resources_including_child_scopes"
  role_identifier           = harness_platform_roles.bu_controller[each.value].id
  principal {
    identifier  = harness_platform_service_account.spoke_agent[each.key].id
    type        = "SERVICE_ACCOUNT"
    scope_level = "organization"
  }
}

resource "harness_platform_apikey" "spoke_agent" {
  for_each    = var.spokes
  identifier  = local.spoke_ids[each.key]
  name        = "HGA Agent ${each.key}"
  account_id  = var.account_id
  org_id      = harness_platform_organization.bu[each.value].id
  parent_id   = harness_platform_service_account.spoke_agent[each.key].id
  apikey_type = "SERVICE_ACCOUNT"
}

resource "harness_platform_token" "spoke_agent" {
  for_each    = var.spokes
  identifier  = local.spoke_ids[each.key]
  name        = "HGA Agent ${each.key}"
  account_id  = var.account_id
  org_id      = harness_platform_organization.bu[each.value].id
  parent_id   = harness_platform_service_account.spoke_agent[each.key].id
  apikey_id   = harness_platform_apikey.spoke_agent[each.key].id
  apikey_type = "SERVICE_ACCOUNT"
}

# The spoke's k3d cluster, its connection in OpenBao at clusters/<name>.
# Destroy provisioners may only read self, so the name and script ride in input.
resource "terraform_data" "spoke_cluster" {
  for_each = var.spokes
  input = {
    name   = each.key
    script = local.spoke_script
  }

  provisioner "local-exec" {
    command = "\"${self.input.script}\" spoke ${self.input.name}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"${self.input.script}\" down ${self.input.name}"
  }
}

# The local stand-in for aws_secretsmanager_secret_version: the key in OpenBao
# at harness-api-keys/<name>, property api_key. It reaches the script only
# through its environment, and a new token is stored again. Dev-mode OpenBao
# forgets it on a hub restart; store it again with
# tofu apply -replace='terraform_data.spoke_key["<name>"]'.
resource "terraform_data" "spoke_key" {
  for_each         = var.spokes
  triggers_replace = harness_platform_token.spoke_agent[each.key].value

  provisioner "local-exec" {
    command = "\"${local.spoke_script}\" store-key ${each.key}"
    environment = {
      HARNESS_API_KEY = harness_platform_token.spoke_agent[each.key].value
    }
  }

  depends_on = [terraform_data.spoke_cluster]
}
