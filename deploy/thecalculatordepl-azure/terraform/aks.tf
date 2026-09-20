resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = replace(var.cluster_name, "_", "-")
  kubernetes_version  = var.kubernetes_version

  identity {
    type = "SystemAssigned"
  }

  # Manual mode keeps the explicit default_node_pool below as the source of
  # truth for node scaling, rather than AKS Node Autoprovisioning (Karpenter).
  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name            = "system"
    vm_size         = var.node_vm_size
    node_count      = var.node_count
    os_disk_size_gb = var.node_os_disk_size_gb
    vnet_subnet_id  = azurerm_subnet.nodes.id
  }

  # Azure CNI Overlay: nodes consume VNet IPs from the node subnet, pods use
  # an overlay CIDR, avoiding VNet IP exhaustion. The Standard load balancer
  # SKU is required for AKS's built-in cloud provider to provision a public
  # Azure Load Balancer for Service type=LoadBalancer without any additional
  # controller.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = cidrhost(var.service_cidr, 10)
    load_balancer_sku   = "standard"
  }

  api_server_access_profile {
    authorized_ip_ranges = var.authorized_ip_ranges
  }

  tags = local.common_tags
}
