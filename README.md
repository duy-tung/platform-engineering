# Platform Engineering

Production-grade Kubernetes platform on GCP — designed for learning with big-tech patterns.

🔗 **Live:** [platform.duy-tung.dev](https://platform.duy-tung.dev)

## Architecture

```
                    ┌─────────────────────────────────┐
                    │  GitHub Actions (CI)            │
                    │  test → build → push → Trivy    │
                    │  → commit image tag [skip ci]   │
                    └───────────────┬─────────────────┘
                                    │ git push (tag update)
                                    ▼
                    ┌─────────────────────────────────┐
                    │  ArgoCD (CD — GitOps)           │
                    │  Watches main branch            │
                    │  Auto-sync + self-heal          │
                    └─────┬───────────────────┬───────┘
                          │                   │
             ┌────────────▼───┐    ┌──────────▼────────────┐
             │ staging-cluster│    │ prod-cluster          │
             │ (zonal, free)  │    │ (regional)            │
             │ 1× e2-standard │    │ 2× e2-medium          │
             │ spot nodes     │    │ + Istio service mesh  │
             │ in-cluster PG  │    │ + Cloud SQL           │
             └────────────────┘    │ + HTTPS (managed cert)│
                                   └───────────────────────┘
```

## Directory Structure

```
apps/
└── platform-api/          # Go API + embedded CRUD UI
    ├── main.go            # Handlers, DB, embed
    ├── static/index.html  # Dark-themed dashboard
    └── Dockerfile

deploy/
├── helm/platform-api/     # Helm chart (single source of truth)
│   ├── templates/         # deployment, service, secret, postgres
│   ├── values.yaml        # Defaults
│   ├── values-staging.yaml
│   └── values-prod.yaml   # GitOps: change here → ArgoCD syncs
├── argocd/applications/   # ArgoCD Application manifests
└── network-policies/      # Kubernetes NetworkPolicies

terraform/
├── modules/               # Reusable: vpc, gke, cloudsql
└── environments/
    ├── staging/            # Zonal cluster (free tier)
    └── prod/               # Regional cluster

.github/workflows/
├── ci.yaml                # CI only (build + push)
└── terraform.yaml         # IaC plan on PR, apply on merge
```

## GitOps Flow

```bash
# App code change → CI builds → ArgoCD deploys
git push                    # triggers CI
                            # CI: test → build → push → commit tag
                            # ArgoCD: detects tag → syncs both envs

# Config change (replicas, CPU, memory) → ArgoCD deploys directly
vim deploy/helm/platform-api/values-prod.yaml
git commit -m "scale to 2 replicas" && git push
                            # ArgoCD: detects change → applies (no CI)
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | CRUD Dashboard (HTML) |
| GET | `/health` | Health check |
| GET | `/ready` | Readiness probe |
| GET | `/version` | Version + hostname |
| GET | `/db-check` | Database connectivity |
| GET | `/users` | List all users |
| POST | `/users` | Create user |
| GET | `/users/:id` | Get user by ID |
| PUT | `/users/:id` | Update user |
| DELETE | `/users/:id` | Delete user |

## Tech Stack

Terraform · GKE · Helm · ArgoCD · Istio · GitHub Actions · Go · Docker · Cloud SQL · HTTPS
