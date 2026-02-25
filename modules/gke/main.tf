# =============================================================================
# GKE Module — Tạo Private GKE Cluster + Node Pools
# =============================================================================

variable "project_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "location" {
  type = string
}

variable "network" {
  type = string
}

variable "subnetwork" {
  type = string
}

variable "master_ipv4_cidr" {
  type    = string
  default = "172.16.0.0/28"
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "system_machine_type" {
  type    = string
  default = "e2-medium"
}

variable "app_machine_type" {
  type    = string
  default = "e2-medium"
}

variable "system_node_count" {
  type    = number
  default = 1
}

variable "app_node_count" {
  type    = number
  default = 1
}

variable "app_spot" {
  type    = bool
  default = true
}

# ---- Cluster ----
resource "google_container_cluster" "cluster" {
  name     = var.cluster_name
  location = var.location
  project  = var.project_id

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    network_policy_config {
      disabled = false
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  deletion_protection = false
}

# ---- System Pool ----
resource "google_container_node_pool" "system" {
  name     = "system-pool"
  cluster  = google_container_cluster.cluster.id
  location = var.location
  project  = var.project_id

  node_count = var.system_node_count

  node_config {
    machine_type = var.system_machine_type
    disk_size_gb = 50
    disk_type    = "pd-standard"

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    labels       = { role = "system" }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# ---- App Pool ----
resource "google_container_node_pool" "app" {
  name     = "app-pool"
  cluster  = google_container_cluster.cluster.id
  location = var.location
  project  = var.project_id

  node_count = var.app_node_count

  node_config {
    machine_type = var.app_machine_type
    disk_size_gb = 50
    disk_type    = "pd-standard"
    spot         = var.app_spot

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    labels       = { role = "app" }

    taint {
      key    = "spot"
      value  = "true"
      effect = "PREFER_NO_SCHEDULE"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# ---- Outputs ----
output "cluster_name" {
  value = google_container_cluster.cluster.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.cluster.endpoint
  sensitive = true
}

output "cluster_id" {
  value = google_container_cluster.cluster.id
}
