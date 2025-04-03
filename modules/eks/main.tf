resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.cluster_version
  
  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = [var.cluster_security_group_id]
  }
  
  # Enable secrets encryption using KMS
  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }
  
  # Enable control plane logging
  enabled_cluster_log_types = var.cluster_enabled_log_types
  
  # CloudWatch Log Group for EKS control plane logs
  depends_on = [
    aws_cloudwatch_log_group.eks_cluster_logs
  ]
  
  # Add tags
  tags = {
    Name = var.cluster_name
  }
}

resource "aws_cloudwatch_log_group" "eks_cluster_logs" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 90
}

# Create IAM OIDC provider for the cluster
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Node groups with launch templates
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups
  
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  
  # Use launch template for advanced customization
  launch_template {
    id      = aws_launch_template.node_group[each.key].id
    version = aws_launch_template.node_group[each.key].latest_version
  }
  
  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }
  
  # Node update strategy
  update_config {
    max_unavailable = each.value.max_unavailable != null ? each.value.max_unavailable : 1
  }
  
  # Optional: Add labels and taints
  labels = each.value.labels
  
  # Add tags
  tags = {
    Name = "${var.cluster_name}-${each.key}"
    "k8s.io/cluster-autoscaler/enabled" = each.value.enable_cluster_autoscaler ? "true" : "false"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = each.value.enable_cluster_autoscaler ? "owned" : "false"
  }
  
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# Launch templates for node groups
resource "aws_launch_template" "node_group" {
  for_each = var.node_groups
  
  name                   = "${var.cluster_name}-${each.key}"
  description            = "Launch template for EKS managed node group ${each.key}"
  update_default_version = true
  
  instance_type = each.value.instance_types[0]
  
  # Enable detailed monitoring
  monitoring {
    enabled = true
  }
  
  # EBS optimized instance by default
  ebs_optimized = true
  
  block_device_mappings {
    device_name = "/dev/xvda"
    
    ebs {
      volume_size           = each.value.disk_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }
  
  # Enable SSM session manager 
  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
    http_tokens                 = "required"  # IMDSv2 required for security
  }
  
  tag_specifications {
    resource_type = "instance"
    
    tags = merge(
      {
        Name = "${var.cluster_name}-${each.key}"
      },
      each.value.instance_tags != null ? each.value.instance_tags : {}
    )
  }
  
  user_data = base64encode(
    <<-EOT
    #!/bin/bash
    set -o xtrace
    /etc/eks/bootstrap.sh ${var.cluster_name} ${each.value.bootstrap_extra_args != null ? each.value.bootstrap_extra_args : ""}
    EOT
  )
  
  tags = {
    Name = "${var.cluster_name}-${each.key}-lt"
  }
}

# Fargate Profile (if needed)
resource "aws_eks_fargate_profile" "main" {
  for_each = var.fargate_profiles != null ? var.fargate_profiles : {}
  
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = each.key
  pod_execution_role_arn = each.value.pod_execution_role_arn
  subnet_ids             = var.subnet_ids
  
  selector {
    namespace = each.value.namespace
    labels    = each.value.labels
  }
  
  tags = {
    Name = "${var.cluster_name}-fargate-${each.key}"
  }
}

# Outputs
output "cluster_id" {
  value = aws_eks_cluster.main.id
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  value = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}