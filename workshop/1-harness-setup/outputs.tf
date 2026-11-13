output "delegate_token" {
  description = "Delegate token for the hub delegate. Read with: tofu output -raw delegate_token"
  value       = harness_platform_delegatetoken.hub.value
  sensitive   = true
}

output "delegate_install_command" {
  description = "Installs the hub delegate. Replace the token placeholder before running."
  value       = <<-EOT
    helm repo add harness-delegate https://app.harness.io/storage/harness-download/delegate-helm-chart/
    helm repo update harness-delegate
    helm upgrade -i ${var.hub_delegate_name} --namespace harness-delegate-ng --create-namespace \
      harness-delegate/harness-delegate-ng \
      --set delegateName=${var.hub_delegate_name} \
      --set accountId=${var.account_id} \
      --set delegateToken="$(tofu output -raw delegate_token)" \
      --set managerEndpoint=https://app.harness.io \
      --set upgrader.enabled=true
  EOT
}

output "github_connector_ref" {
  value = harness_platform_connector_github.this.id
}
