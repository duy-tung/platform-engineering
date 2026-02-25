# Platform Engineering

Production-grade Kubernetes platform on GCP — designed for learning with big tech patterns.

## Architecture

```
┌─────────────────────────────────────────────┐
│ GitHub Actions CI/CD                        │
│ ├── Build → Test → Scan → Push              │
│ └── Terraform Plan (PR review)              │
└─────────────┬───────────────────────────────┘
              │ GitOps (ArgoCD)
              ▼
┌──────────────────┐  ┌──────────────────────┐
│ staging-cluster  │  │ prod-cluster         │
│ (zonal, free)    │  │ (regional, HA)       │
│ 1 × e2-small     │  │ 1 × e2-small        │
│ spot             │  │ spot                 │
└──────────────────┘  └──────────────────────┘
```

## Directory Structure

```
terraform/
├── modules/              # Reusable: vpc, gke, cloudsql
└── environments/         # Per-env state
    ├── staging/          # Zonal (free tier)
    └── prod/             # Regional (HA)
apps/
└── platform-api/         # Go API + Dockerfile
deploy/
└── k8s/
    ├── base/             # Shared manifests
    ├── overlays/         # staging + prod configs
    └── policies/         # Gatekeeper + NetworkPolicy
.github/workflows/
├── ci.yaml               # App CI/CD
└── terraform.yaml        # IaC plan on PR
```

## Quick Start

```bash
# Start infrastructure (~5 min)
./scripts/start.sh

# Stop to save costs
./scripts/stop.sh
```

## Cost: ~$97/month

| Resource | Cost |
|----------|------|
| GKE staging (zonal, free) | $0 |
| GKE prod (regional, HA) | $74 |
| 2 × e2-small spot | $14 |
| Storage | $3 |

## Tech Stack

Terraform · GKE · ArgoCD · Kustomize · GitHub Actions · Go · Docker · OPA Gatekeeper · Prometheus
