# =============================================================================
# Staging Environment — Internal only, private cluster
# Zonal cluster (free tier), spot nodes, ArgoCD hub
# Last verified: 2026-03-02 — ruleset fix verified
# =============================================================================

module "vpc" {
  source     = "github.com/duy-tung/terraform-modules//vpc?ref=v1.0.0"
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

  enable_nat = true # Private nodes need NAT for outbound (pull images, etc.)
}

module "gke" {
  source       = "github.com/duy-tung/terraform-modules//gke?ref=v1.1.0"
  project_id   = var.project_id
  cluster_name = "staging-cluster"
  location     = "${var.region}-a" # Zonal → free tier

  network    = module.vpc.vpc_name
  subnetwork = module.vpc.subnet_names["staging-subnet"]

  pods_range_name     = "staging-pods"
  services_range_name = "staging-services"

  system_machine_type = "e2-standard-2"
  system_node_count   = 0
  app_machine_type    = "e2-standard-2"
  app_node_count      = 1
  app_spot            = true

  # ---- Private cluster ----
  enable_private_nodes = true
  master_ipv4_cidr     = "172.16.0.0/28"

  disk_size_gb = 30

  enable_dataplane_v2 = true

  # Istio Ambient — platform-managed via Terraform
  enable_istio_ambient = true

  # ArgoCD — fresh install via Helm (clean rebuild)
  enable_argocd = true
}
