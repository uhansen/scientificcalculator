output "cluster_name" {
  description = "Name of the provisioned EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_region" {
  description = "AWS region hosting the EKS cluster."
  value       = var.aws_region
}

output "cluster_endpoint" {
  description = "EKS Kubernetes API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "vpc_id" {
  description = "VPC ID used by the EKS cluster."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs tagged for internet-facing load balancers."
  value       = [for az in local.availability_zones : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs tagged for internal load balancers and worker nodes."
  value       = [for az in local.availability_zones : aws_subnet.private[az].id]
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
  description = "Command to get the public hostname of the generated Envoy/NLB endpoint."
  value       = "kubectl get gateway ${local.envoy_gateway_name} -n ${local.app_namespace} -o jsonpath='{.status.addresses[0].value}'"
}

output "verify_command" {
  description = "Command to verify the calculator through the public Envoy endpoint."
  value       = "curl -H 'Host: ${var.app_host}' \"http://$(kubectl get gateway ${local.envoy_gateway_name} -n ${local.app_namespace} -o jsonpath='{.status.addresses[0].value}')/?calculate=add(2,3)\""
}

output "kubeconfig_update_command" {
  description = "Command to update local kubeconfig for the cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.aws_region}"
}
