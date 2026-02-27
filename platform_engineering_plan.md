# 🚀 Platform Engineering 12-Month Learning Plan — 2026

> **Profile**: Senior Go/Python Backend Engineer → Platform Engineer
> **Cloud**: Google Cloud Platform
> **Budget**: $300 GCP trial credit (90 ngày) + $100/tháng riêng

---

## 💰 Phân bổ Budget

| Giai đoạn | Tháng | Credit | Tiền riêng | Tổng/tháng | Chiến lược |
|-----------|--------|--------|------------|------------|------------|
| **Phase 1** | 1-3 | $300 (chia 3) | $100/tháng | ~$200/tháng | Dồn hết resource tốn tiền (GKE, Cloud SQL, LB) |
| **Phase 2** | 4-6 | Hết | $100/tháng | $100/tháng | Free-tier tools (Backstage, Crossplane local) |
| **Phase 3** | 7-9 | — | $100/tháng | $100/tháng | Lean cloud + local K8s (kind/minikube) |
| **Phase 4** | 10-12 | — | $100/tháng | $100/tháng | AI/ML workloads nhẹ, capstone project |

> [!IMPORTANT]
> **Quy tắc vàng**: Thứ 6 `terraform destroy` → Thứ 2 `terraform apply`. Tiết kiệm ~60% chi phí.

---

## Phase 1: Cloud Infrastructure (Tháng 1-3, ~$200/tháng)

*Tận dụng GCP credit để hands-on với resource tốn tiền. Sau phase này bạn sẽ có nền tảng vững.*

### Tháng 1: Network + Kubernetes + Database

#### Tuần 1 — Private Network Foundation
- VPC custom mode, 2 subnets (2 regions: `asia-southeast1`, `us-central1`)
- Firewall deny-all + allow IAP SSH only
- Cloud Router + Cloud NAT
- 🆕 GCS backend cho Terraform remote state
- **Test**: VM e2-micro không IP public → SSH qua IAP → `ping google.com` ✅

#### Tuần 2 — Private GKE Clusters
- 2 GKE private clusters (staging + prod)
- Node pools: system-pool (on-demand) + app-pool (Spot VM)
- Workload Identity
- 🆕 Network Policy (deny-all + allow cụ thể)
- 🆕 Terraform modules (tái sử dụng VPC/GKE config)
- 🆕 Artifact Registry repository
- **Test**: `kubectl get nodes` → 3 nodes chỉ có Internal IP ✅

#### Tuần 3 — Database + Secrets
- VPC Peering: `platform-vpc` ↔ `data-vpc`
- Cloud SQL PostgreSQL HA (Private IP only)
- 🆕 Secret Manager cho DB credentials
- 🆕 Cloud SQL Auth Proxy sidecar
- **Test**: Pod trong GKE `psql` vào Cloud SQL qua private IP ✅

#### Tuần 4 — CI/CD + Monitoring + GitOps
- Go API đơn giản + Dockerfile multi-stage
- 🆕 GitHub Actions: build → test → scan (Trivy) → push Artifact Registry
- ArgoCD trên staging cluster
- 🆕 kube-prometheus-stack (Prometheus + Grafana)
- LoadBalancer expose app
- **Test**: Push code → auto build → auto deploy → thấy trên browser ✅

> **Chi phí tháng 1**: ~$155 (nếu destroy cuối tuần)

---

### Tháng 2: Hardening & Production Readiness

#### Tuần 5 — Security Hardening
- Pod Security Standards (restricted profile)
- Binary Authorization (chỉ deploy signed images)
- OPA Gatekeeper — Policy-as-Code
- **Test**: Deploy image chưa sign → bị reject ✅

#### Tuần 6 — Advanced Terraform
- Module hóa toàn bộ infra (VPC, GKE, Cloud SQL modules)
- Terraform workspaces (staging vs prod)
- `terraform plan` trong CI (GitHub Actions)
- Infracost integration — ước tính chi phí trước khi apply
- **Test**: PR trên GitHub → comment hiện cost estimate ✅

#### Tuần 7 — Advanced Kubernetes
- Helm charts cho app deployment
- HPA (Horizontal Pod Autoscaler)
- PDB (Pod Disruption Budget)
- Resource quotas & LimitRanges
- **Test**: Load test → pods tự scale up ✅

#### Tuần 8 — Observability Deep Dive
- OpenTelemetry tracing cho Go app
- Grafana dashboards custom (latency, error rate, throughput — RED method)
- Alerting rules (PagerDuty/Slack webhook)
- Log aggregation (Cloud Logging hoặc Loki)
- **Test**: Inject lỗi → alert fires → trace hiện bottleneck ✅

> **Chi phí tháng 2**: ~$120 (đã quen destroy/apply)

---

### Tháng 3: Multi-Service Architecture

#### Tuần 9 — Microservices trên GKE
- 2-3 Go microservices (API Gateway, User Service, Order Service)
- gRPC internal communication
- Ingress Controller (NGINX hoặc GKE Gateway API)
- **Test**: External request → Gateway → internal gRPC → response ✅

