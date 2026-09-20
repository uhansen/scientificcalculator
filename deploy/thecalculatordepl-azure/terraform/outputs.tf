output "cluster_name" {
  description = "Name of the provisioned AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_location" {
  description = "Azure region hosting the AKS cluster."
  value       = var.location
}

output "cluster_fqdn" {
  description = "AKS Kubernetes API server FQDN."
  value       = azurerm_kubernetes_cluster.this.fqdn
}

output "resource_group_name" {
  description = "Resource group hosting the AKS cluster."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "VNet ID used by the AKS cluster."
  value       = azurerm_virtual_network.this.id
}

output "node_subnet_id" {
  description = "Node subnet ID used by the default node pool."
  value       = azurerm_subnet.nodes.id
}

output "gateway_class_name" {
  description = "Envoy GatewayClass name used by the application."
  value       = local.envoy_gateway_class_name
}

output "gateway_name" {
  description = "Gateway API Gateway name used by the application."
  value       = local.envoy_gateway_name
}

output "envoy_gateway_service_lookup" {
  description = "Command to look up the Envoy service generated for the application Gateway."
  value       = "kubectl get svc -n ${local.envoy_gateway_namespace} -l gateway.envoyproxy.io/owning-gateway-namespace=${local.app_namespace},gateway.envoyproxy.io/owning-gateway-name=${local.envoy_gateway_name}"
}

output "envoy_gateway_hostname_lookup" {
  description = "Command to get the public address of the generated Envoy/Azure Load Balancer endpoint."
  value       = "kubectl get gateway ${local.envoy_gateway_name} -n ${local.app_namespace} -o jsonpath='{.status.addresses[0].value}'"
}

output "verify_command" {
  description = "Command to verify the calculator through the public Envoy endpoint."
  value       = "curl -H 'Host: ${var.app_host}' \"http://$(kubectl get gateway ${local.envoy_gateway_name} -n ${local.app_namespace} -o jsonpath='{.status.addresses[0].value}')/?calculate=add(2,3)\""
}

output "kubeconfig_update_command" {
  description = "Command to update local kubeconfig for the cluster."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name} --overwrite-existing"
}
