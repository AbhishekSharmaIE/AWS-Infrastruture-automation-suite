# ─── Providers ─────────────────────────────────────────────────────────────────

provider "aws" {
  alias  = "primary"
  region = var.primary_region
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags { tags = local.common_tags }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.primary_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.primary_region]
    }
  }
}

# ─── Locals ────────────────────────────────────────────────────────────────────

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Team        = var.team_name
    CostCenter  = var.cost_center
    Repository  = "aws-infra-suite"
  }

  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── Data Sources ──────────────────────────────────────────────────────────────

data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
}

data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_region" "primary" {
  provider = aws.primary
}

data "aws_route53_zone" "main" {
  provider = aws.primary
  name     = var.domain_name
}

# ─── VPC Primary ──────────────────────────────────────────────────────────────

module "vpc_primary" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  providers = { aws = aws.primary }

  name = "${local.name_prefix}-primary"
  cidr = var.primary_vpc_cidr
  azs  = slice(data.aws_availability_zones.primary.names, 0, 3)

  private_subnets  = var.primary_private_subnets
  public_subnets   = var.primary_public_subnets
  database_subnets = var.primary_database_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "prod"
  enable_dns_hostnames   = true
