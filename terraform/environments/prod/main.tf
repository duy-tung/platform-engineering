# =============================================================================
# Production Environment — Regional cluster (HA), spot nodes
# =============================================================================

module "vpc" {
  source     = "../../modules/vpc"
  project_id = var.project_id

  subnets = {
    prod-subnet = {
      region        = var.region
      ip_cidr_range = "10.40.0.0/24"
      secondary_ranges = {
        prod-pods     = "10.50.0.0/16"
        prod-services = "10.60.0.0/20"
      }
    }
  }

  enable_nat = false # Public cluster, no NAT needed
}

module "gke" {
  source       = "../../modules/gke"
  project_id   = var.project_id
  cluster_name = "prod-cluster"
  location     = var.region # Regional → HA control plane (3 zones)

  node_locations = ["${var.region}-b"] # Nodes only in 1 zone (cost saving)

  network    = module.vpc.vpc_name
  subnetwork = module.vpc.subnet_names["prod-subnet"]

  pods_range_name     = "prod-pods"
  services_range_name = "prod-services"

  system_machine_type = "e2-small"
  system_node_count   = 0
  app_machine_type    = "e2-small"
  app_node_count      = 1
  app_spot            = true

  enable_private_nodes = false
  disk_size_gb         = 30
}
