# ─── Project ───────────────────────────────────────────────────────────────────

variable "project_name" {
  type        = string
  description = "Name of the project, used as prefix for all resources"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}

variable "team_name" {
  type        = string
  default     = "platform"
  description = "Team that owns this infrastructure"
}

variable "cost_center" {
  type        = string
  description = "Cost center for billing allocation"
}

variable "alarm_email" {
  type        = string
  description = "Email address for CloudWatch alarm notifications"
}

variable "domain_name" {
  type        = string
  description = "Primary domain name (must have a Route53 hosted zone)"
}

# ─── Regions ───────────────────────────────────────────────────────────────────

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "secondary_region" {
  type    = string
  default = "us-west-2"
}

# ─── VPC Primary ──────────────────────────────────────────────────────────────

variable "primary_vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "primary_private_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "primary_public_subnets" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "primary_database_subnets" {
  type    = list(string)
  default = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
}

# ─── VPC Secondary ────────────────────────────────────────────────────────────

variable "secondary_vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "secondary_private_subnets" {
  type    = list(string)
  default = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
}

variable "secondary_public_subnets" {
  type    = list(string)
  default = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
}

variable "secondary_database_subnets" {
  type    = list(string)
  default = ["10.1.201.0/24", "10.1.202.0/24", "10.1.203.0/24"]
}

# ─── EKS ──────────────────────────────────────────────────────────────────────

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "eks_on_demand_instance_types" {
  type    = list(string)
  default = ["m6i.xlarge", "m6i.2xlarge"]
}

variable "eks_spot_instance_types" {
  type    = list(string)
  default = ["m5.xlarge", "m5.2xlarge", "m5a.xlarge", "m6i.xlarge"]
}

variable "eks_min_size" {
  type    = number
  default = 2
}

variable "eks_max_size" {
  type    = number
  default = 20
}

variable "eks_desired_size" {
  type    = number
  default = 3
}

# ─── Aurora ───────────────────────────────────────────────────────────────────

variable "aurora_engine_version" {
  type    = string
  default = "15.4"
}

variable "aurora_instance_class" {
  type    = string
  default = "db.r7g.large"
}

variable "aurora_reader_class" {
  type    = string
  default = "db.r7g.large"
}

variable "aurora_max_replicas" {
  type    = number
  default = 5
}

variable "database_name" {
  type    = string
  default = "appdb"
}

# ─── Redis ────────────────────────────────────────────────────────────────────

variable "redis_node_type" {
  type    = string
  default = "cache.r7g.large"
}

# ─── WAF ──────────────────────────────────────────────────────────────────────

variable "waf_blocked_countries" {
  type        = list(string)
  default     = []
  description = "ISO 3166-1 alpha-2 country codes to block via WAF geo-match"
}
