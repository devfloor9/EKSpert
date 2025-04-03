output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "The endpoint URL for the EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the cluster"
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the created private subnets"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the created public subnets"
  value       = module.networking.public_subnet_ids
}

output "opensearch_endpoint" {
  description = "Endpoint for the OpenSearch cluster"
  value       = module.logging.opensearch_endpoint
}

output "kubeconfig_command" {
  description = "kubectl command to update kubeconfig for the created cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "grafana_endpoint" {
  description = "Endpoint for Grafana dashboard"
  value       = "kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
}

output "prometheus_endpoint" {
  description = "Endpoint for Prometheus"
  value       = "kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090"
}