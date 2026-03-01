# =============================================================================
# Istio Ambient — Platform Component (managed by Terraform, not ArgoCD)
# =============================================================================
# Follows Uber/Airbnb pattern: service mesh = platform infrastructure.
# ArgoCD only manages app-level resources (Gateway, HTTPRoute, policies).

variable "enable_istio_ambient" {
  description = "Install Istio Ambient components via Helm"
  type        = bool
  default     = false
}

variable "istio_version" {
  description = "Istio Helm chart version"
  type        = string
  default     = "1.29.0"
}

variable "istio_istiod_replicas" {
  description = "Number of istiod replicas (1 for staging, 2+ for prod)"
  type        = number
  default     = 1
}

# ---- Namespace ----
resource "kubernetes_namespace" "istio_system" {
  count = var.enable_istio_ambient ? 1 : 0
  metadata {
    name = "istio-system"
  }
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

# ---- istio-base (CRDs + RBAC) ----
resource "helm_release" "istio_base" {
  count            = var.enable_istio_ambient ? 1 : 0
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  version          = var.istio_version
  namespace        = "istio-system"
  create_namespace = false

  depends_on = [kubernetes_namespace.istio_system]
}

# ---- istiod (control plane) ----
resource "helm_release" "istiod" {
  count            = var.enable_istio_ambient ? 1 : 0
  name             = "istiod"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  version          = var.istio_version
  namespace        = "istio-system"
  create_namespace = false

  values = [yamlencode({
    profile = "ambient"
    global = {
      platform = "gke"
    }
    pilot = {
      replicaCount = var.istio_istiod_replicas
      env = {
        PILOT_ENABLE_AMBIENT = "true"
      }
    }
    resources = {
      requests = { cpu = "10m", memory = "64Mi" }
      limits   = { cpu = "500m", memory = "256Mi" }
    }
  })]

  depends_on = [helm_release.istio_base]
}

# ---- istio-cni (required for ambient) ----
resource "helm_release" "istio_cni" {
  count            = var.enable_istio_ambient ? 1 : 0
  name             = "istio-cni"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "cni"
  version          = var.istio_version
  namespace        = "istio-system"
  create_namespace = false

  values = [yamlencode({
    profile = "ambient"
    global = {
      platform = "gke"
    }
    cni = {
      cniBinDir = "/home/kubernetes/bin"
      resources = {
        requests = { cpu = "5m", memory = "32Mi" }
        limits   = { cpu = "100m", memory = "128Mi" }
      }
    }
  })]

  depends_on = [helm_release.istiod]
}

# ---- ztunnel (L4 data plane for ambient) ----
resource "helm_release" "ztunnel" {
  count            = var.enable_istio_ambient ? 1 : 0
  name             = "ztunnel"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "ztunnel"
  version          = var.istio_version
  namespace        = "istio-system"
  create_namespace = false

  values = [yamlencode({
    global = {
      platform = "gke"
    }
    resources = {
      requests = { cpu = "5m", memory = "32Mi" }
      limits   = { cpu = "200m", memory = "128Mi" }
    }
  })]

  depends_on = [helm_release.istiod]
}
