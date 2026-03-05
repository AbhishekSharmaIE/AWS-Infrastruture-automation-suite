<p align="center">
  <img src="https://img.shields.io/badge/Terraform-%3E%3D1.5-844FBA?style=for-the-badge&logo=terraform&logoColor=white" alt="Terraform">
  <img src="https://img.shields.io/badge/AWS-Cloud-FF9900?style=for-the-badge&logo=amazonwebservices&logoColor=white" alt="AWS">
  <img src="https://img.shields.io/badge/Python-3.10+-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/Kubernetes-EKS%201.29-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes">
  <img src="https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?style=for-the-badge&logo=githubactions&logoColor=white" alt="GitHub Actions">
  <img src="https://img.shields.io/badge/IaC-CloudFormation-FF4F8B?style=for-the-badge&logo=amazonaws&logoColor=white" alt="CloudFormation">
</p>

# AWS Infrastructure Automation Suite

> End-to-end, production-grade AWS infrastructure provisioned via Terraform, orchestrated with Python, secured with WAF, and observed through CloudWatch + Prometheus/Grafana -- shipped through a fully automated GitHub Actions CI/CD pipeline.

---

## Why This Project?

Most Terraform demos stop at `terraform apply`. This project goes further by solving the **real-world operational problems** that come *after* provisioning:

- **Drift Detection** -- automated checks that catch manual console changes before they cause incidents.
- **Self-Healing Infrastructure** -- Lambda-based auto-remediation that responds to CloudWatch alarms in real time (Aurora scale-out, pod restarts, 5xx mitigation).
- **Cost Governance** -- daily anomaly detection and monthly cost reports pushed via SNS, not just a dashboard you forget to check.
- **One-Command Lifecycle** -- bootstrap, deploy, monitor, and tear down an entire environment with a single `make` target.

---

## Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │              AWS Cloud (us-east-1)          │
                    │                                             │
                    │  ┌───────────────────────────────────────┐  │
                    │  │            WAF v2 (Web ACL)           │  │
                    │  │  CommonRuleSet · KnownBadInputs · SQLi│  │
                    │  │        Rate Limit: 2000 req/IP        │  │
                    │  └──────────────────┬────────────────────┘  │
                    │                     │                       │
                    │  ┌──────────────────▼────────────────────┐  │
                    │  │     Application Load Balancer (ALB)    │  │
                    │  │         HTTP → Target Group :8080      │  │
                    │  └──────────────────┬────────────────────┘  │
                    │                     │                       │
                    │  ┌──────────────────▼────────────────────┐  │
                    │  │          Amazon EKS (v1.29)            │  │
                    │  │  ┌─────────┐ ┌──────────┐ ┌────────┐  │  │
                    │  │  │Autoscale│ │ Metrics  │ │Promethe│  │  │
                    │  │  │  r      │ │ Server   │ │us+Graf │  │  │
                    │  │  └─────────┘ └──────────┘ └────────┘  │  │
                    │  │       Private Subnets (3 AZs)         │  │
                    │  └──────────────────┬────────────────────┘  │
                    │          ┌──────────┼──────────┐            │
                    │          │          │          │            │
                    │  ┌───────▼──┐ ┌────▼───┐ ┌────▼─────┐     │
                    │  │  Aurora   │ │ Redis  │ │    S3    │     │
                    │  │PostgreSQL │ │ 7.0    │ │ (Logs +  │     │
                    │  │  16.6     │ │Encrypt │ │  State)  │     │
                    │  └──────────┘ └────────┘ └──────────┘     │
                    │       Database Subnets (isolated)          │
                    │                                             │
                    │  ┌───────────────────────────────────────┐  │
                    │  │           CloudWatch                   │  │
                    │  │  7 Alarms · Dashboard · SNS Alerts    │  │
                    │  └──────────────┬────────────────────────┘  │
                    │                 │  triggers                  │
                    │  ┌──────────────▼────────────────────────┐  │
                    │  │      Lambda (Auto-Remediation)         │  │
                    │  │  Aurora scale-out · Pod refresh · 5xx  │  │
                    │  └───────────────────────────────────────┘  │
                    └─────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Provisioning** | Terraform (HCL) | Declarative infrastructure-as-code with remote S3/DynamoDB state backend |
