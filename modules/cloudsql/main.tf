# =============================================================================
# Cloud SQL Module — PostgreSQL + Secret Manager
# =============================================================================

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "instance_name" {
  type    = string
  default = "platform-db"
}

variable "database_name" {
  type    = string
  default = "platform"
}

variable "tier" {
  type    = string
  default = "db-f1-micro"
}

variable "vpc_id" {
  type = string
}

variable "private_service_connection_id" {
  description = "ID of the private service connection (dependency)"
  type        = string
}

# ---- Random Password ----
resource "random_password" "db_password" {
  length  = 24
  special = true
}

# ---- Cloud SQL ----
resource "google_sql_database_instance" "db" {
  name                = var.instance_name
  database_version    = "POSTGRES_16"
  region              = var.region
  project             = var.project_id
  deletion_protection = false

  settings {
    tier              = var.tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"
    disk_autoresize   = false

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.vpc_id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled    = true
      start_time = "03:00"
      backup_retention_settings {
        retained_backups = 7
      }
    }

    database_flags {
      name  = "max_connections"
      value = "50"
    }
  }
}

resource "google_sql_database" "db" {
  name     = var.database_name
  instance = google_sql_database_instance.db.name
  project  = var.project_id
}

resource "google_sql_user" "user" {
  name     = "${var.database_name}-admin"
  instance = google_sql_database_instance.db.name
  password = random_password.db_password.result
  project  = var.project_id
}

# ---- Secret Manager ----
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.instance_name}-password"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "google_secret_manager_secret" "db_connection" {
  secret_id = "${var.instance_name}-connection"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_connection" {
  secret = google_secret_manager_secret.db_connection.id
  secret_data = jsonencode({
    host     = google_sql_database_instance.db.private_ip_address
    port     = 5432
    database = google_sql_database.db.name
    username = google_sql_user.user.name
    password = random_password.db_password.result
  })
}

# ---- Outputs ----
output "private_ip" {
  value = google_sql_database_instance.db.private_ip_address
}

output "connection_name" {
  value = google_sql_database_instance.db.connection_name
}

output "database_name" {
  value = google_sql_database.db.name
}

output "password_secret_id" {
  value = google_secret_manager_secret.db_password.secret_id
}
