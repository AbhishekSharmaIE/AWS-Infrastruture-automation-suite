# AWS Infrastructure Automation Suite

Production-grade, multi-region AWS infrastructure managed with Terraform, automated with Python, and monitored with CloudWatch + Prometheus/Grafana.

## Architecture

```
                          ┌─────────────────────────┐
                          │       Route53            │
                          │   (Failover Routing)     │
                          └────────┬────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
            ┌───────▼───────┐            ┌───────▼───────┐
            │  us-east-1    │            │  eu-west-1    │
            │  (Primary)    │◄──Peering──►  (Secondary)  │
            └───────┬───────┘            └───────┬───────┘
                    │                             │
        ┌───────────┼───────────┐                 │
        │           │           │                 │
   ┌────▼──┐  ┌────▼──┐  ┌────▼────┐       ┌────▼──┐
   │  WAF  │  │  ALB  │  │  EKS    │       │Aurora │
   │       │  │       │  │ Cluster │       │Reader │
   └───────┘  └───────┘  └────┬────┘       └───────┘
                               │
                    ┌──────────┼──────────┐
                    │          │          │
              ┌─────▼──┐ ┌────▼───┐ ┌────▼────┐
              │ Aurora  │ │ Redis  │ │   S3    │
              │ Writer  │ │Cluster │ │ Buckets │
              └────────┘ └────────┘ └─────────┘
```

## What's Included

| Component | Description |
|-----------|-------------|
| **VPC** | Multi-region with peering, 3-AZ, public/private/database subnets, flow logs |
| **EKS** | Managed Kubernetes with on-demand, spot, and memory-optimized node groups |
| **Aurora** | PostgreSQL Global Database with cross-region replication and auto-scaling |
| **ElastiCache** | Redis with auth tokens, encryption at rest/transit, multi-AZ (prod) |
| **ALB** | Application Load Balancer with HTTPS, HTTP→HTTPS redirect, access logs |
| **WAF** | AWS managed rules (Common, BadInputs, SQLi) + rate limiting + geo-blocking |
| **Route53** | Failover routing with health checks across 3 regions |
| **CloudWatch** | Full dashboard, 10+ alarms, custom metrics from health checks |
| **Prometheus** | kube-prometheus-stack with Grafana dashboards for EKS monitoring |
| **Lambda** | Auto-remediation (Aurora scale-out, pod refresh) + cost anomaly detection |
| **CI/CD** | GitHub Actions with OIDC auth, plan on PR, apply on merge |

## Project Structure

```
.
├── terraform/                    # Infrastructure as Code
│   ├── main.tf                   # Core resources (VPC, EKS, Aurora, Redis, ALB, WAF, Route53)
│   ├── monitoring.tf             # CloudWatch alarms and dashboard
│   ├── variables.tf              # Input variables with validation
│   ├── outputs.tf                # Output values
│   ├── versions.tf               # Provider and backend configuration
│   ├── environments/
│   │   ├── dev/terraform.tfvars
│   │   ├── staging/terraform.tfvars
│   │   └── prod/terraform.tfvars
│   └── modules/                  # Placeholder for custom modules
├── cloudformation/
│   ├── bootstrap.yaml            # S3 state bucket + DynamoDB lock + IAM roles
│   └── iam-roles.yaml            # IRSA roles for EKS workloads
├── python/
│   ├── deploy.py                 # Main deployment orchestrator
│   ├── scripts/
│   │   ├── health_check.py       # Multi-region health checker
│   │   ├── cost_reporter.py      # Cost analysis with Cost Explorer API
│   │   └── drift_detector.py     # Infrastructure drift detection
│   └── lambda/
│       ├── auto_remediation.py   # Automated incident response
│       └── cost_anomaly.py       # Spending anomaly detection
├── kubernetes/
│   ├── cluster-autoscaler.yaml   # Cluster Autoscaler with RBAC
│   ├── metrics-server.yaml       # Metrics Server for HPA
│   └── monitoring/
│       ├── prometheus-values.yaml # Helm values for kube-prometheus-stack
│       └── grafana-dashboards.yaml
├── scripts/
│   ├── bootstrap.sh              # One-time state backend setup
│   ├── deploy.sh                 # Deployment wrapper
│   └── destroy.sh                # Safe teardown with confirmation
├── .github/workflows/
│   └── terraform.yaml            # CI/CD pipeline
├── Makefile                      # Developer commands
├── requirements.txt              # Python dependencies
└── .gitignore
```

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- Python >= 3.10
- kubectl and helm (for EKS management)

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Bootstrap State Backend (one-time per environment)