| **Compute** | Amazon EKS 1.29 | Managed Kubernetes with managed node groups |
| **Database** | Aurora PostgreSQL 16.6 | Encrypted relational store with CloudWatch audit logs |
| **Cache** | ElastiCache Redis 7.0 | In-memory caching with at-rest + in-transit encryption |
| **Networking** | VPC, ALB, WAFv2 | 3-AZ VPC, application load balancing, Layer 7 firewall |
| **Observability** | CloudWatch, Prometheus, Grafana | Alarms, dashboards, full-stack Kubernetes metrics |
| **Automation** | Python 3.10+, Bash | Deploy orchestration, health checks, drift detection, cost reporting |
| **Serverless** | AWS Lambda | Event-driven auto-remediation and cost anomaly detection |
| **CI/CD** | GitHub Actions | Validate on PR, plan preview, apply on merge, scheduled cost reports |
| **Bootstrap** | CloudFormation | One-click state backend (S3 + DynamoDB + IAM + GitHub OIDC) |

---

## Project Structure

```
.
├── terraform/                          # ── Infrastructure as Code ──────────────
│   ├── main.tf                         #   VPC, EKS, Aurora, Redis, ALB, WAF, SNS
│   ├── monitoring.tf                   #   CloudWatch alarms (7) + dashboard
│   ├── variables.tf                    #   Typed inputs with validation & defaults
│   ├── outputs.tf                      #   Cluster endpoints, DB URIs, dashboard URL
│   ├── versions.tf                     #   Provider pins + S3 backend config
│   └── environments/
│       ├── dev/terraform.tfvars        #   Development sizing & config
│       ├── staging/terraform.tfvars    #   Staging sizing & config
│       └── prod/terraform.tfvars       #   Production sizing & config
│
├── cloudformation/                     # ── Bootstrap & IAM ─────────────────────
│   ├── bootstrap.yaml                  #   S3 state bucket, DynamoDB, IAM, OIDC
│   └── iam-roles.yaml                  #   IRSA roles for EKS workloads
│
├── python/                             # ── Automation & Operations ─────────────
│   ├── deploy.py                       #   Deployment orchestrator (pre-flight → apply → post-deploy)
│   ├── scripts/
│   │   ├── health_check.py             #   Multi-resource health checker with continuous mode
│   │   ├── cost_reporter.py            #   Cost Explorer analysis + SNS delivery
│   │   └── drift_detector.py           #   Terraform drift + security posture checks
│   └── lambda/
│       ├── auto_remediation.py         #   CloudWatch alarm → automated fix
│       └── cost_anomaly.py             #   Daily spend anomaly detection
│
├── kubernetes/                         # ── Cluster Add-ons ─────────────────────
│   ├── cluster-autoscaler.yaml         #   Node autoscaling (ASG discovery)
│   ├── metrics-server.yaml             #   HPA metrics provider
│   └── monitoring/
│       ├── prometheus-values.yaml      #   kube-prometheus-stack Helm values
│       └── grafana-dashboards.yaml     #   Custom EKS/Node/Pod dashboards
│
├── scripts/                            # ── Shell Wrappers ──────────────────────
│   ├── bootstrap.sh                    #   One-time state backend provisioning
│   ├── deploy.sh                       #   Deploy entrypoint (wraps deploy.py)
│   └── destroy.sh                      #   Safe teardown with prod safeguards
│
├── .github/workflows/
│   └── terraform.yaml                  #   Full CI/CD pipeline
│
├── Makefile                            #   22 developer-facing targets
├── requirements.txt                    #   Python dependencies (boto3, rich, httpx, pyyaml)
├── CONTRIBUTING.md                     #   Contribution guidelines
├── CODEOWNERS                          #   Code review ownership
├── .pre-commit-config.yaml             #   Pre-commit hooks (fmt, lint, security)
├── .tfsec.yml                          #   Static security analysis config
├── .editorconfig                       #   Consistent formatting across editors
└── .gitignore                          #   Comprehensive ignore rules
```

**29 Terraform resources** | **6 Python automation scripts** | **4 Kubernetes manifests** | **3 environment configs** | **22 Makefile targets**

---

## Features in Depth

### Infrastructure Provisioning (Terraform)

- **VPC**: 3-AZ deployment across public, private, and isolated database subnets with NAT gateway and proper route tables.
- **EKS Cluster**: Managed Kubernetes 1.29 with API server and audit logging, configurable node group sizing per environment.
- **Aurora PostgreSQL**: Encrypted cluster (KMS) with CloudWatch log exports, auto-generated master password via `random_password`.
- **ElastiCache Redis**: Replication group with at-rest encryption, private subnet placement, dedicated security group.
- **ALB + WAF**: Application Load Balancer fronted by WAFv2 with three AWS-managed rule groups and IP-based rate limiting at 2,000 requests per 5-minute window.
- **SNS Topics**: Separate alert and critical notification channels for CloudWatch alarm routing.

