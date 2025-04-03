variable "region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "project" {
  description = "Project name"
}

variable "environment" {
  description = "Environment (dev, staging, production)"
}

variable "vpc_cidr" {
  description = "CIDR for VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  default     = "1.28"
}

variable "node_groups" {
  description = "EKS node group configurations"
  type = map(object({
    desired_size   = number
    min_size       = number
    max_size       = number
    instance_types = list(string)
    capacity_type  = string  # ON_DEMAND or SPOT
    disk_size      = number
    labels         = map(string)
    max_unavailable = optional(number)
    instance_tags   = optional(map(string))
    bootstrap_extra_args = optional(string)
    enable_cluster_autoscaler = optional(bool, true)
  }))
}

variable "fargate_profiles" {
  description = "Fargate profile configurations"
  type = map(object({
    namespace   = string
    labels      = map(string)
    pod_execution_role_arn = string
  }))
  default = {}
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  sensitive   = true
}

variable "opensearch_master_user" {
  description = "OpenSearch master username"
  default     = "admin"
}

variable "opensearch_master_password" {
  description = "OpenSearch master password"
  sensitive   = true
}