#### Tuần 10 — Message Queue + Async
- Cloud Pub/Sub (hoặc deploy Redis/NATS trên GKE)
- Event-driven architecture giữa services
- Dead Letter Queue handling
- **Test**: Publish event → consumer xử lý → verify trong DB ✅

#### Tuần 11 — Database Migration & Multi-tenancy
- Flyway/golang-migrate cho schema versioning
- Connection pooling (PgBouncer)
- Read replica setup
- **Test**: Migration up/down thành công, zero downtime ✅

#### Tuần 12 — Tổng kết Phase 1
- Document toàn bộ architecture (Excalidraw diagrams)
- Disaster recovery test: `terraform destroy` → `terraform apply` → verify tất cả services
- **Deliverable**: GitHub repo hoàn chỉnh + README + Architecture Diagram

> **Chi phí tháng 3**: ~$100 (credit sắp hết, tối ưu hóa tối đa)

---

## Phase 2: Developer Platform (Tháng 4-6, $100/tháng)

*Credit hết. Chuyển sang tools miễn phí chạy local + cloud usage tối thiểu.*

### Tháng 4: Internal Developer Portal — Backstage

> **Chi phí thấp**: Backstage chạy local, chỉ cần GKE khi deploy.

#### Tuần 13-14 — Backstage Core
- Cài đặt Backstage locally (Node.js)
- Service Catalog — đăng ký tất cả services từ Phase 1
- Software Templates — tạo template "New Go Microservice"
- TechDocs — tự động generate docs từ markdown
- **Test**: Developer dùng template → scaffold project mới trong 2 phút ✅

#### Tuần 15-16 — Backstage + Kubernetes Plugin
- Kubernetes plugin — xem pod status trực tiếp trong Backstage
- CI/CD plugin — xem GitHub Actions pipeline status
- Custom plugin (TypeScript) — hiển thị cost dashboard
- Deploy Backstage lên GKE staging (1 tuần, rồi destroy)
- **Test**: Backstage UI hiện service → pods → logs → CI status ✅

> **Chi phí tháng 4**: ~$40 (Backstage local + 1 tuần GKE)

---

### Tháng 5: Crossplane — Kubernetes-native IaC

> **Chi phí thấp**: Chạy Crossplane trên local K8s (kind cluster).

#### Tuần 17-18 — Crossplane Fundamentals
- Cài Crossplane trên **kind** cluster (local, miễn phí)
- GCP Provider for Crossplane
- Composite Resource Definitions (XRDs) — abstract Cloud SQL, GCS
- Compositions — "1 click" tạo full database + user + secret
- **Test**: `kubectl apply` XR → GCP resource tạo tự động ✅

#### Tuần 19-20 — Crossplane + Backstage Integration
- Backstage templates trigger Crossplane claims
- Self-service: developer request DB → Crossplane provisions → Backstage shows status
- GitOps cho Crossplane configs (ArgoCD)
- **Test**: Developer dùng Backstage form → DB tạo tự động → connection string trong Secret ✅

> **Chi phí tháng 5**: ~$30 (chủ yếu local, chỉ GCP resource nhỏ cho test)

---

### Tháng 6: Policy & Governance — "AI Safety Net"

> **Xu hướng 2026**: Platform phải review AI-generated code/IaC trước khi deploy.

#### Tuần 21-22 — Policy-as-Code
- OPA Gatekeeper policies cho K8s (chạy trên kind)
- Kyverno — alternative, YAML-native policies
- Policies: no privileged pods, required labels, resource limits
- CI gate: `conftest` validate Terraform plans trước khi apply
- **Test**: Deploy vi phạm policy → bị chặn ✅

#### Tuần 23-24 — Platform Governance
- RBAC design cho multi-team
- Namespace-per-team strategy
- Audit logging
- Compliance reports tự động
- **Deliverable**: "Platform Engineering Handbook" — tài liệu Golden Paths cho team

> **Chi phí tháng 6**: ~$20 (gần hết chạy local)

---

## Phase 3: Production Patterns (Tháng 7-9, $100/tháng)

*Chạy chủ yếu trên local K8s (kind/minikube), cloud khi cần test thật.*

### Tháng 7: Service Mesh — Istio

#### Tuần 25-26 — Istio trên kind
- Cài Istio ambient mode (không cần sidecar)
- mTLS tự động giữa services
- Traffic management: canary deployment, traffic splitting
- **Test**: Deploy v2 → route 10% traffic → xem metrics → tăng dần ✅

#### Tuần 27-28 — Observability với Service Mesh
- Kiali dashboard — visualize service topology
- Jaeger distributed tracing (integrated with Istio)
- Rate limiting, circuit breaking qua Istio
- **Test**: Inject latency fault → circuit breaker kích hoạt → Grafana alert ✅

> **Chi phí tháng 7**: ~$20 (kind cluster local)

---

### Tháng 8: FinOps & Cost Engineering

