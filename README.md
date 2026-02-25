# 🏗️ Platform Engineering — Learning Path

12-month hands-on learning journey for GCP platform engineering.

## Architecture

```
┌─── Week 1-2: Foundation ─────────────────────────────────────┐
│  VPC (Custom) → Subnets → Cloud NAT → Firewall              │
│  GKE Staging (asia-southeast1) + GKE Prod (us-central1)     │
│  Artifact Registry                                           │
├─── Week 3: Data ─────────────────────────────────────────────┤
│  Cloud SQL PostgreSQL 16 (Private IP)                        │
│  Secret Manager │ Private Service Connection                 │
│  kube-prometheus-stack (Prometheus + Grafana)                 │
├─── Week 4: CI/CD ────────────────────────────────────────────┤
│  Go API → Dockerfile (multi-stage) → Cloud Build             │
│  Kustomize (base + overlays) → ArgoCD (GitOps)               │
│  GitHub Actions: build → test → scan → push                  │
├─── Week 5: Security ─────────────────────────────────────────┤
│  Pod Security Standards (restricted)                         │
│  OPA Gatekeeper (3 constraint templates)                     │
│  NetworkPolicy (zero trust)                                  │
├─── Week 6: Advanced Terraform ───────────────────────────────┤
│  Reusable modules: VPC, GKE, Cloud SQL                       │
│  Root module composition (500+ → 80 lines)                   │
│  CI: terraform plan on PR + Infracost                        │
└──────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
├── modules/              # Reusable Terraform modules
│   ├── vpc/              # VPC + Subnets + NAT + Firewall
│   ├── gke/              # Private GKE + Node Pools
│   └── cloudsql/         # PostgreSQL + Secrets
├── infra/                # Root module (composes all modules)
├── week1-vpc/            # Week 1: VPC setup
├── week2-gke/            # Week 2: GKE clusters
├── week3-data/           # Week 3: Cloud SQL + Secrets
├── app/                  # Go API (platform-api)
├── k8s/                  # Kubernetes manifests
│   ├── base/             # Kustomize base
│   ├── overlays/         # Staging + Production
│   └── security/         # Gatekeeper + NetworkPolicy
└── .github/workflows/    # CI/CD pipelines
```

## Quick Start

```bash
# 1. Copy tfvars
cp terraform.tfvars.example week1-vpc/terraform.tfvars
# Edit with your project_id and credentials

# 2. Deploy infrastructure (in order)
cd week1-vpc && terraform init && terraform apply
cd ../week2-gke && terraform init && terraform apply
cd ../week3-data && terraform init && terraform apply

# 3. Build & deploy app
gcloud builds submit app/ --tag=REGISTRY/platform-api:v1
kubectl apply -k k8s/overlays/staging/
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Cloud | GCP (GKE, Cloud SQL, Secret Manager, Artifact Registry) |
| IaC | Terraform + reusable modules |
| Container | Docker (multi-stage, scratch) |
| Orchestration | Kubernetes (GKE) |
| GitOps | ArgoCD |
| CI/CD | GitHub Actions |
| Monitoring | Prometheus + Grafana |
| Security | PSS + OPA Gatekeeper + NetworkPolicy |
| App | Go (stdlib) |
