terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # ---- Remote State trên GCS ----
  # State lưu trên cloud → không mất khi destroy, share được với team
  backend "gcs" {
    bucket = "tf-state-infra-learning-pdtung1605"
    prefix = "week1-vpc"
  }
}

provider "google" {
  credentials = file(pathexpand(var.credentials_file))
  project     = var.project_id
  region      = var.region
}

# ==============================================================================
# VPC
# ==============================================================================
resource "google_compute_network" "platform_vpc" {
  name                    = "platform-vpc"
  auto_create_subnetworks = false # Tắt subnet tự động, tự tay định nghĩa
}

# ==============================================================================
# SUBNETS
# ==============================================================================

# ---- Staging Subnet (Asia) ----
resource "google_compute_subnetwork" "staging_subnet" {
  name          = "staging-subnet"
  ip_cidr_range = "10.10.0.0/20" # 4,096 IPs cho VMs
  region        = "asia-southeast1"
  network       = google_compute_network.platform_vpc.id

  # Private Google Access: VM không có IP Public vẫn gọi được Google APIs
  private_ip_google_access = true

  # Secondary ranges: cần cho GKE Pods và Services (Tuần 2)
  secondary_ip_range {
    range_name    = "staging-pods"
    ip_cidr_range = "10.11.0.0/16" # 65,536 IPs cho Pods
  }
  secondary_ip_range {
    range_name    = "staging-services"
    ip_cidr_range = "10.12.0.0/20" # 4,096 IPs cho Services
  }
}

# ---- Production Subnet (US) ----
resource "google_compute_subnetwork" "prod_subnet" {
  name          = "prod-subnet"
  ip_cidr_range = "10.20.0.0/20" # 4,096 IPs cho VMs
  region        = "us-central1"
  network       = google_compute_network.platform_vpc.id

  private_ip_google_access = true

  # Secondary ranges cho GKE Tuần 2
  secondary_ip_range {
    range_name    = "prod-pods"
    ip_cidr_range = "10.21.0.0/16"
  }
  secondary_ip_range {
    range_name    = "prod-services"
    ip_cidr_range = "10.22.0.0/20"
  }
}

# ==============================================================================
# CLOUD ROUTER + NAT (asia-southeast1)
# ==============================================================================
resource "google_compute_router" "staging_router" {
  name    = "staging-router"
  region  = "asia-southeast1"
  network = google_compute_network.platform_vpc.id
}

resource "google_compute_router_nat" "staging_nat" {
  name                               = "staging-nat"
  router                             = google_compute_router.staging_router.name
  region                             = "asia-southeast1"
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Log NAT connections (debug khi cần)
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ==============================================================================
# CLOUD ROUTER + NAT (us-central1)
# ==============================================================================
resource "google_compute_router" "prod_router" {
  name    = "prod-router"
  region  = "us-central1"
  network = google_compute_network.platform_vpc.id
}

resource "google_compute_router_nat" "prod_nat" {
  name                               = "prod-nat"
  router                             = google_compute_router.prod_router.name
  region                             = "us-central1"
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ==============================================================================
# FIREWALL RULES
# ==============================================================================

# ---- Chặn tất cả Ingress từ Internet ----
resource "google_compute_firewall" "deny_all_ingress" {
  name      = "deny-all-ingress"
  network   = google_compute_network.platform_vpc.id
  priority  = 1000
  direction = "INGRESS"

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

# ---- Cho phép SSH qua IAP (Identity-Aware Proxy) ----
# IAP Tunnel dùng dải IP 35.235.240.0/20 của Google
resource "google_compute_firewall" "allow_iap_ssh" {
  name      = "allow-iap-ssh"
  network   = google_compute_network.platform_vpc.id
  priority  = 500 # Ưu tiên cao hơn rule deny ở trên
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["allow-ssh"] # Chỉ VM có tag này mới được SSH
}

# ---- Cho phép traffic nội bộ giữa các VMs trong VPC ----
resource "google_compute_firewall" "allow_internal" {
  name      = "allow-internal"
  network   = google_compute_network.platform_vpc.id
  priority  = 900
  direction = "INGRESS"

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  # Cho phép tất cả subnet ranges nội bộ giao tiếp
  source_ranges = [
    "10.10.0.0/20", # staging-subnet
    "10.20.0.0/20", # prod-subnet
  ]
}
