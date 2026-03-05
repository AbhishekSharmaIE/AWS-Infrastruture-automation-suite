# ─── Project ───────────────────────────────────────────────────────────────────

variable "project_name" {
  type        = string
  default     = "awsinfra"
  description = "Name of the project, used as prefix for all resources"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Deployment environment"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "lab_role_arn" {
  type        = string
  default     = "arn:aws:iam::216203951255:role/LabRole"
  description = "AWS Academy LabRole ARN used for all service roles"
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "database_subnets" {
  type    = list(string)
  default = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
}

# ─── EKS ──────────────────────────────────────────────────────────────────────

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "eks_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "eks_desired_size" {
  type    = number
  default = 2
}

variable "eks_min_size" {
  type    = number
  default = 1
}

variable "eks_max_size" {
  type    = number
  default = 4
}

# ─── Aurora ───────────────────────────────────────────────────────────────────

variable "aurora_engine_version" {
  type    = string
  default = "15.4"
}

variable "aurora_instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "database_name" {
  type    = string
  default = "appdb"
}

# ─── Redis ────────────────────────────────────────────────────────────────────

variable "redis_node_type" {
  type    = string
  default = "cache.t3.medium"
}
