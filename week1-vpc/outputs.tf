# ---- VPC ----
output "vpc_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.platform_vpc.name
}

output "vpc_id" {
  description = "ID of the VPC network (used by other modules)"
  value       = google_compute_network.platform_vpc.id
}

# ---- Subnets ----
output "staging_subnet_name" {
  description = "Name of the staging subnet"
  value       = google_compute_subnetwork.staging_subnet.name
}

output "staging_subnet_cidr" {
  description = "CIDR range of the staging subnet"
  value       = google_compute_subnetwork.staging_subnet.ip_cidr_range
}

output "prod_subnet_name" {
  description = "Name of the production subnet"
  value       = google_compute_subnetwork.prod_subnet.name
}

output "prod_subnet_cidr" {
  description = "CIDR range of the production subnet"
  value       = google_compute_subnetwork.prod_subnet.ip_cidr_range
}

# ---- NAT Routers ----
output "staging_router_name" {
  description = "Name of the staging Cloud Router"
  value       = google_compute_router.staging_router.name
}

output "prod_router_name" {
  description = "Name of the production Cloud Router"
  value       = google_compute_router.prod_router.name
}
