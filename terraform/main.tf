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
  enable_dns_support     = true

  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                     = "1"
    "kubernetes.io/cluster/${local.name_prefix}" = "owned"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb"                              = "1"
    "kubernetes.io/cluster/${local.name_prefix}" = "owned"
  }

  tags = local.common_tags
}

# ─── VPC Secondary ────────────────────────────────────────────────────────────

module "vpc_secondary" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  providers = { aws = aws.secondary }

  name = "${local.name_prefix}-secondary"
  cidr = var.secondary_vpc_cidr
  azs  = slice(data.aws_availability_zones.secondary.names, 0, 3)

  private_subnets  = var.secondary_private_subnets
  public_subnets   = var.secondary_public_subnets
  database_subnets = var.secondary_database_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "prod"
  enable_dns_hostnames   = true
  enable_dns_support     = true

  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  tags = local.common_tags
}

# ─── VPC Peering ──────────────────────────────────────────────────────────────

resource "aws_vpc_peering_connection" "cross_region" {
  provider    = aws.primary
  vpc_id      = module.vpc_primary.vpc_id
  peer_vpc_id = module.vpc_secondary.vpc_id
  peer_region = var.secondary_region
  auto_accept = false
  tags        = { Name = "${local.name_prefix}-cross-region-peering" }
}

resource "aws_vpc_peering_connection_accepter" "cross_region" {
  provider                  = aws.secondary
  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region.id
  auto_accept               = true
  tags                      = { Name = "${local.name_prefix}-cross-region-peering" }
}

resource "aws_route" "primary_to_secondary" {
  count                     = length(module.vpc_primary.private_route_table_ids)
  provider                  = aws.primary
  route_table_id            = module.vpc_primary.private_route_table_ids[count.index]
  destination_cidr_block    = var.secondary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region.id
}

resource "aws_route" "secondary_to_primary" {
  count                     = length(module.vpc_secondary.private_route_table_ids)
  provider                  = aws.secondary
  route_table_id            = module.vpc_secondary.private_route_table_ids[count.index]
  destination_cidr_block    = var.primary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region.id
}

# ─── EKS Cluster ──────────────────────────────────────────────────────────────

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  providers = { aws = aws.primary }

  cluster_name    = local.name_prefix
  cluster_version = var.kubernetes_version

  vpc_id                          = module.vpc_primary.vpc_id
  subnet_ids                      = module.vpc_primary.private_subnets
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  cluster_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        computeType = "Fargate"
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = { ENABLE_PREFIX_DELEGATION = "true" }
      })
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
    aws-efs-csi-driver = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    general = {
      name           = "${local.name_prefix}-general"
      instance_types = var.eks_on_demand_instance_types
      capacity_type  = "ON_DEMAND"
      min_size       = var.eks_min_size
      max_size       = var.eks_max_size
      desired_size   = var.eks_desired_size
      disk_size      = 100

      labels = {
        role        = "general"
        environment = var.environment
      }

      update_config = {
        max_unavailable_percentage = 33
      }
    }

    spot = {
      name           = "${local.name_prefix}-spot"
      instance_types = var.eks_spot_instance_types
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 30
      desired_size   = var.environment == "prod" ? 3 : 0
      disk_size      = 50

      labels = {
        role        = "spot"
        environment = var.environment
      }

      taints = [{
        key    = "spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }

    memory_optimized = {
      name           = "${local.name_prefix}-mem"
      instance_types = ["r6i.xlarge", "r6i.2xlarge"]
      capacity_type  = "ON_DEMAND"
      min_size       = 0
      max_size       = 10
      desired_size   = 0
      disk_size      = 200

      labels = {
        role = "memory-optimized"
      }
    }
  }

  tags = local.common_tags
}

# ─── RDS Aurora Global ────────────────────────────────────────────────────────

resource "aws_rds_global_cluster" "main" {
  provider                  = aws.primary
  global_cluster_identifier = "${local.name_prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.aurora_engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.environment == "prod"
}

module "aurora_primary" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 9.0"
  providers = { aws = aws.primary }

  name           = "${local.name_prefix}-aurora-primary"
  engine         = "aurora-postgresql"
  engine_version = var.aurora_engine_version
  instance_class = var.aurora_instance_class

  instances = {
    writer   = { instance_class = var.aurora_instance_class }
    reader-1 = { instance_class = var.aurora_reader_class }
  }

  global_cluster_identifier = aws_rds_global_cluster.main.id
  is_primary_cluster        = true

  vpc_id               = module.vpc_primary.vpc_id
  db_subnet_group_name = module.vpc_primary.database_subnet_group_name
  security_group_rules = {
    ingress_from_vpc = {
      cidr_blocks = [var.primary_vpc_cidr]
    }
  }

  storage_encrypted   = true
  monitoring_interval = 60
  deletion_protection = var.environment == "prod"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  autoscaling_enabled      = true
  autoscaling_min_capacity = 1
  autoscaling_max_capacity = var.aurora_max_replicas
  autoscaling_target_cpu   = 70

  backup_retention_period      = var.environment == "prod" ? 35 : 7
  preferred_backup_window      = "02:00-03:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  apply_immediately = var.environment != "prod"

  tags = local.common_tags
}

