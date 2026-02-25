# =============================================================================
# Staging Environment — Zonal cluster (free tier), spot nodes
# =============================================================================

module "vpc" {
  source     = "../../modules/vpc"
  project_id = var.project_id

  subnets = {
    staging-subnet = {
      region        = var.region
      ip_cidr_range = "10.10.0.0/24"
      secondary_ranges = {
        staging-pods     = "10.20.0.0/16"
        staging-services = "10.30.0.0/20"
      }
    }
  }

  enable_nat = false # Public cluster, no NAT needed
}

module "gke" {
  source       = "../../modules/gke"
  project_id   = var.project_id
  cluster_name = "staging-cluster"
  location     = "${var.region}-a" # Zonal → free tier

  network    = module.vpc.vpc_name
  subnetwork = module.vpc.subnet_names["staging-subnet"]

  pods_range_name     = "staging-pods"
  services_range_name = "staging-services"

  system_machine_type = "e2-small"
  system_node_count   = 0
  app_machine_type    = "e2-small"
  app_node_count      = 1
  app_spot            = true

  enable_private_nodes = false
  disk_size_gb         = 30
}
