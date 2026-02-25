terraform {
  # GKE clusters: staging (asia-southeast1) + prod (us-central1)
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    bucket = "tf-state-infra-learning-pdtung1605"
    prefix = "week2-gke"
  }
}

provider "google" {
  credentials = file(pathexpand(var.credentials_file))
  project     = var.project_id
  region      = var.region
}

# ==============================================================================
# ĐỌC STATE TỪ WEEK 1 — Lấy VPC + Subnet đã tạo
# ==============================================================================
# terraform_remote_state cho phép đọc outputs từ workspace khác.
# Nhờ vậy Week 2 không cần tạo lại VPC, mà dùng lại cái Week 1 đã tạo.
data "terraform_remote_state" "vpc" {
  backend = "gcs"
  config = {
    bucket = "tf-state-infra-learning-pdtung1605"
    prefix = "week1-vpc"
  }
}

# ==============================================================================
# ARTIFACT REGISTRY — Nơi lưu Docker Images
# ==============================================================================
# Giống Docker Hub nhưng nằm trong GCP, private, tính tiền theo storage.
# Cần có trước khi build image ở Tuần 4.
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "platform-images"
  description   = "Docker images for platform services"
  format        = "DOCKER"
}

# ==============================================================================
# GKE CLUSTER — STAGING (asia-southeast1)
# ==============================================================================
resource "google_container_cluster" "staging" {
  name     = "staging-cluster"
  location = var.region # Regional cluster — nodes spread across zones

  # Xóa default node pool ngay sau khi tạo.
  # GKE bắt buộc phải có ít nhất 1 node pool khi tạo cluster,
  # nên ta tạo 1 node rồi xóa ngay, sau đó dùng node pool riêng bên dưới.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Gắn vào VPC + Subnet của Week 1
  network    = data.terraform_remote_state.vpc.outputs.vpc_name
  subnetwork = data.terraform_remote_state.vpc.outputs.staging_subnet_name

  # ---- Private Cluster ----
  # Worker nodes KHÔNG có IP Public → không ai từ Internet truy cập được.
  # Control plane (master) vẫn có endpoint public để kubectl kết nối,
  # nhưng chỉ allow từ internal networks.
  private_cluster_config {
    enable_private_nodes    = true            # Nodes chỉ có IP nội bộ
    enable_private_endpoint = false           # Cho phép kubectl từ bên ngoài
    master_ipv4_cidr_block  = "172.16.0.0/28" # Dải IP riêng cho control plane
  }

  # Chỉ cho phép kết nối kubectl từ mạng nội bộ
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.10.0.0/20"
      display_name = "staging-subnet"
    }
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "local-dev"
    }
  }

  # ---- IP Allocation ----
  # Trỏ vào secondary IP ranges đã tạo ở Week 1.
  # Pods và Services sẽ dùng dải IP riêng, không tranh với VMs.
  ip_allocation_policy {
    cluster_secondary_range_name  = "staging-pods"     # 10.11.0.0/16
    services_secondary_range_name = "staging-services" # 10.12.0.0/20
  }

  # ---- Workload Identity ----
  # Cho phép Pods nói chuyện với GCP APIs mà KHÔNG cần key file.
  # Pod sẽ "đóng vai" một GCP Service Account thông qua K8s Service Account.
  # Ví dụ: Pod cần đọc Secret Manager → bind K8s SA với GCP SA có quyền.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # ---- Network Policy ----
  # Bật Calico network policy engine cho cluster.
  # Mặc định tất cả Pods nói chuyện tự do → nguy hiểm.
  # Với network policy, ta có thể: "Pod A chỉ được gọi Pod B, không được gọi Pod C".
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # ---- Addons ----
  addons_config {
    # HTTP Load Balancing — cần cho Ingress Controller
    http_load_balancing {
      disabled = false
    }
    # HPA — tự scale pods dựa trên CPU/Memory
    horizontal_pod_autoscaling {
      disabled = false
    }
    # GCE PD CSI Driver — để pods dùng persistent disk
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    # Network Policy addon (Calico)
    network_policy_config {
      disabled = false
    }
  }

  # Kênh release: REGULAR = nhận update K8s version cân bằng giữa ổn định và mới
  release_channel {
    channel = "REGULAR"
  }

  # Tắt deletion protection → cho phép terraform destroy
  deletion_protection = false
}

# ==============================================================================
# NODE POOLS — STAGING
# ==============================================================================

# ---- System Pool: Chạy thành phần lõi K8s (kube-system) ----
# Dùng On-demand VM vì system components KHÔNG được bị gián đoạn.
resource "google_container_node_pool" "staging_system" {
  name     = "system-pool"
  cluster  = google_container_cluster.staging.id
  location = var.region

  node_count = 1 # 1 node cho staging là đủ

  node_config {
    machine_type = "e2-medium" # 2 vCPU, 4GB RAM
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # Workload Identity ở node level
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # OAuth scope cho node
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Labels để phân biệt — scheduler biết node nào chạy system workload
    labels = {
      role = "system"
    }
  }

  # Tự động repair node bị lỗi & upgrade version
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# ---- App Pool: Chạy ứng dụng của bạn ----
# Dùng Spot VM (trước đây gọi là Preemptible) để TIẾT KIỆM ~60-90% chi phí.
# Spot VM có thể bị Google thu lại bất kỳ lúc nào (khi Google cần máy),
# nhưng K8s sẽ tự reschedule pod sang node khác → OK cho staging/dev.
resource "google_container_node_pool" "staging_app" {
  name     = "app-pool"
  cluster  = google_container_cluster.staging.id
  location = var.region

  node_count = 1 # Giảm xuống 1 để tiết kiệm (plan gốc là 2)

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 50
    disk_type    = "pd-standard"
    spot         = true # ← Spot VM, tiết kiệm ~60-90%

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      role = "app"
    }

    # Taint: Chỉ pods có toleration mới được schedule vào pool này.
    # System pods sẽ KHÔNG chạy trên spot VMs.
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

# ==============================================================================
# GKE CLUSTER — PRODUCTION (us-central1)
# ==============================================================================
resource "google_container_cluster" "prod" {
  name     = "prod-cluster"
  location = "us-central1"

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = data.terraform_remote_state.vpc.outputs.vpc_name
  subnetwork = data.terraform_remote_state.vpc.outputs.prod_subnet_name

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.1.0/28" # Khác với staging (tránh conflict)
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.20.0.0/20"
      display_name = "prod-subnet"
    }
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "local-dev"
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "prod-pods"
    services_secondary_range_name = "prod-services"
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

# ---- System Pool — Prod ----
resource "google_container_node_pool" "prod_system" {
  name     = "system-pool"
  cluster  = google_container_cluster.prod.id
  location = "us-central1"

  node_count = 1

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 50
    disk_type    = "pd-standard"

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      role = "system"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# ---- App Pool — Prod ----
resource "google_container_node_pool" "prod_app" {
  name     = "app-pool"
  cluster  = google_container_cluster.prod.id
  location = "us-central1"

  node_count = 1

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 50
    disk_type    = "pd-standard"
    spot         = true

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      role = "app"
    }

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
