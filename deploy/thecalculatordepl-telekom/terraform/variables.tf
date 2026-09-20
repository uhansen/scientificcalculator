variable "project" {
  description = "Project tag/name prefix."
  type        = string
  default     = "scientificcalculator"
}

variable "environment" {
  description = "Environment name used in descriptions and tags."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the CCE cluster to create or reuse."
  type        = string
  default     = "thecalculatorspin-cce"
}

variable "cluster_description" {
  description = "Description for a Terraform-created CCE cluster."
  type        = string
  default     = "SpinKube calculator deployment on Telekom CCE"
}

variable "existing_cluster_id" {
  description = "Reuse an existing CCE cluster by ID instead of creating one."
  type        = string
  default     = ""
}

variable "existing_cluster_name" {
  description = "Reuse an existing CCE cluster by name instead of creating one."
  type        = string
  default     = ""
}

variable "cluster_flavor" {
  description = "CCE control-plane flavor ID."
  type        = string
  default     = "cce.s1.small"
}

variable "cluster_version" {
  description = "CCE Kubernetes version for new clusters."
  type        = string
  default     = "v1.30"
}

variable "vpc_id" {
  description = "Existing VPC ID for the CCE cluster."
  type        = string
}

variable "subnet_id" {
  description = "Existing subnet network ID for the CCE cluster and node pool."
  type        = string
}

variable "api_access_trustlist" {
  description = "CIDR blocks allowed to access the public CCE API."
  type        = list(string)
  default     = []
}

variable "timezone" {
  description = "Timezone for new clusters."
  type        = string
  default     = "UTC"
}

variable "node_pool_name" {
  description = "Node pool name for Terraform-created clusters."
  type        = string
  default     = ""
}

variable "node_flavor" {
  description = "CCE node flavor ID for Terraform-created clusters."
  type        = string
  default     = "s3.large.2"
}

variable "node_os" {
  description = "Node OS image for the node pool."
  type        = string
  default     = "HCE OS 2.0"
}

variable "node_count" {
  description = "Initial node count for Terraform-created clusters."
  type        = number
  default     = 3
}

variable "availability_zone" {
  description = "Availability zone for the node pool."
  type        = string
}

variable "ssh_key_name" {
  description = "Existing OTC key pair name for node access."
  type        = string
}

variable "root_volume_size" {
  description = "Root volume size in GiB for CCE nodes."
  type        = number
  default     = 40
}

variable "root_volume_type" {
  description = "Root volume type for CCE nodes."
  type        = string
  default     = "SSD"
}

variable "data_volume_size" {
  description = "Data volume size in GiB for CCE nodes."
  type        = number
  default     = 100
}

variable "data_volume_type" {
  description = "Data volume type for CCE nodes."
  type        = string
  default     = "SSD"
}

variable "kubeconfig_duration" {
  description = "Lifetime of the generated kubeconfig in days; -1 means about five years."
  type        = number
  default     = -1
}
