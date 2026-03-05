# ─── Provider ──────────────────────────────────────────────────────────────────

provider "aws" {
  region = var.region
  default_tags {
    tags = local.common_tags
  }
}

# ─── Locals ────────────────────────────────────────────────────────────────────

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── Data Sources ──────────────────────────────────────────────────────────────

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ─── VPC ───────────────────────────────────────────────────────────────────────

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets  = var.private_subnets
  public_subnets   = var.public_subnets
  database_subnets = var.database_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = false
  flow_log_destination_type            = "cloud-watch-logs"

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${local.name_prefix}" = "owned"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/${local.name_prefix}" = "owned"
  }

  tags = local.common_tags
}

# ─── EKS Cluster ──────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = local.name_prefix
  role_arn = var.lab_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_public_access  = true
    endpoint_private_access = true
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = local.common_tags

  depends_on = [module.vpc]
}

resource "aws_security_group" "eks_cluster" {
  name_prefix = "${local.name_prefix}-eks-cluster-"
  vpc_id      = module.vpc.vpc_id
  description = "EKS cluster security group"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "API server from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-eks-cluster" })

  lifecycle { create_before_destroy = true }
}

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-general"
  node_role_arn   = var.lab_role_arn
  subnet_ids      = module.vpc.private_subnets
  instance_types  = var.eks_instance_types
  capacity_type   = "ON_DEMAND"
  disk_size       = 50

  scaling_config {
    desired_size = var.eks_desired_size
    min_size     = var.eks_min_size
    max_size     = var.eks_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role        = "general"
    environment = var.environment
  }

  tags = local.common_tags

  depends_on = [aws_eks_cluster.main]
}

# ─── Aurora PostgreSQL ─────────────────────────────────────────────────────────

resource "aws_rds_cluster" "main" {
  cluster_identifier     = "${local.name_prefix}-aurora"
  engine                 = "aurora-postgresql"
  engine_version         = var.aurora_engine_version
  database_name          = var.database_name
  master_username        = "dbadmin"
  master_password        = random_password.aurora_master.result
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.aurora.id]
  storage_encrypted      = true
  skip_final_snapshot    = true
  deletion_protection    = false
  apply_immediately      = true

  backup_retention_period      = 7
  preferred_backup_window      = "02:00-03:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = local.common_tags
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${local.name_prefix}-aurora-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.aurora_instance_class
  engine             = "aurora-postgresql"
  engine_version     = var.aurora_engine_version

  tags = local.common_tags
}

resource "random_password" "aurora_master" {
  length  = 24
  special = false
}

resource "aws_security_group" "aurora" {
  name_prefix = "${local.name_prefix}-aurora-"
  vpc_id      = module.vpc.vpc_id
  description = "Aurora PostgreSQL security group"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "PostgreSQL from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-aurora" })

  lifecycle { create_before_destroy = true }
}

# ─── ElastiCache Redis ─────────────────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name_prefix}-redis"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "redis" {
  name_prefix = "${local.name_prefix}-redis-"
  vpc_id      = module.vpc.vpc_id
  description = "Redis security group"

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Redis from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis" })

  lifecycle { create_before_destroy = true }
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = local.name_prefix
  description          = "Redis cluster for ${var.project_name}"
  node_type            = var.redis_node_type
  num_cache_clusters   = 1
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false
  snapshot_retention_limit   = 1
  snapshot_window            = "03:00-04:00"
  maintenance_window         = "mon:04:00-mon:05:00"
  engine_version             = "7.0"
  automatic_failover_enabled = false

  tags = local.common_tags
}

# ─── Application Load Balancer ─────────────────────────────────────────────────

resource "aws_s3_bucket" "alb_logs" {
  bucket_prefix = "${local.name_prefix}-alb-logs-"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_security_group" "alb" {
  name_prefix = "${local.name_prefix}-alb-"
  vpc_id      = module.vpc.vpc_id
  description = "ALB security group"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb" })

  lifecycle { create_before_destroy = true }
}

resource "aws_lb" "main" {
  name               = local.name_prefix
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false
  enable_http2               = true
  idle_timeout               = 60
  drop_invalid_header_fields = true

  tags = local.common_tags
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-app"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200-404"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ─── WAF ───────────────────────────────────────────────────────────────────────

resource "aws_wafv2_web_acl" "main" {
  name        = local.name_prefix
  description = "WAF for ${var.project_name} ${var.environment}"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
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
    override_action {
      none {}
    }
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
    name     = "RateLimitRule"
    priority = 3
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# ─── SNS Alerts ────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic" "critical" {
  name = "${local.name_prefix}-critical"
  tags = local.common_tags
}