```bash
make bootstrap PROJECT=myproject ENV=dev REGION=us-east-1
```

This creates the S3 bucket for Terraform state and DynamoDB table for locking.

### 3. Configure Variables

Edit the environment-specific tfvars file:

```bash
vim terraform/environments/dev/terraform.tfvars
```

Key variables to set:
- `project_name` - Your project identifier
- `domain_name` - Route53 hosted zone domain
- `alarm_email` - Email for CloudWatch alerts
- `cost_center` - Billing tag

### 4. Plan and Apply

```bash
# See what will be created
make plan PROJECT=myproject ENV=dev

# Apply the changes
make apply PROJECT=myproject ENV=dev

# Or apply without confirmation (CI/CD)
make apply-auto PROJECT=myproject ENV=dev
```

### 5. Post-Deploy Operations

```bash
# Configure kubectl
make update-kubeconfig PROJECT=myproject ENV=dev

# Install monitoring stack
make install-monitoring

# Run health checks
make health PROJECT=myproject ENV=dev

# Check for drift
make drift PROJECT=myproject ENV=dev

# View cost estimate
make cost PROJECT=myproject ENV=dev
```

## Environment Sizing

| Resource | Dev | Staging | Prod |
|----------|-----|---------|------|
| EKS Nodes | 2x m6i.xlarge | 3x m6i.xlarge | 6x m6i.2xlarge + spot |
| Aurora | 1 writer | 1 writer + 1 reader | Global DB, 2 regions |
| Redis | 1 node | 1 node | 3 nodes, multi-AZ |
| NAT Gateways | 1 (shared) | 1 (shared) | 3 per region |
| Estimated Cost | ~$550/mo | ~$900/mo | ~$4,500/mo |

## CI/CD Pipeline

The GitHub Actions workflow provides:

1. **On PR**: Format check, linting, Terraform plan posted as PR comment
2. **On merge to main**: Auto-apply to dev environment
3. **Manual dispatch**: Apply or destroy any environment with approval gates
4. **Scheduled**: Daily cost reports

### Setup

1. Create an OIDC provider in AWS (done by `bootstrap.yaml`)
2. Set repository variables:
   - `AWS_ROLE_ARN` - IAM role ARN for GitHub Actions
   - `AWS_ACCOUNT_ID` - AWS account ID
3. Configure environment protection rules in GitHub for staging/prod

## Operations Runbook

### Health Checks

```bash
# One-time check
python python/scripts/health_check.py --project myproject --env prod

# Continuous monitoring (every 60s)
python python/scripts/health_check.py --project myproject --env prod --continuous --interval 60
```

### Cost Management

```bash
# Monthly cost report
python python/scripts/cost_reporter.py --project myproject --env prod --period monthly

# Send report via SNS
python python/scripts/cost_reporter.py --project myproject --env prod --sns-topic arn:aws:sns:...
```

### Drift Detection

```bash
# Full drift check (Terraform + security)
python python/scripts/drift_detector.py --project myproject --env prod

# Security-only check
python python/scripts/drift_detector.py --project myproject --env prod --security-only
```

### Tear Down

```bash
# Dev/staging (simple confirmation)
make destroy PROJECT=myproject ENV=dev

# Production (requires typing project name + 'destroy-prod')
make destroy PROJECT=myproject ENV=prod
```

## Security Features

- **WAF**: AWS managed rulesets (CommonRuleSet, KnownBadInputs, SQLi) + IP rate limiting
- **Encryption**: S3 (KMS), Aurora (KMS), Redis (at-rest + in-transit), EBS (default)
- **Network**: VPC flow logs, private subnets for workloads, database subnets isolated
- **IAM**: IRSA for pod-level permissions, least-privilege Terraform role
- **TLS**: ACM certificates with auto-renewal, TLS 1.3 policy on ALB
- **State**: Encrypted S3 backend with DynamoDB locking, versioned state files

## License

MIT
