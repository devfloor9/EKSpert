# Create namespace for backup tools
resource "kubernetes_namespace" "velero" {
  count = var.enable_velero ? 1 : 0
  
  metadata {
    name = "velero"
  }
}

# Create S3 bucket for backups
resource "aws_s3_bucket" "velero_backups" {
  count = var.enable_velero ? 1 : 0
  
  bucket = var.velero_backup_bucket_name
  
  tags = {
    Name = var.velero_backup_bucket_name
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "velero_backups" {
  count = var.enable_velero ? 1 : 0
  
  bucket = aws_s3_bucket.velero_backups[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "velero_backups" {
  count = var.enable_velero ? 1 : 0
  
  bucket = aws_s3_bucket.velero_backups[0].id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Create lifecycle policy for backups
resource "aws_s3_bucket_lifecycle_configuration" "velero_backups" {
  count = var.enable_velero ? 1 : 0
  
  bucket = aws_s3_bucket.velero_backups[0].id
  
  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    
    expiration {
      days = var.backup_retention_period_days
    }
  }
}

# Create IRSA for Velero
module "velero_irsa" {
  count = var.enable_velero ? 1 : 0
  
  source = "../addons/irsa"
  
  role_name          = "${var.cluster_name}-velero"
  namespace          = "velero"
  service_account    = "velero"
  oidc_provider_arn  =  var.oidc_provider_arn
  
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          "${aws_s3_bucket.velero_backups[0].arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.velero_backups[0].arn
        ]
      }
    ]
  })
}

# Deploy Velero using Helm
resource "helm_release" "velero" {
  count = var.enable_velero ? 1 : 0
  
  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  namespace  = "velero"
  version    = var.velero_version
  
  values = [
    <<-EOF
    serviceAccount:
      server:
        create: true
        name: velero
        annotations:
          eks.amazonaws.com/role-arn: ${module.velero_irsa[0].role_arn}
    
    configuration:
      provider: aws
      backupStorageLocation:
        bucket: ${aws_s3_bucket.velero_backups[0].id}
        config:
          region: ${data.aws_region.current.name}
      volumeSnapshotLocation:
        config:
          region: ${data.aws_region.current.name}
    
    initContainers:
      - name: velero-plugin-for-aws
        image: velero/velero-plugin-for-aws:v1.7.0
        imagePullPolicy: IfNotPresent
        volumeMounts:
          - mountPath: /target
            name: plugins
    
    # Configure backup schedule if enabled
    schedules:
      daily-backup:
        schedule: "${var.backup_schedule}"
        template:
          ttl: "${var.backup_retention_period_days * 24}h0m0s"
          includedNamespaces:
          - '*'
          excludedNamespaces:
          - kube-system
          - velero
          - monitoring
          - logging
        useOwnerReferencesInBackup: false
        # Use velero's restic integration for persistent volume backup
        defaultVolumesToRestic: ${var.schedule_backups ? "true" : "false"}
    EOF
  ]
  
  depends_on = [
    kubernetes_namespace.velero,
    aws_s3_bucket.velero_backups,
    module.velero_irsa
  ]
}

data "aws_region" "current" {}