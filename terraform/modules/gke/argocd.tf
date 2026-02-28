# =============================================================================
# ArgoCD — Platform Bootstrap (managed by Terraform)
# =============================================================================
# Tier 2 pattern: Terraform installs ArgoCD via Helm.
# ArgoCD then manages all app-level workloads via root-app.

variable "enable_argocd" {
  description = "Install ArgoCD via Helm"
  type        = bool
  default     = false
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.8.13"
}

variable "argocd_webhook_secret" {
  description = "GitHub webhook secret for instant sync"
  type        = string
  default     = ""
  sensitive   = true
}

# ---- ArgoCD namespace ----
resource "kubernetes_namespace" "argocd" {
  count = var.enable_argocd ? 1 : 0
  metadata {
    name = "argocd"
  }
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

# ---- ArgoCD Helm release ----
resource "helm_release" "argocd" {
  count            = var.enable_argocd ? 1 : 0
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = "argocd"
  create_namespace = false

  values = [yamlencode({
    # Server runs behind GKE Gateway — no TLS needed internally
    server = {
      insecure = true
    }

    # Webhook secret for GitHub instant sync
    configs = {
      secret = {
        extra = var.argocd_webhook_secret != "" ? {
          "webhook.github.secret" = var.argocd_webhook_secret
        } : {}
      }
    }

    # Resource limits for e2-standard-2 nodes
    controller = {
      resources = {
        requests = { cpu = "100m", memory = "512Mi" }
        limits   = { cpu = "500m", memory = "1Gi" }
      }
    }
    server = {
      insecure = true
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "128Mi" }
      }
    }
    repoServer = {
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }
    }
    redis = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { cpu = "100m", memory = "64Mi" }
      }
    }
  })]

  depends_on = [kubernetes_namespace.argocd]
}
