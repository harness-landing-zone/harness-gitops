# Workspace hub reads cluster-values/hub.yaml, provisions k3d cluster hga-hub,
# and installs the PE Admin GitOps stack via hub.tf.
locals {
  values = yamldecode(file("${path.module}/cluster-values/${terraform.workspace}.yaml"))
  name   = terraform.workspace
  role   = try(local.values.role, "")
  script = abspath("${path.module}/k3d.sh")
}

resource "terraform_data" "values" {
  lifecycle {
    precondition {
      condition     = local.role == "hub" && local.name == "hub"
      error_message = "Select workspace 'hub' (cluster-values/hub.yaml with role: hub)."
    }
    precondition {
      condition     = can(regex("^[a-z0-9]+$", local.env))
      error_message = "environment_id from ../1-harness-setup must be lowercase letters and digits."
    }
  }
}

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

data "terraform_remote_state" "setup" {
  count   = local.role == "hub" ? 1 : 0
  backend = "local"
  config = {
    path = "${path.module}/../1-harness-setup/terraform.tfstate"
  }
}

data "harness_platform_current_account" "this" {}