### Monitoring & Alerting (CloudWatch + Prometheus)

| Alarm | Threshold | Target |
|-------|-----------|--------|
| ALB 5xx Errors | > 50 in 5 min | SNS Critical |
| ALB p99 Latency | > 5 seconds | SNS Alerts |
| Aurora CPU | > 80% | SNS Alerts |
| Aurora Connections | > 100 | SNS Alerts |
| Redis CPU | > 75% | SNS Alerts |
| Redis Memory | > 80% | SNS Critical |
| EKS Node CPU | > 80% | SNS Alerts |

Plus a consolidated CloudWatch dashboard with ALB request rates, EKS node metrics, Aurora performance, and Redis utilization -- all in one pane.

On the Kubernetes side, the **kube-prometheus-stack** deploys Prometheus (2 replicas) + Grafana with custom dashboards for cluster, node, and pod-level observability.

### Auto-Remediation (Lambda)

The `auto_remediation.py` Lambda responds to CloudWatch alarm state changes and executes targeted fixes:

| Trigger | Automated Response |
|---------|--------------------|
| Aurora CPU > threshold | Scale out read replica |
| EKS pod crash loops | Force pod refresh via rollout restart |
| ALB 5xx spike | Capture diagnostics, notify on-call |
| Redis memory pressure | Trigger eviction analysis |
| ECR image scan findings | Quarantine affected images |

### Cost Intelligence

- **Cost Reporter** (`cost_reporter.py`): Queries AWS Cost Explorer for breakdown by service, daily trends, and 30-day forecasts. Outputs rich terminal tables or delivers via SNS.
- **Cost Anomaly Lambda** (`cost_anomaly.py`): Runs daily, compares current spend against rolling averages, fires SNS alerts when deviation exceeds configurable thresholds.

### Drift Detection

`drift_detector.py` performs two-layer checks:

1. **Terraform Drift**: Runs `terraform plan` and parses output for unexpected resource changes.
2. **Security Posture**: Validates S3 public access blocks, security group rules, encryption status, and EKS endpoint configuration against expected baselines.

### CI/CD Pipeline (GitHub Actions)

```
  PR opened/updated          merge to main            manual dispatch          cron (daily)
        │                         │                        │                       │
        ▼                         ▼                        ▼                       ▼
  ┌───────────┐           ┌──────────────┐         ┌─────────────┐        ┌──────────────┐
  │ Validate  │           │ Auto-apply   │         │ Apply or    │        │ Cost Report  │
  │ fmt + lint│           │ to dev       │         │ Destroy any │        │ via SNS      │
  │ tf plan   │           │              │         │ environment │        │              │
  │ → PR comment│         │              │         │              │        │              │
  └───────────┘           └──────────────┘         └─────────────┘        └──────────────┘
```

- **OIDC authentication** -- no long-lived AWS credentials stored in GitHub.
- **Plan output posted as PR comment** for peer review before any infrastructure change.
- **Environment protection rules** for staging and production gates.

---

