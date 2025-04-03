# Create namespace for logging
resource "kubernetes_namespace" "logging" {
  metadata {
    name = var.namespace
    
    labels = {
      name = var.namespace
    }
  }
}

# Create security group for OpenSearch
resource "aws_security_group" "opensearch" {
  name        = "${var.cluster_name}-opensearch-sg"
  description = "Security group for Amazon OpenSearch"
  vpc_id      = var.vpc_id
  
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.cluster_name}-opensearch-sg"
  }
}

# Create OpenSearch Domain (formerly Elasticsearch Service)
resource "aws_opensearch_domain" "logging" {
  domain_name     = var.opensearch_domain_name
  engine_version  = "OpenSearch_2.5"
  
  cluster_config {
    instance_type  = var.opensearch_instance_type
    instance_count = var.opensearch_instance_count
    
    zone_awareness_enabled = var.opensearch_instance_count > 1
    
    zone_awareness_config {
      availability_zone_count = var.opensearch_instance_count >= 3 ? 3 : 2
    }
  }
  
  ebs_options {
    ebs_enabled = true
    volume_size = var.opensearch_volume_size
    volume_type = "gp3"
  }
  
  encrypt_at_rest {
    enabled = true
  }
  
  node_to_node_encryption {
    enabled = true
  }
  
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }
  
  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    
    master_user_options {
      master_user_name     = var.opensearch_master_user
      master_user_password = var.opensearch_master_password
    }
  }
  
  vpc_options {
    subnet_ids         = [var.subnet_ids[0]]
    security_group_ids = [aws_security_group.opensearch.id]
  }
  
  access_policies = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "es:*",
      "Resource": "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.opensearch_domain_name}/*",
      "Condition": {
        "IpAddress": {
          "aws:VpcSourceIp": "${data.aws_vpc.selected.cidr_block}"
        }
      }
    }
  ]
}
POLICY
  
  tags = {
    Domain = var.opensearch_domain_name
  }
  
  # To avoid race condition issues during initial creation/setup
  depends_on = [aws_security_group.opensearch]
}

# Create IRSA for Fluent Bit
module "fluent_bit_irsa" {
  source = "../addons/irsa"
  
  role_name          = "${var.cluster_name}-fluent-bit"
  namespace          = var.namespace
  service_account    = "fluent-bit"
  oidc_provider_arn  = var.oidc_provider_arn
  
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "es:ESHttp*"
        ]
        Resource = "${aws_opensearch_domain.logging.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Deploy Fluent Bit using Helm for log collection
resource "helm_release" "fluent_bit" {
  count = var.enable_fluent_bit ? 1 : 0
  
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = var.fluent_bit_version
  
  values = [
    <<-EOF
    serviceAccount:
      create: true
      name: fluent-bit
      annotations:
        eks.amazonaws.com/role-arn: ${module.fluent_bit_irsa.role_arn}
        
    config:
      service: |
        [SERVICE]
            Flush           5
            Daemon          Off
            Log_Level       info
            Parsers_File    parsers.conf
            HTTP_Server     On
            HTTP_Listen     0.0.0.0
            HTTP_Port       2020
            Health_Check    On
            
      inputs: |
        [INPUT]
            Name             tail
            Path             /var/log/containers/*.log
            Parser           docker
            Tag              kube.*
            Refresh_Interval 10
            Mem_Buf_Limit    5MB
            Skip_Long_Lines  On
            
      filters: |
        [FILTER]
            Name           kubernetes
            Match          kube.*
            Merge_Log      On
            Keep_Log       Off
            K8S-Logging.Parser    On
            K8S-Logging.Exclude   Off
            
        [FILTER]
            Name           grep
            Match          *
            Exclude        $kubernetes['namespace_name'] fluent-bit
            
      outputs: |
        [OUTPUT]
            Name            es
            Match           *
            Host            ${aws_opensearch_domain.logging.endpoint}
            Port            443
            TLS             On
            AWS_Auth        On
            AWS_Region      ${data.aws_region.current.name}
            Index           kubernetes_cluster
            Replace_Dots    On
            Suppress_Type_Name On
            Logstash_Format On
            Logstash_Prefix kubernetes
            
        [OUTPUT]
            Name             cloudwatch
            Match            *
            region           ${data.aws_region.current.name}
            log_group_name   /aws/eks/${var.cluster_name}/containers
            log_stream_prefix $kubernetes['namespace_name'].$kubernetes['pod_name'].$kubernetes['container_name']
            auto_create_group true
    EOF
  ]
  
  depends_on = [
    aws_opensearch_domain.logging
  ]
}

# Deploy OpenSearch Dashboards
resource "helm_release" "opensearch_dashboards" {
  count = var.enable_opensearch_dashboard ? 1 : 0
  
  name       = "opensearch-dashboards"
  repository = "https://opensearch-project.github.io/helm-charts/"
  chart      = "opensearch-dashboards"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = var.opensearch_dashboards_version
  
  values = [
    <<-EOF
    opensearchHosts: "https://${aws_opensearch_domain.logging.endpoint}"
    config:
      opensearch.ssl.verificationMode: none
      
    serviceAccount:
      create: true
      name: opensearch-dashboards
      
    extraEnvs:
      - name: OPENSEARCH_USERNAME
        value: ${var.opensearch_master_user}
      - name: OPENSEARCH_PASSWORD
        value: ${var.opensearch_master_password}
      
    service:
      type: ClusterIP
    
    ingress:
      enabled: true
      ingressClassName: alb
      annotations:
        alb.ingress.kubernetes.io/scheme: internal
        alb.ingress.kubernetes.io/target-type: ip
        alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
        alb.ingress.kubernetes.io/ssl-redirect: "443"
        alb.ingress.kubernetes.io/healthcheck-path: /app/home
      hosts:
        - host: opensearch-dashboards.${var.cluster_name}.internal
          paths:
            - path: /
              pathType: Prefix
    EOF
  ]
  
  depends_on = [
    aws_opensearch_domain.logging
  ]
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_vpc" "selected" {
  id = var.vpc_id
}