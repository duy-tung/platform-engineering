# ---- Cloud SQL ----
output "db_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.platform_db.name
}

output "db_private_ip" {
  description = "Private IP of Cloud SQL instance"
  value       = google_sql_database_instance.platform_db.private_ip_address
}

output "db_connection_name" {
  description = "Cloud SQL connection name (for Auth Proxy)"
  value       = google_sql_database_instance.platform_db.connection_name
}

output "db_database_name" {
  description = "Database name"
  value       = google_sql_database.platform.name
}

# ---- Secrets ----
output "db_password_secret_id" {
  description = "Secret Manager ID for DB password"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "db_connection_secret_id" {
  description = "Secret Manager ID for full DB connection info"
  value       = google_secret_manager_secret.db_connection.secret_id
}
