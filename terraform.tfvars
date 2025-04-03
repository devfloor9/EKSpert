region             = "us-west-2"
project            = "mycompany"
environment        = "production"
vpc_cidr           = "10.0.0.0/16"
kubernetes_version = "1.28"

node_groups = {
  system = {
    desired_size   = 2
    min_size       = 2
    max_size       = 4
    instance_types = ["m6i.large"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 50
    labels = {
      "role" = "system"
    }
    enable_cluster_autoscaler = true
  },
  
  application = {
    desired_size   = 3
    min_size       = 3
    max_size       = 10
    instance_types = ["m6i.xlarge"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 100
    labels = {
      "role" = "application"
    }
    enable_cluster_autoscaler = true
  },
  
  spot = {
    desired_size   = 1
    min_size       = 0
    max_size       = 10
    instance_types = ["m6i.large", "m5.large", "m5a.large"]
    capacity_type  = "SPOT"
    disk_size      = 50
    labels = {
      "role" = "spot"
    }
    enable_cluster_autoscaler = true
  }
}

grafana_admin_password = "StrongPasswordHere123!"  # Change this in production!
opensearch_master_password = "StrongPasswordHere456!"  # Change this in production!