# ─── EKS ──────────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  value       = module.eks.cluster_name
  description = "EKS cluster name"
}

output "eks_cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  sensitive   = true
  description = "EKS cluster API endpoint"
}

output "eks_cluster_version" {
  value       = module.eks.cluster_version
  description = "EKS cluster Kubernetes version"
}

output "kubeconfig_command" {
  value       = "aws eks update-kubeconfig --region ${var.primary_region} --name ${module.eks.cluster_name}"
  description = "Command to configure kubectl"
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

output "vpc_primary_id" {
  value       = module.vpc_primary.vpc_id
  description = "Primary VPC ID"
}

output "vpc_secondary_id" {
  value       = module.vpc_secondary.vpc_id
  description = "Secondary VPC ID"
}

output "vpc_primary_private_subnets" {
  value       = module.vpc_primary.private_subnets
  description = "Primary VPC private subnet IDs"
}

output "vpc_primary_public_subnets" {
  value       = module.vpc_primary.public_subnets
  description = "Primary VPC public subnet IDs"
}

# ─── Aurora ───────────────────────────────────────────────────────────────────

output "aurora_primary_endpoint" {
  value       = module.aurora_primary.cluster_endpoint
  sensitive   = true
  description = "Aurora primary cluster writer endpoint"
}

output "aurora_reader_endpoint" {
  value       = module.aurora_primary.cluster_reader_endpoint
  sensitive   = true
  description = "Aurora primary cluster reader endpoint"
}

output "aurora_primary_port" {
  value       = module.aurora_primary.cluster_port
  description = "Aurora primary cluster port"
}

# ─── ALB ──────────────────────────────────────────────────────────────────────

output "alb_dns_name" {
  value       = module.alb.dns_name
  description = "ALB DNS name"
}

output "alb_zone_id" {
  value       = module.alb.zone_id
  description = "ALB Route53 zone ID"
}

output "alb_arn" {
  value       = module.alb.arn
  description = "ALB ARN"
}

# ─── Redis ────────────────────────────────────────────────────────────────────

output "redis_primary_endpoint" {
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
  sensitive   = true
  description = "Redis primary endpoint address"
}

output "redis_auth_token" {
  value       = random_password.redis_auth.result
  sensitive   = true
  description = "Redis authentication token"
}

# ─── Monitoring ───────────────────────────────────────────────────────────────

output "cloudwatch_dashboard_url" {
  value       = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${local.name_prefix}"
  description = "CloudWatch dashboard URL"
}

output "sns_alerts_topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "SNS alerts topic ARN"
}
