variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-southeast1"
}

variable "argocd_webhook_secret" {
  description = "GitHub webhook secret for ArgoCD instant sync"
  type        = string
  default     = ""
  sensitive   = true
}
