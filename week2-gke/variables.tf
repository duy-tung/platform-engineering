variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region (primary — staging cluster)"
  type        = string
}

variable "credentials_file" {
  description = "Path to the Terraform Service Account key file"
  type        = string
  sensitive   = true
}

