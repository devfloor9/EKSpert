# Create IRSA for AWS Load Balancer Controller
module "aws_load_balancer_controller_irsa" {
  count = var.enable_aws_load_balancer_controller ? 1 : 0
  
  source  = "./irsa"
  
  role_name          = "${var.cluster_name}-aws-load-balancer-controller"
  namespace          = "kube-system"
  service_account    = "aws-load-balancer-controller"
  oidc_provider_arn  = var.oidc_provider_arn
  
  policy_json = file("${path.module}/policies/aws-load-balancer-controller.json")
}

# Create IRSA for External DNS
module "external_dns_irsa" {
  count = var.enable_external_dns ? 1 : 0
  
  source  = "./irsa"
  
  role_name          = "${var.cluster_name}-external-dns"
  namespace          = "kube-system"
  service_account    = "external-dns"
  oidc_provider_arn  = var.oidc_provider_arn
  
  policy_json = file("${path.module}/policies/external-dns.json")
}

# Create IRSA for Cluster Autoscaler
module "cluster_autoscaler_irsa" {
  count = var.enable_cluster_autoscaler ? 1 : 0
  
  source  = "./irsa"
  
  role_name          = "${var.cluster_name}-cluster-autoscaler"
  namespace          = "kube-system"
  service_account    = "cluster-autoscaler"
  oidc_provider_arn  = var.oidc_provider_arn
  
  policy_json = file("${path.module}/policies/cluster-autoscaler.json")
}

# Create IRSA for AWS Node Termination Handler
module "node_termination_handler_irsa" {
  count = var.enable_aws_node_termination_handler ? 1 : 0
  
  source  = "./irsa"
  
  role_name          = "${var.cluster_name}-node-termination-handler"
  namespace          = "kube-system"
  service_account    = "aws-node-termination-handler"
  oidc_provider_arn  = var.oidc_provider_arn
  
  policy_json = file("${path.module}/policies/node-termination-handler.json")
}

# Install Amazon EKS add-ons
resource "aws_eks_addon" "vpc_cni" {
  count = var.enable_vpc_cni ? 1 : 0
  
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = var.vpc_cni_version
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  count = var.enable_kube_proxy ? 1 : 0
  
  cluster_name                = var.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = var.kube_proxy_version
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  count = var.enable_coredns ? 1 : 0
  
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  addon_version               = var.coredns_version
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.enable_ebs_csi_driver ? 1 : 0
  
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_driver_version
  resolve_conflicts_on_update = "OVERWRITE"
  
  # Service account role for ebs-csi-controller
  service_account_role_arn = module.ebs_csi_irsa[0].role_arn
}

module "ebs_csi_irsa" {
  count = var.enable_ebs_csi_driver ? 1 : 0
  
  source  = "./irsa"
  
  role_name          = "${var.cluster_name}-ebs-csi-controller"
  namespace          = "kube-system"
  service_account    = "ebs-csi-controller-sa"
  oidc_provider_arn  = var.oidc_provider_arn
  
  policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  ]
}

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  count = var.enable_aws_load_balancer_controller ? 1 : 0
  
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.aws_load_balancer_controller_version
  
  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.aws_load_balancer_controller_irsa[0].role_arn
  }
  
  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.coredns,
  ]
}

# External DNS
resource "helm_release" "external_dns" {
  count = var.enable_external_dns ? 1 : 0
  
  name       = "external-dns"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "external-dns"
  namespace  = "kube-system"
  version    = var.external_dns_version
  
  set {
    name  = "provider"
    value = "aws"
  }
  
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  
  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }
  
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_dns_irsa[0].role_arn
  }
  
  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.coredns,
  ]
}

# Cluster Autoscaler
resource "helm_release" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0
  
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = var.cluster_autoscaler_version
  
  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }
  
  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }
  
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }
  
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.cluster_autoscaler_irsa[0].role_arn
  }
  
  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.coredns,
  ]
}

# Metrics Server
resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0
  
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = var.metrics_server_version
  
  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.coredns,
  ]
}

# AWS Node Termination Handler
resource "helm_release" "aws_node_termination_handler" {
  count = var.enable_aws_node_termination_handler ? 1 : 0
  
  name       = "aws-node-termination-handler"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-node-termination-handler"
  namespace  = "kube-system"
  version    = var.aws_node_termination_handler_version
  
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  
  set {
    name  = "serviceAccount.name"
    value = "aws-node-termination-handler"
  }
  
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.node_termination_handler_irsa[0].role_arn
  }
  
  set {
    name  = "awsRegion"
    value = data.aws_region.current.name
  }
  
  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.coredns,
  ]
}

# Cert Manager
resource "helm_release" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0
  
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = var.cert_manager_version
  create_namespace = true
  
  set {
    name  = "installCRDs"
    value = "true"
  }
  
  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.coredns,
  ]
}

# Apply Pod Security Standards
resource "kubectl_manifest" "pod_security_standards" {
  count = var.enable_pod_security_standards ? 1 : 0
  
  yaml_body = <<YAML
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: PodSecurity
  configuration:
    apiVersion: pod-security.admission.config.k8s.io/v1
    kind: PodSecurityConfiguration
    defaults:
      enforce: "baseline"
      enforce-version: "latest"
      audit: "restricted"
      audit-version: "latest"
      warn: "restricted"
      warn-version: "latest"
    exemptions:
      usernames: []
      runtimeClasses: []
      namespaces: [kube-system, cert-manager]
YAML

  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.coredns,
  ]
}

data "aws_region" "current" {}