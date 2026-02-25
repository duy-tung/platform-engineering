variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region (primary)"
  type        = string
}

variable "zone" {
  description = "GCP Zone"
  type        = string
}

variable "credentials_file" {
  description = "Path to the Terraform Service Account key file"
  type        = string
  sensitive   = true
}
