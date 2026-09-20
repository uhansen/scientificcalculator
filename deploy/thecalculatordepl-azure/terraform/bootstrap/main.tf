provider "azurerm" {
  features {}
  storage_use_azuread = true
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "state" {
  name     = var.state_resource_group_name
  location = var.location

  tags = merge(
    {
      ManagedBy  = "terraform"
      Repository = "scientificcalculator"
    },
    var.tags,
  )
}

resource "azurerm_storage_account" "state" {
  name                = var.state_storage_account_name
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = merge(
    {
      ManagedBy  = "terraform"
      Repository = "scientificcalculator"
    },
    var.tags,
  )
}

# Terraform's azurerm backend authenticates to blob storage with Azure AD
# (storage_use_azuread = true / use_azuread_auth in backend config), so the
# identity that runs `terraform init`/`apply` needs data-plane access here.
resource "azurerm_role_assignment" "state_contributor" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_storage_container" "state" {
  name                  = var.state_container_name
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  depends_on = [azurerm_role_assignment.state_contributor]
}

output "state_resource_group_name" {
  description = "Resource group holding the Terraform state storage account."
  value       = azurerm_resource_group.state.name
}

output "state_storage_account_name" {
  description = "Name of the Terraform state storage account."
  value       = azurerm_storage_account.state.name
}

output "state_container_name" {
  description = "Name of the Terraform state blob container."
  value       = azurerm_storage_container.state.name
}

output "backend_key_example" {
  description = "Example key path for the main Terraform state."
  value       = "deploy/thecalculatordepl-azure/terraform/terraform.tfstate"
}

output "backend_hcl_snippet" {
  description = "backend.hcl contents for terraform init -backend-config."
  value       = <<-EOT
  resource_group_name = "${azurerm_resource_group.state.name}"
  storage_account_name = "${azurerm_storage_account.state.name}"
  container_name       = "${azurerm_storage_container.state.name}"
  key                  = "deploy/thecalculatordepl-azure/terraform/terraform.tfstate"
  use_azuread_auth     = true
  EOT
}
