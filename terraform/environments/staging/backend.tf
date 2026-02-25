terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  backend "gcs" {
    bucket = "tf-state-infra-learning-pdtung1605"
    prefix = "staging"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