#### Tuần 29-30 — FinOps Dashboard
- Kubecost (open-source) — per-namespace cost allocation
- GCP Billing Export → BigQuery → Data Studio dashboard
- Infracost trong CI pipeline
- Rightsizing recommendations tự động

#### Tuần 31-32 — Cost Optimization Thực Chiến
- Spot/Preemptible VM strategy
- Committed Use Discounts analysis
- Cluster autoscaler tuning
- Idle resource detection & cleanup automation
- **Deliverable**: Cost report + optimization recommendations

> **Chi phí tháng 8**: ~$50 (cần GKE thật để đo cost)

---

### Tháng 9: Multi-cluster & Disaster Recovery

#### Tuần 33-34 — Multi-cluster Management
- Fleet management (GKE Hub)
- Config Sync — GitOps for fleet
- Multi-cluster services (MCS)

#### Tuần 35-36 — DR Testing
- Full disaster recovery simulation
- RTO/RPO measurement
- Database backup & restore automation
- Chaos engineering basics (Chaos Mesh)
- **Deliverable**: DR Runbook + tested procedures

> **Chi phí tháng 9**: ~$80 (multi-cluster cần 2 clusters)

---

## Phase 4: AI-Native Platform (Tháng 10-12, $100/tháng)

*Đỉnh cao — kết hợp AI vào platform engineering.*

### Tháng 10: AI-Assisted Operations

#### Tuần 37-38 — AI cho IaC Review
- LLM review Terraform plans (tích hợp vào CI)
- AI-generated runbooks từ incident history
- Chatbot trả lời platform questions (RAG trên docs của bạn)

#### Tuần 39-40 — AIOps
- Anomaly detection trên metrics (Python + LLM)
- Auto-remediation scripts triggered by alerts
- Log analysis với AI (pattern recognition)
- **Test**: Inject anomaly → AI detect → auto-fix → notify ✅

> **Chi phí tháng 10**: ~$40 (chủ yếu API calls LLM)

---

### Tháng 11: MLOps Basics

#### Tuần 41-42 — ML Pipeline trên K8s
- Kubeflow Pipelines trên kind cluster
- Simple ML model (Go/Python) → containerize → serve
- Model versioning & A/B testing

#### Tuần 43-44 — GPU Orchestration (Theory + Small Scale)
- NVIDIA GPU Operator concepts
- GPU sharing strategies (time-slicing, MIG)
- GKE GPU node pool (dùng g2-standard-4 Spot, test nhanh rồi destroy)
- **Test**: ML inference endpoint trên GKE với GPU ✅

> **Chi phí tháng 11**: ~$60 (GPU Spot ~$0.5/hr, chạy vài giờ)

---

### Tháng 12: Capstone Project — Production-Grade Platform

#### Tuần 45-48 — Tổng hợp tất cả
- Dựng lại TOÀN BỘ platform từ scratch, apply tất cả kiến thức 11 tháng
- Full stack: VPC → GKE → CI/CD → ArgoCD → Backstage → Monitoring → Policy
- Viết "Platform Engineering Portfolio" showcase:
  - Architecture diagrams
  - GitHub repos with README
  - Blog posts about lessons learned
  - **Deliverable**: Portfolio sẵn sàng cho interview

> **Chi phí tháng 12**: ~$80 (full stack 2 tuần)

---

## 📊 Tổng chi phí cả năm

| Phase | Tháng | Credit | Tiền riêng | Tổng |
|-------|--------|--------|------------|------|
| Phase 1 | 1-3 | $300 | $300 | $600 |
| Phase 2 | 4-6 | — | $300 | $300 |
| Phase 3 | 7-9 | — | $300 | $300 |
| Phase 4 | 10-12 | — | $300 | $300 |
| **Total** | **12 tháng** | **$300** | **$1,200** | **$1,500** |

> [!TIP]
> Chi phí thực tế có thể **thấp hơn $1,500** nếu nghiêm túc destroy cuối tuần và tận dụng local K8s (kind) cho Phase 2-4.

---

## 🎯 Kỹ năng đạt được sau 12 tháng

```
Infrastructure     ████████████████████ 100%  (VPC, GKE, Cloud SQL, NAT)
Kubernetes         ████████████████████ 100%  (Clusters, Helm, HPA, Network Policy)
Terraform/IaC      ████████████████████ 100%  (Modules, Workspaces, CI integration)
CI/CD              ████████████████████  95%  (GitHub Actions, ArgoCD, GitOps)
Security           ████████████████████  90%  (IAM, Secrets, Policy-as-Code, mTLS)
Observability      ████████████████████  90%  (Prometheus, Grafana, OpenTelemetry)
Developer Platform ████████████████████  85%  (Backstage, Crossplane, Golden Paths)
Service Mesh       ████████████████████  75%  (Istio ambient, traffic management)
AI/MLOps           ████████████████████  60%  (Kubeflow basics, AIOps)
FinOps             ████████████████████  70%  (Cost allocation, optimization)
```
