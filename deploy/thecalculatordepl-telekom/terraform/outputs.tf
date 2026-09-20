output "cluster_id" {
  description = "ID of the Telekom/OpenTelekomCloud CCE cluster."
  value       = local.cluster_id
}

output "cluster_name" {
  description = "Name of the Telekom/OpenTelekomCloud CCE cluster."
  value       = local.cluster_name_resolved
}

output "cluster_created" {
  description = "Whether Terraform created the cluster instead of reusing an existing one."
  value       = local.create_cluster
}

output "kubeconfig" {
  description = "Kubeconfig for the target CCE cluster."
  value       = data.opentelekomcloud_cce_cluster_kubeconfig_v3.this.kubeconfig
  sensitive   = true
}
