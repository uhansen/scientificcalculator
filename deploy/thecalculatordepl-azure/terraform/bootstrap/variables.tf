variable "location" {
  description = "Azure region for the Terraform state resources."
  type        = string
  default     = "denmarkeast"
}

variable "state_resource_group_name" {
  description = "Resource group dedicated to Terraform state resources."
  type        = string
  default     = "rg-thecalculatorspin-tfstate"
}

variable "state_storage_account_name" {
  description = "Globally unique Azure Storage Account name for Terraform state (lowercase letters/numbers, 3-24 chars)."
  type        = string
}

variable "state_container_name" {
  description = "Blob container name for Terraform state."
  type        = string
  default     = "tfstate"
}

variable "tags" {
  description = "Additional tags for backend resources."
  type        = map(string)
  default     = {}
}
