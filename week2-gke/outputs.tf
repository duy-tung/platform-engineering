# ---- Clusters ----
output "staging_cluster_name" {
  description = "Name of the staging GKE cluster"
  value       = google_container_cluster.staging.name
}

output "staging_cluster_endpoint" {
  description = "Endpoint of the staging GKE cluster"
  value       = google_container_cluster.staging.endpoint
  sensitive   = true
}

output "prod_cluster_name" {
  description = "Name of the production GKE cluster"
  value       = google_container_cluster.prod.name
}

output "prod_cluster_endpoint" {
  description = "Endpoint of the production GKE cluster"
  value       = google_container_cluster.prod.endpoint
  sensitive   = true
}

# ---- Artifact Registry ----
output "docker_repo_url" {
  description = "URL of the Artifact Registry Docker repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_repo.repository_id}"
}
