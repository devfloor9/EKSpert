provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Configure providers after EKS cluster is created
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

locals {
  cluster_name = "${var.project}-${var.environment}"
  vpc_name     = "${var.project}-${var.environment}"
}

# VPC and networking module
module "networking" {
  source = "./modules/networking"
  
  vpc_name             = local.vpc_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  
  # Enable VPC flow logs
  enable_flow_logs     = true
  flow_logs_group_name = "/aws/vpc/${local.vpc_name}/flow-logs"
  
  # VPC Endpoints for private cluster
  enable_vpc_endpoints = true
}

# Core IAM roles and permissions module
module "iam" {
  source = "./modules/iam"
  
  cluster_name = local.cluster_name
}

# Security module (KMS keys, security groups)
module "security" {
  source = "./modules/security"
  
  cluster_name = local.cluster_name
  vpc_id       = module.networking.vpc_id
}

# EKS module
module "eks" {
  source = "./modules/eks"
  
  cluster_name                    = local.cluster_name
  cluster_version                 = var.kubernetes_version
  vpc_id                          = module.networking.vpc_id
  subnet_ids                      = module.networking.private_subnet_ids
  
  # IAM
  cluster_role_arn               = module.iam.cluster_role_arn
  node_role_arn                  = module.iam.node_role_arn
  
  # Security
  cluster_security_group_id      = module.security.cluster_security_group_id
  node_security_group_id         = module.security.node_security_group_id
  
  # KMS for secrets encryption
  kms_key_arn                    = module.security.kms_key_arn
  
  # Node groups with launch templates
  node_groups                    = var.node_groups
  
  # Private cluster configuration
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = var.environment == "production" ? false : true
  public_access_cidrs             = var.environment == "production" ? ["YOUR_IP/32"] : ["0.0.0.0/0"]
  
  # Enable control plane logging
  cluster_enabled_log_types      = [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ]
}

# EKS Add-ons module
module "addons" {
  source = "./modules/addons"
  
  depends_on = [module.eks]
  
  cluster_name         = module.eks.cluster_name
  cluster_endpoint     = module.eks.cluster_endpoint
  cluster_ca_data      = module.eks.cluster_certificate_authority_data
  oidc_provider_arn    = module.eks.oidc_provider_arn
  vpc_id               = module.networking.vpc_id
  
  # Enable AWS EKS addons
  enable_vpc_cni                  = true
  enable_kube_proxy               = true
  enable_coredns                  = true
  enable_ebs_csi_driver           = true
  
  # Enable community addons
  enable_aws_load_balancer_controller = true
  enable_external_dns               = true
  enable_cluster_autoscaler         = true
  enable_metrics_server             = true
  enable_aws_node_termination_handler = true
  enable_cert_manager               = true
}

# Monitoring module (Prometheus + Grafana)
module "monitoring" {
  source = "./modules/monitoring"
  
  depends_on = [module.eks, module.addons]
  
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  namespace         = "monitoring"
  grafana_admin_password = var.grafana_admin_password
  
  # Enable Prometheus Operator, Grafana, AlertManager
  enable_prometheus_operator = true
  enable_grafana             = true
  enable_alertmanager        = true
  
  # Performance monitoring and cost management
  enable_kube_state_metrics  = true
  enable_node_exporter       = true
  enable_kubecost            = true
}

# Logging module (Fluent Bit + Elasticsearch)
module "logging" {
  source = "./modules/logging"
  
  depends_on = [module.eks, module.addons]
  
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.private_subnet_ids
  namespace         = "logging"
  
  # OpenSearch (Amazon ES) configuration
  opensearch_domain_name     = "${var.project}-${var.environment}-logs"
  opensearch_instance_type   = "m6g.large.elasticsearch"
  opensearch_instance_count  = 3
  opensearch_volume_size     = 100
  
  # Enable enhanced logging features
  enable_opensearch_dashboard = true
  enable_fluent_bit           = true
}

# Backup and Disaster Recovery module
module "backup" {
  source = "./modules/backup"
  
  depends_on = [module.eks, module.addons]
  
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  
  # Enable Velero for Kubernetes resource backup
  enable_velero                = true
  velero_backup_bucket_name    = "${var.project}-${var.environment}-velero-backups"
  schedule_backups             = true
  backup_schedule              = "0 1 * * *"  # Daily at 1 AM
  backup_retention_period_days = 30
}