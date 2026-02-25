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

  backend "gcs" {
    bucket = "tf-state-infra-learning-pdtung1605"
    prefix = "week3-data"
  }
}

provider "google" {
  credentials = file(pathexpand(var.credentials_file))
  project     = var.project_id
  region      = var.region
}

# ==============================================================================
# ĐỌC STATE TỪ WEEK 1 + WEEK 2
# ==============================================================================
data "terraform_remote_state" "vpc" {
  backend = "gcs"
  config = {
    bucket = "tf-state-infra-learning-pdtung1605"
    prefix = "week1-vpc"
  }
}

data "terraform_remote_state" "gke" {
  backend = "gcs"
  config = {
    bucket = "tf-state-infra-learning-pdtung1605"
    prefix = "week2-gke"
  }
}

# ==============================================================================
# PRIVATE SERVICE CONNECTION — "Cầu nối" VPC ↔ Google Services
# ==============================================================================
# Cloud SQL private IP cần một "đường hầm" riêng giữa VPC của bạn và
# mạng nội bộ của Google. Cái này gọi là Private Service Connection.
#
# Flow: VPC → (VPC Peering) → Google-managed network → Cloud SQL
#
# Tại sao cần? Vì Cloud SQL KHÔNG nằm trong VPC của bạn.
# Nó nằm trong mạng của Google. Để truy cập bằng Private IP,
# phải tạo "cầu nối" (peering) giữa 2 mạng.

# Cấp phát dải IP riêng cho Google Services
resource "google_compute_global_address" "private_ip_range" {
  name          = "google-services-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20 # 4,096 IPs dành cho Google-managed services
  network       = data.terraform_remote_state.vpc.outputs.vpc_id
}

# Tạo Private Service Connection
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = data.terraform_remote_state.vpc.outputs.vpc_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# ==============================================================================
# CLOUD SQL — PostgreSQL (Private IP Only)
# ==============================================================================
# db-f1-micro: 0.6GB RAM, shared CPU — đủ cho learning.
# Private IP: chỉ truy cập được từ VPC (qua Private Service Connection).
# Không có Public IP → an toàn.

resource "random_password" "db_password" {
  length  = 24
  special = true
}

resource "google_sql_database_instance" "platform_db" {
  name                = "platform-db"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = false # Cho phép terraform destroy

  # Phải đợi Private Service Connection tạo xong
  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier              = "db-f1-micro" # Tier nhỏ nhất, ~$10/tháng
    edition           = "ENTERPRISE"  # ENTERPRISE cho tier nhỏ (f1-micro, g1-small)
    availability_type = "ZONAL"       # ZONAL = 1 zone (rẻ). REGIONAL = HA (2 zones, đắt gấp đôi)
    disk_size         = 10            # 10GB SSD
    disk_type         = "PD_SSD"
    disk_autoresize   = false # Tắt auto-resize để kiểm soát chi phí

    ip_configuration {
      ipv4_enabled                                  = false # KHÔNG có Public IP
      private_network                               = data.terraform_remote_state.vpc.outputs.vpc_id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled    = true
      start_time = "03:00" # Backup lúc 3 giờ sáng (UTC)

      backup_retention_settings {
        retained_backups = 7 # Giữ 7 bản backup gần nhất
      }
    }

    maintenance_window {
      day          = 7 # Chủ nhật
      hour         = 4 # 4 giờ sáng UTC = 11 giờ sáng VN
      update_track = "stable"
    }

    database_flags {
      name  = "max_connections"
      value = "50" # Giới hạn connections cho instance nhỏ
    }
  }
}

# Tạo database
resource "google_sql_database" "platform" {
  name     = "platform"
  instance = google_sql_database_instance.platform_db.name
}

# Tạo user
resource "google_sql_user" "platform_user" {
  name     = "platform-admin"
  instance = google_sql_database_instance.platform_db.name
  password = random_password.db_password.result
}

# ==============================================================================
# SECRET MANAGER — Lưu DB credentials an toàn
# ==============================================================================
# Tại sao không hardcode password?
# 1. Ai có access vào Git repo sẽ thấy password
# 2. Rotate password phải sửa code + redeploy
# 3. Secret Manager encrypt + audit log + access control bằng IAM

resource "google_secret_manager_secret" "db_password" {
  secret_id = "platform-db-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "google_secret_manager_secret" "db_connection" {
  secret_id = "platform-db-connection"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_connection" {
  secret = google_secret_manager_secret.db_connection.id
  secret_data = jsonencode({
    host     = google_sql_database_instance.platform_db.private_ip_address
    port     = 5432
    database = google_sql_database.platform.name
    username = google_sql_user.platform_user.name
    password = random_password.db_password.result
    # Connection string cho app (Go/Python)
    dsn = "postgresql://${google_sql_user.platform_user.name}:${random_password.db_password.result}@${google_sql_database_instance.platform_db.private_ip_address}:5432/${google_sql_database.platform.name}?sslmode=disable"
  })
}

# ==============================================================================
# PROMETHEUS + GRAFANA (kube-prometheus-stack via Helm)
# ==============================================================================
# Cài trực tiếp lên staging cluster bằng gcloud + kubectl.
# Terraform quản lý infra, Helm quản lý K8s workloads — separation of concerns.
# Sẽ cài bằng script sau khi terraform apply xong.
