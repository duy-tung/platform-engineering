# =============================================================================
# Root Module — Sử dụng tất cả modules
# =============================================================================
# File này cho thấy cách modules được GỌI.
# Thay vì 500+ dòng config, chỉ cần ~80 dòng.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  # Backend: dùng GCS bucket
  # backend "gcs" {
  #   bucket = "tf-state-infra-learning-pdtung1605"
  #   prefix = "infra-modules"
  # }
}

provider "google" {
  credentials = file(pathexpand(var.credentials_file))
  project     = var.project_id
  region      = var.region
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "credentials_file" {
  type      = string
  sensitive = true
}

# ==== MODULE: VPC ====
module "vpc" {
  source = "../modules/vpc"

  project_id   = var.project_id
  network_name = "platform-vpc"

  subnets = {
    "staging-subnet" = {
      region        = "asia-southeast1"
      ip_cidr_range = "10.10.0.0/20"
      secondary_ranges = {
        "staging-pods"     = "10.11.0.0/16"
        "staging-services" = "10.12.0.0/20"
      }
    }
    "prod-subnet" = {
      region        = "us-central1"
      ip_cidr_range = "10.20.0.0/20"
      secondary_ranges = {
        "prod-pods"     = "10.21.0.0/16"
        "prod-services" = "10.22.0.0/20"
      }
    }
  }
}

# ==== MODULE: GKE — Staging ====
module "gke_staging" {
  source = "../modules/gke"

  project_id          = var.project_id
  cluster_name        = "staging-cluster"
  location            = "asia-southeast1"
  network             = module.vpc.vpc_name
  subnetwork          = module.vpc.subnet_names["staging-subnet"]
  master_ipv4_cidr    = "172.16.0.0/28"
  pods_range_name     = "staging-pods"
  services_range_name = "staging-services"
  system_node_count   = 1
  app_node_count      = 1
  app_spot            = true
}

# ==== MODULE: GKE — Prod ====
module "gke_prod" {
  source = "../modules/gke"

  project_id          = var.project_id
  cluster_name        = "prod-cluster"
  location            = "us-central1"
  network             = module.vpc.vpc_name
  subnetwork          = module.vpc.subnet_names["prod-subnet"]
  master_ipv4_cidr    = "172.16.1.0/28"
  pods_range_name     = "prod-pods"
  services_range_name = "prod-services"
  system_node_count   = 1
  app_node_count      = 1
  app_spot            = true
}

# ==== Private Service Connection (cho Cloud SQL) ====
resource "google_compute_global_address" "private_ip_range" {
  name          = "google-services-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = module.vpc.vpc_id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = module.vpc.vpc_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# ==== MODULE: Cloud SQL ====
module "cloudsql" {
  source = "../modules/cloudsql"

  project_id                    = var.project_id
  region                        = var.region
  vpc_id                        = module.vpc.vpc_id
  private_service_connection_id = google_service_networking_connection.private_vpc.id
}

# ==== Artifact Registry ====
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "platform-images"
  format        = "DOCKER"
}

# ==== Outputs ====
output "staging_cluster" { value = module.gke_staging.cluster_name }
output "prod_cluster" { value = module.gke_prod.cluster_name }
output "db_private_ip" { value = module.cloudsql.private_ip }
output "docker_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_repo.repository_id}"
}
