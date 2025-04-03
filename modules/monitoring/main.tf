# Create namespace for monitoring
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace
    
    labels = {
      name = var.namespace
    }
  }
}

# Create IRSA for Prometheus
module "prometheus_irsa" {
  source = "../addons/irsa"
  
  role_name          = "${var.cluster_name}-prometheus"
  namespace          = var.namespace
  service_account    = "prometheus-server"
  oidc_provider_arn  = var.oidc_provider_arn
  
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess",
    "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess",
    "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
  ]
}

# Deploy Prometheus Stack using Helm
resource "helm_release" "prometheus_stack" {
  count = var.enable_prometheus_operator ? 1 : 0
  
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = var.prometheus_stack_version
  
  values = [
    <<-EOF
    prometheus:
      prometheusSpec:
        serviceAccountName: prometheus-server
        serviceMonitorSelectorNilUsesHelmValues: false
        podMonitorSelectorNilUsesHelmValues: false
        retention: 15d
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: gp3
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 50Gi
        resources:
          requests:
            memory: 512Mi
            cpu: 500m
          limits:
            memory: 2Gi
            cpu: 1000m
        
    alertmanager:
      enabled: ${var.enable_alertmanager}
      alertmanagerSpec:
        storage:
          volumeClaimTemplate:
            spec:
              storageClassName: gp3
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 10Gi
        resources:
          requests:
            memory: 256Mi
            cpu: 100m
          limits:
            memory: 512Mi
            cpu: 200m
    
    grafana:
      enabled: ${var.enable_grafana}
      adminPassword: ${var.grafana_admin_password}
      persistence:
        enabled: true
        storageClassName: gp3
        size: 10Gi
      resources:
        requests:
          memory: 256Mi
          cpu: 100m
        limits:
          memory: 512Mi
          cpu: 200m
      dashboardProviders:
        dashboardproviders.yaml:
          apiVersion: 1
          providers:
          - name: 'kubernetes'
            orgId: 1
            folder: 'Kubernetes'
            type: file
            disableDeletion: false
            editable: true
            options:
              path: /var/lib/grafana/dashboards/kubernetes
      dashboards:
        kubernetes:
          k8s-system-api-server:
            gnetId: 15761
            revision: 8
            datasource: Prometheus
          k8s-system-coredns:
            gnetId: 15762
            revision: 8
            datasource: Prometheus
          k8s-views-global:
            gnetId: 15757
            revision: 18
            datasource: Prometheus
          k8s-views-namespaces:
            gnetId: 15758
            revision: 15
            datasource: Prometheus
          k8s-views-nodes:
            gnetId: 15759
            revision: 18
            datasource: Prometheus
          k8s-views-pods:
            gnetId: 15760
            revision: 16
            datasource: Prometheus
        
    nodeExporter:
      enabled: ${var.enable_node_exporter}
    
    kubeStateMetrics:
      enabled: ${var.enable_kube_state_metrics}
    EOF
  ]
  
  timeout = 900
  
  depends_on = [
    kubernetes_namespace.monitoring
  ]
}

# Deploy KubeCost
resource "helm_release" "kubecost" {
  count = var.enable_kubecost ? 1 : 0
  
  name       = "kubecost"
  repository = "https://kubecost.github.io/cost-analyzer/"
  chart      = "cost-analyzer"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = var.kubecost_version
  
  set {
    name  = "global.prometheus.enabled"
    value = "false"
  }
  
  set {
    name  = "prometheus.server.external"
    value = "http://prometheus-operated:9090"
  }
  
  set {
    name  = "kubecostToken"
    value = "dGVydGVyc3Rlcg=="  # base64 encoded placeholder - replace with real token if needed
  }
  
  depends_on = [
    helm_release.prometheus_stack
  ]
}