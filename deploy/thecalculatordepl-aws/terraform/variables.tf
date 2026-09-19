variable "project" {
  description = "Project tag/name prefix."
  type        = string
  default     = "scientificcalculator"
}

variable "aws_region" {
  description = "AWS region for the EKS deployment."
  type        = string
  default     = "eu-north-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "thecalculatorspin-eks"
}

variable "environment" {
  description = "Environment name used in tags and naming."
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version to deploy."
  type        = string
  default     = "1.33"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "Allowed CIDR blocks for the public EKS API endpoint."
  type        = list(string)

  validation {
    condition = length(var.cluster_endpoint_public_access_cidrs) > 0 && alltrue([
      for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "cluster_endpoint_public_access_cidrs must contain at least one valid CIDR block."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "node_instance_types" {
  description = "Managed node group EC2 instance types."
  type        = list(string)
  default     = ["m5.large"]
}

variable "node_ami_type" {
  description = "AMI type for the managed node group."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_desired_size" {
  description = "Desired node count for the managed node group."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum node count for the managed node group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum node count for the managed node group."
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Managed node group root volume size in GiB."
  type        = number
  default     = 50
}

variable "node_capacity_type" {
  description = "Capacity type for the managed node group."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "tags" {
  description = "Additional tags applied to supported AWS foundation resources."
  type        = map(string)
  default     = {}
}
