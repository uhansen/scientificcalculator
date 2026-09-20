variable "project" {
  description = "Project tag/name prefix."
  type        = string
  default     = "scientificcalculator"
}

variable "location" {
  description = "Azure region for the AKS deployment."
  type        = string
  default     = "denmarkeast"
}

variable "resource_group_name" {
  description = "Resource group for the AKS cluster and its networking."
  type        = string
  default     = "rg-thecalculatorspin-aks"
}

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "thecalculatorspin-aks"
}

variable "environment" {
  description = "Environment name used in tags and naming."
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version to deploy."
  type        = string
  default     = "1.31"
}

variable "authorized_ip_ranges" {
  description = "Allowed CIDR blocks for the public AKS API endpoint."
  type        = list(string)

  validation {
    condition = length(var.authorized_ip_ranges) > 0 && alltrue([
      for cidr in var.authorized_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "authorized_ip_ranges must contain at least one valid CIDR block."
  }
}

variable "vnet_cidr" {
  description = "CIDR block for the VNet."
  type        = string
  default     = "10.60.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0))
    error_message = "vnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "node_subnet_cidr" {
  description = "CIDR block for the AKS node subnet (Azure CNI Overlay only consumes VNet IPs for nodes, not pods)."
  type        = string
  default     = "10.60.1.0/24"
}

variable "pod_cidr" {
  description = "Overlay CIDR used for pod IPs (Azure CNI Overlay)."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR block for Kubernetes Services."
  type        = string
  default     = "10.245.0.0/24"
}

variable "node_vm_size" {
  description = "VM size for the default AKS node pool."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "node_count" {
  description = "Number of nodes in the default AKS node pool."
  type        = number
  default     = 3
}

variable "node_os_disk_size_gb" {
  description = "Default node pool OS disk size in GiB."
  type        = number
  default     = 50
}

variable "tags" {
  description = "Additional tags applied to supported Azure foundation resources."
  type        = map(string)
  default     = {}
}
