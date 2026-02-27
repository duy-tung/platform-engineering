# =============================================================================
# Production Environment — Regional HA, private cluster, big-tech grade
# =============================================================================

module "vpc" {
  source       = "../../modules/vpc"
  project_id   = var.project_id
  network_name = "prod-vpc"

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

  enable_nat = true # Private nodes need NAT for outbound
}

module "gke" {
  source       = "../../modules/gke"
  project_id   = var.project_id
  cluster_name = "prod-cluster"
  location     = var.region # Regional → HA control plane (3 zones)

  # Multi-zone nodes for HA (big-tech: ≥2 zones)
  node_locations = ["${var.region}-a", "${var.region}-b"]

  network    = module.vpc.vpc_name
  subnetwork = module.vpc.subnet_names["prod-subnet"]

  pods_range_name     = "prod-pods"
  services_range_name = "prod-services"

  system_machine_type = "e2-medium"
  system_node_count   = 1
  app_machine_type    = "e2-medium"
  app_node_count      = 1
  app_spot            = false # On-demand for prod reliability

  # ---- Private cluster ----
  enable_private_nodes = true
  master_ipv4_cidr     = "172.16.1.0/28"

  disk_size_gb = 30
}

# ---- Private Service Connection (for Cloud SQL private IP) ----
resource "google_compute_global_address" "private_ip_range" {
  name          = "prod-cloudsql-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = module.vpc.vpc_id
  project       = var.project_id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = module.vpc.vpc_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# ---- Cloud SQL HA (big-tech grade) ----
module "cloudsql" {
  source     = "../../modules/cloudsql"
  project_id = var.project_id
  region     = var.region

  instance_name = "platform-db"
  database_name = "platform"
  tier          = "db-f1-micro" # Shared core, 0.6GB — đủ cho learning

  vpc_id                        = module.vpc.vpc_id
  private_service_connection_id = google_service_networking_connection.private_vpc.id
}
