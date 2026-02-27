# =============================================================================
# VPC Module — Tạo VPC, Subnets, NAT, Firewall
# =============================================================================
# Mục đích: Tái sử dụng cho bất kỳ project nào cần private networking.
# Thay vì copy-paste 180 dòng, gọi module với vài biến.

variable "project_id" {
  type = string
}

variable "network_name" {
  type    = string
  default = "platform-vpc"
}

variable "subnets" {
  description = "Map of subnets to create"
  type = map(object({
    region           = string
    ip_cidr_range    = string
    secondary_ranges = optional(map(string), {})
  }))
}

variable "enable_nat" {
  description = "Create Cloud NAT per region"
  type        = bool
  default     = true
}

# ---- VPC ----
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  project                 = var.project_id
}

# ---- Subnets ----
resource "google_compute_subnetwork" "subnets" {
  for_each = var.subnets

  name                     = each.key
  ip_cidr_range            = each.value.ip_cidr_range
  region                   = each.value.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  project                  = var.project_id

  dynamic "secondary_ip_range" {
    for_each = each.value.secondary_ranges
    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }
}

# ---- Cloud Router + NAT (per unique region) ----
locals {
  regions = var.enable_nat ? toset([for s in var.subnets : s.region]) : toset([])
}

resource "google_compute_router" "router" {
  for_each = local.regions

  name    = "${var.network_name}-router-${each.key}"
  region  = each.key
  network = google_compute_network.vpc.id
  project = var.project_id
}

resource "google_compute_router_nat" "nat" {
  for_each = local.regions

  name                               = "${var.network_name}-nat-${each.key}"
  router                             = google_compute_router.router[each.key].name
  region                             = each.key
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  project                            = var.project_id

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# NOTE: deny_all_ingress firewall removed — it blocked GKE master→pod
# communication (webhooks, kubelet). K8s NetworkPolicies used instead.

resource "google_compute_firewall" "allow_iap_ssh" {
  name      = "${var.network_name}-allow-iap-ssh"
  network   = google_compute_network.vpc.id
  priority  = 500
  direction = "INGRESS"
  project   = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["allow-ssh"]
}

resource "google_compute_firewall" "allow_internal" {
  name      = "${var.network_name}-allow-internal"
  network   = google_compute_network.vpc.id
  priority  = 600
  direction = "INGRESS"
  project   = var.project_id

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = [for s in var.subnets : s.ip_cidr_range]
}

# ---- Outputs ----
output "vpc_id" {
  value = google_compute_network.vpc.id
}

output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "subnet_names" {
  value = { for k, v in google_compute_subnetwork.subnets : k => v.name }
}

output "subnet_ids" {
  value = { for k, v in google_compute_subnetwork.subnets : k => v.id }
}