## Quick Start

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| AWS CLI | v2 | [docs.aws.amazon.com/cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Terraform | >= 1.5.0 | [terraform.io/downloads](https://www.terraform.io/downloads) |
| Python | >= 3.10 | [python.org](https://www.python.org/downloads/) |
| kubectl | >= 1.29 | [kubernetes.io/docs](https://kubernetes.io/docs/tasks/tools/) |
| Helm | >= 3.x | [helm.sh/docs](https://helm.sh/docs/intro/install/) |

### 1. Clone & Install

```bash
git clone git@github.com:AbhishekSharmaIE/AWS-Infrastruture-automation-suite.git
cd AWS-Infrastruture-automation-suite
pip install -r requirements.txt
```

### 2. Bootstrap State Backend

```bash
make bootstrap PROJECT=awsinfra ENV=dev REGION=us-east-1
```

Creates the S3 bucket (versioned, encrypted) and DynamoDB table for Terraform state locking.

### 3. Configure Environment

```bash
# Edit environment-specific variables
vim terraform/environments/dev/terraform.tfvars
```

### 4. Deploy

```bash
make plan  PROJECT=awsinfra ENV=dev    # Preview changes
make apply PROJECT=awsinfra ENV=dev    # Provision infrastructure
```

### 5. Post-Deploy Setup

```bash
make update-kubeconfig PROJECT=awsinfra ENV=dev   # Configure kubectl
make install-monitoring                            # Deploy Prometheus + Grafana
make install-autoscaler                            # Deploy Cluster Autoscaler
```

### 6. Operations

```bash
make health  PROJECT=awsinfra ENV=dev   # Run health checks
make drift   PROJECT=awsinfra ENV=dev   # Detect configuration drift
make cost    PROJECT=awsinfra ENV=dev   # Generate cost report
```

### 7. Tear Down

```bash
make destroy PROJECT=awsinfra ENV=dev   # Destroy all resources
```

> Production environments require typing the project name + `destroy-prod` as a safety gate.

---

## Environment Sizing

| Resource | Dev | Staging | Prod |
|----------|-----|---------|------|
| EKS Nodes | 2x `m6i.xlarge` | 3x `m6i.xlarge` | 6x `m6i.2xlarge` + spot fleet |
| Aurora Instances | 1 writer | 1 writer + 1 reader | Multi-region, auto-scaling |
| Redis Nodes | 1 node | 1 node | 3 nodes, multi-AZ |
| NAT Gateways | 1 (shared) | 1 (shared) | 3 (per AZ, HA) |
| **Est. Monthly Cost** | **~$550** | **~$900** | **~$4,500** |

---

## Security Posture

| Control | Implementation |
|---------|---------------|
| **Network Isolation** | Private subnets for compute, isolated database subnets, security groups with least-privilege rules |
| **Web Application Firewall** | WAFv2 with AWS CommonRuleSet, KnownBadInputs, SQLi protection, IP rate limiting |
| **Encryption at Rest** | S3 (SSE-S3), Aurora (KMS), Redis (at-rest), EBS (default encryption) |
| **Encryption in Transit** | Redis in-transit encryption, ALB TLS termination |
| **Secrets Management** | Auto-generated DB passwords via `random_password`, no secrets in code |
| **State Security** | S3 backend with versioning, DynamoDB locking, encrypted state files |
| **IAM** | IRSA for pod-level AWS permissions, scoped roles per workload |
| **CI/CD Auth** | GitHub OIDC -- no static credentials, short-lived session tokens |
| **Static Analysis** | tfsec for Terraform security scanning, pre-commit hooks |
| **Code Ownership** | `CODEOWNERS` file enforcing review requirements |

---

## Makefile Reference

```bash
make help                # Show all available targets
make bootstrap           # Provision S3 + DynamoDB state backend
make init                # Initialize Terraform
make plan                # Generate execution plan
make apply               # Apply infrastructure changes
make apply-auto          # Apply without interactive confirmation
make destroy             # Tear down infrastructure
make validate            # Validate Terraform configuration
make fmt                 # Format Terraform files
make lint                # Run tfsec security linter
make lint-python         # Run ruff on Python code
make test                # Run test suite
make health              # Execute health checks
make drift               # Run drift detection
make cost                # Generate cost estimate
make cost-report         # Publish cost report via SNS
make update-kubeconfig   # Configure kubectl for EKS
make install-monitoring  # Deploy Prometheus + Grafana stack
make install-autoscaler  # Deploy Cluster Autoscaler
make dashboard           # Open CloudWatch dashboard URL
make deps                # Install Python dependencies
make clean               # Remove local Terraform artifacts
make tree                # Display project structure
```

---

## Built With

<p>
  <img src="https://img.shields.io/badge/Terraform-844FBA?style=flat-square&logo=terraform&logoColor=white" alt="Terraform">
  <img src="https://img.shields.io/badge/AWS-FF9900?style=flat-square&logo=amazonwebservices&logoColor=white" alt="AWS">
  <img src="https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white" alt="Kubernetes">
  <img src="https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat-square&logo=githubactions&logoColor=white" alt="GitHub Actions">
  <img src="https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white" alt="Prometheus">
  <img src="https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white" alt="Grafana">
  <img src="https://img.shields.io/badge/Helm-0F1689?style=flat-square&logo=helm&logoColor=white" alt="Helm">
  <img src="https://img.shields.io/badge/CloudWatch-FF4F8B?style=flat-square&logo=amazonaws&logoColor=white" alt="CloudWatch">
  <img src="https://img.shields.io/badge/Redis-DC382D?style=flat-square&logo=redis&logoColor=white" alt="Redis">
  <img src="https://img.shields.io/badge/PostgreSQL-4169E1?style=flat-square&logo=postgresql&logoColor=white" alt="PostgreSQL">
</p>

---

## License

This project is licensed under the MIT License.
