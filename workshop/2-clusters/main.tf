# One workspace per cluster: the workspace name is the cluster name, and
# cluster-values/<workspace>.yaml says what it is. A missing file fails here
# (the default workspace has none). k3d.sh does the cluster work; this decides
# what to run and holds the Harness side.
locals {
  values = yamldecode(file("${path.module}/cluster-values/${terraform.workspace}.yaml"))
  name   = terraform.workspace
  role   = try(local.values.role, "")
  bu     = try(local.values.bu, "")
  # Only the hub has one. try(): validate reads it in every workspace.
  delegate = try(local.values.delegateName, "")
  script   = abspath("${path.module}/k3d.sh")
  # The spoke's own Harness identity.
  id = "hga_agent_${replace(local.name, "-", "_")}"
  # Where the spoke's key goes in OpenBao (the AWS Secrets Manager secret name
  # on EKS). The member file's harnessSecretName must name the same path.
  secret = coalesce(try(local.values.harnessSecretName, null), "harness-api-keys/${local.name}")
}

# The values file, checked before anything runs. Names reach k3d, Helm and the
# shell, so they are checked here too.
resource "terraform_data" "values" {
  lifecycle {
    precondition {
      condition     = contains(["hub", "spoke"], local.role)
      error_message = "cluster-values/${local.name}.yaml: role must be hub or spoke."
    }
    precondition {
      condition     = local.role != "hub" || local.name == "hub"
      error_message = "The hub's workspace must be named hub."
    }
    precondition {
      condition     = local.role != "hub" || can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", local.delegate))
      error_message = "cluster-values/hub.yaml: delegateName must be a DNS label."
    }
    precondition {
      condition     = local.role != "spoke" || can(regex("^spoke-[a-z0-9]([-a-z0-9]*[a-z0-9])?$", local.name))
      error_message = "A spoke's workspace must be named spoke-<name> (a DNS label)."
    }
    precondition {
      condition     = local.role != "spoke" || local.bu != ""
      error_message = "cluster-values/${local.name}.yaml: a spoke needs bu."
    }
    # Under harness-api-keys/ only: a key must never overwrite a cluster
    # connection (clusters/<name>).
    precondition {
      condition     = local.role != "spoke" || can(regex("^harness-api-keys/[a-z0-9]([-a-z0-9_/]*[a-z0-9])?$", local.secret))
      error_message = "cluster-values/${local.name}.yaml: harnessSecretName must be harness-api-keys/<name> (lowercase letters, digits, -, _, /)."
    }
  }
}

# The hub's k3d cluster. Destroy provisioners may only read self, so the name
# and script ride in input.
resource "terraform_data" "hub_cluster" {
  count = local.role == "hub" ? 1 : 0
  input = {
    name   = local.name
    script = local.script
  }

  provisioner "local-exec" {
    command = "\"${self.input.script}\" hub"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"${self.input.script}\" down ${self.input.name}"
  }

  depends_on = [terraform_data.values]
}

# The delegate token comes from ../1-harness-setup, which made it.
data "terraform_remote_state" "setup" {
  count   = local.role == "hub" ? 1 : 0
  backend = "local"
  config = {
    path = "${path.module}/../1-harness-setup/terraform.tfstate"
  }
}

data "harness_platform_current_account" "this" {}

# The hub's delegate, installed again for a new name or a new hub cluster. The
# token reaches the script only through its environment. Nothing removes the
# delegate on destroy: it goes with the hub cluster.
resource "terraform_data" "delegate" {
  count            = local.role == "hub" ? 1 : 0
  triggers_replace = [local.delegate, terraform_data.hub_cluster[0].id]

  provisioner "local-exec" {
    command = "\"${local.script}\" delegate ${local.delegate}"
    environment = {
      DELEGATE_TOKEN     = data.terraform_remote_state.setup[0].outputs.delegate_token
      HARNESS_ACCOUNT_ID = data.harness_platform_current_account.this.account_id
    }
  }

  depends_on = [terraform_data.hub_cluster]
}

# A spoke runs its own controller, which needs an API key on the spoke. Each
# spoke gets its own key, scoped to its business unit's org, so no spoke holds
# a key that reaches beyond its org or that another spoke shares. No Harness
# secret: nothing in Harness reads it. Registering the spoke in GitOps stays a
# commit of fleet-members/<name>.yaml.

resource "harness_platform_service_account" "spoke_agent" {
  count      = local.role == "spoke" ? 1 : 0
  identifier = local.id
  name       = "HGA Agent ${local.name}"
  email      = "${local.id}@service.harness.io"
  account_id = data.harness_platform_current_account.this.account_id
  org_id     = local.bu

  depends_on = [terraform_data.values]
}

# The BU controller's role (hga_controller_<bu>, from ../1-harness-setup): the
# same rights, only inside the BU's org.
resource "harness_platform_role_assignments" "spoke_agent" {
  count                     = local.role == "spoke" ? 1 : 0
  org_id                    = local.bu
  resource_group_identifier = "_all_resources_including_child_scopes"
  role_identifier           = "hga_controller_${local.bu}"
  principal {
    identifier  = harness_platform_service_account.spoke_agent[0].id
    type        = "SERVICE_ACCOUNT"
    scope_level = "organization"
  }
}

resource "harness_platform_apikey" "spoke_agent" {
  count       = local.role == "spoke" ? 1 : 0
  identifier  = local.id
  name        = "HGA Agent ${local.name}"
  account_id  = data.harness_platform_current_account.this.account_id
  org_id      = local.bu
  parent_id   = harness_platform_service_account.spoke_agent[0].id
  apikey_type = "SERVICE_ACCOUNT"
}

resource "harness_platform_token" "spoke_agent" {
  count       = local.role == "spoke" ? 1 : 0
  identifier  = local.id
  name        = "HGA Agent ${local.name}"
  account_id  = data.harness_platform_current_account.this.account_id
  org_id      = local.bu
  parent_id   = harness_platform_service_account.spoke_agent[0].id
  apikey_id   = harness_platform_apikey.spoke_agent[0].id
  apikey_type = "SERVICE_ACCOUNT"
}

# The spoke's k3d cluster, its connection in OpenBao at clusters/<name>.
# Input as for the hub.
resource "terraform_data" "spoke_cluster" {
  count = local.role == "spoke" ? 1 : 0
  input = {
    name   = local.name
    script = local.script
  }

  provisioner "local-exec" {
    command = "\"${self.input.script}\" spoke ${self.input.name}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"${self.input.script}\" down ${self.input.name}"
  }

  depends_on = [terraform_data.values]
}

# The local stand-in for aws_secretsmanager_secret_version: the key in OpenBao
# at harnessSecretName (local.secret), property api_key. It reaches the script
# only through its environment; a new token or a new path stores it again.
# Dev-mode OpenBao forgets it on a hub restart; store it again with
# tofu apply -replace='terraform_data.spoke_key[0]'.
resource "terraform_data" "spoke_key" {
  count            = local.role == "spoke" ? 1 : 0
  triggers_replace = [harness_platform_token.spoke_agent[0].value, local.secret]

  provisioner "local-exec" {
    command = "\"${local.script}\" store-key ${local.secret}"
    environment = {
      HARNESS_API_KEY = harness_platform_token.spoke_agent[0].value
    }
  }

  depends_on = [terraform_data.spoke_cluster]
}

# The value for harnessSecretName in fleet-members/<name>.yaml.
output "harness_secret_name" {
  value = local.role == "spoke" ? local.secret : null
}