module "aurora_secondary" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 9.0"
  providers = { aws = aws.secondary }

  name           = "${local.name_prefix}-aurora-secondary"
  engine         = "aurora-postgresql"
  engine_version = var.aurora_engine_version
  instance_class = var.aurora_reader_class
  instances      = { reader-1 = {} }

  global_cluster_identifier = aws_rds_global_cluster.main.id
  is_primary_cluster        = false
  source_region             = var.primary_region

  vpc_id               = module.vpc_secondary.vpc_id
  db_subnet_group_name = module.vpc_secondary.database_subnet_group_name
  security_group_rules = {
    ingress_from_vpc = {
      cidr_blocks = [var.secondary_vpc_cidr]
    }
  }

  storage_encrypted = true

  depends_on = [module.aurora_primary]
  tags       = local.common_tags
}

# ─── ElastiCache Redis ────────────────────────────────────────────────────────

resource "random_password" "redis_auth" {
  length  = 32
  special = false
}

resource "aws_elasticache_parameter_group" "redis" {
  provider = aws.primary
  name     = "${local.name_prefix}-redis"
  family   = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"
  }
}

resource "aws_elasticache_subnet_group" "main" {
  provider   = aws.primary
  name       = "${local.name_prefix}-redis"
  subnet_ids = module.vpc_primary.private_subnets
}

resource "aws_security_group" "redis" {
  provider    = aws.primary
  name_prefix = "${local.name_prefix}-redis-"
  vpc_id      = module.vpc_primary.vpc_id
  description = "Security group for Redis cluster"

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.primary_vpc_cidr]
    description = "Redis from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis" })
}

resource "aws_cloudwatch_log_group" "redis_slow" {
  provider          = aws.primary
  name              = "/elasticache/${local.name_prefix}/slow-log"
  retention_in_days = 30
  tags              = local.common_tags
}

resource "aws_elasticache_replication_group" "main" {
  provider                   = aws.primary
  replication_group_id       = local.name_prefix
  description                = "Redis cluster for ${var.project_name}"
  node_type                  = var.redis_node_type
  num_cache_clusters         = var.environment == "prod" ? 3 : 1
  port                       = 6379
  parameter_group_name       = aws_elasticache_parameter_group.redis.name
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [aws_security_group.redis.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth.result
  automatic_failover_enabled = var.environment == "prod"
  multi_az_enabled           = var.environment == "prod"
  snapshot_retention_limit   = 7
  snapshot_window            = "03:00-04:00"
  maintenance_window         = "mon:04:00-mon:05:00"
  notification_topic_arn     = aws_sns_topic.alerts.arn
  engine_version             = "7.0"

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  tags = local.common_tags
}

# ─── ACM Certificate ──────────────────────────────────────────────────────────

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 5.0"
  providers = { aws = aws.primary }

  domain_name = var.domain_name
  zone_id     = data.aws_route53_zone.main.zone_id

  subject_alternative_names = [
    "*.${var.domain_name}",
  ]

  validation_method = "DNS"
  wait_for_validation = true

  tags = local.common_tags
}

# ─── Application Load Balancer ────────────────────────────────────────────────

resource "aws_s3_bucket" "alb_logs" {
  provider      = aws.primary
  bucket_prefix = "${local.name_prefix}-alb-logs-"
  force_destroy = var.environment != "prod"
  tags          = local.common_tags
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  provider = aws.primary
  bucket   = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = var.environment == "prod" ? 90 : 30
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  provider = aws.primary
  bucket   = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  provider                = aws.primary
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"
  providers = { aws = aws.primary }

  name    = local.name_prefix
  vpc_id  = module.vpc_primary.vpc_id
  subnets = module.vpc_primary.public_subnets

  enable_deletion_protection = var.environment == "prod"
  enable_http2               = true
  drop_invalid_header_fields = true
  idle_timeout               = 60

  access_logs = {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  security_group_ingress_rules = {
    http  = { from_port = 80, to_port = 80, ip_protocol = "tcp", cidr_ipv4 = "0.0.0.0/0" }
    https = { from_port = 443, to_port = 443, ip_protocol = "tcp", cidr_ipv4 = "0.0.0.0/0" }
  }

  security_group_egress_rules = {
    all = { ip_protocol = "-1", cidr_ipv4 = var.primary_vpc_cidr }
  }

  listeners = {
    http_redirect = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = module.acm.acm_certificate_arn
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      forward = {
        target_group_key = "app"
      }
    }
  }

  target_groups = {
    app = {
      name             = "${local.name_prefix}-app"
      protocol         = "HTTP"
      port             = 8080
      target_type      = "ip"
      create_attachment = false

      health_check = {
        path                = "/health"
        healthy_threshold   = 2
        unhealthy_threshold = 3
        interval            = 30
        timeout             = 10
        matcher             = "200-299"
      }

      stickiness = {
        enabled  = true
        type     = "lb_cookie"
        duration = 86400
      }
    }
  }

  tags = local.common_tags
}

# ─── WAF ──────────────────────────────────────────────────────────────────────

resource "aws_wafv2_web_acl" "main" {
  provider    = aws.primary
  name        = local.name_prefix
  description = "WAF for ${var.project_name} ${var.environment}"
  scope       = "REGIONAL"

  default_action { allow {} }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-sqli"
      sampled_requests_enabled   = true
    }
  }

