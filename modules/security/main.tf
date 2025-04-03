# KMS key for EKS secrets encryption
resource "aws_kms_key" "eks" {
  description             = "${var.cluster_name} EKS Secret Encryption Key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow EKS service to use the key"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

# EKS cluster security group
resource "aws_security_group" "cluster_sg" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS control plane"
  vpc_id      = var.vpc_id
  
  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

resource "aws_security_group_rule" "cluster_egress" {
  description       = "Allow all outbound traffic from the EKS control plane"
  security_group_id = aws_security_group.cluster_sg.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# EKS node security group
resource "aws_security_group" "node_sg" {
  name        = "${var.cluster_name}-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id
  
  tags = {
    Name = "${var.cluster_name}-node-sg"
  }
}

resource "aws_security_group_rule" "node_egress" {
  description       = "Allow all outbound traffic from the EKS nodes"
  security_group_id = aws_security_group.node_sg.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Allow nodes to communicate with each other
resource "aws_security_group_rule" "node_ingress_self" {
  description       = "Allow nodes to communicate with each other"
  security_group_id = aws_security_group.node_sg.id
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  self              = true
}

# Allow cluster to communicate with nodes
resource "aws_security_group_rule" "cluster_to_node" {
  description              = "Allow cluster to communicate with nodes"
  security_group_id        = aws_security_group.node_sg.id
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.cluster_sg.id
}

# Allow nodes to communicate with cluster
resource "aws_security_group_rule" "node_to_cluster" {
  description              = "Allow nodes to communicate with cluster"
  security_group_id        = aws_security_group.cluster_sg.id
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.node_sg.id
}

data "aws_caller_identity" "current" {}

# Outputs to reference elsewhere
output "kms_key_arn" {
  value = aws_kms_key.eks.arn
}

output "cluster_security_group_id" {
  value = aws_security_group.cluster_sg.id
}

output "node_security_group_id" {
  value = aws_security_group.node_sg.id
}