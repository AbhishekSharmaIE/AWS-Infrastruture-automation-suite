# ─── EKS ──────────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  value       = aws_eks_cluster.main.name
  description = "EKS cluster name"
}

output "eks_cluster_endpoint" {
  value       = aws_eks_cluster.main.endpoint
  sensitive   = true
  description = "EKS cluster API endpoint"
}

output "eks_cluster_version" {
  value       = aws_eks_cluster.main.version
  description = "EKS Kubernetes version"
}

output "kubeconfig_command" {
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}"
  description = "Command to configure kubectl"
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID"
}

output "private_subnets" {
  value       = module.vpc.private_subnets
  description = "Private subnet IDs"
}

output "public_subnets" {
  value       = module.vpc.public_subnets
  description = "Public subnet IDs"
}

# ─── Aurora ───────────────────────────────────────────────────────────────────

output "aurora_cluster_endpoint" {
  value       = aws_rds_cluster.main.endpoint
  sensitive   = true
  description = "Aurora cluster writer endpoint"
}

output "aurora_reader_endpoint" {
  value       = aws_rds_cluster.main.reader_endpoint
  sensitive   = true
  description = "Aurora cluster reader endpoint"
}

# ─── ALB ──────────────────────────────────────────────────────────────────────

output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "ALB DNS name"
}

output "alb_url" {
  value       = "http://${aws_lb.main.dns_name}"
  description = "ALB URL"
}

# ─── Redis ────────────────────────────────────────────────────────────────────

output "redis_endpoint" {
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
  sensitive   = true
  description = "Redis primary endpoint"
}

# ─── Monitoring ───────────────────────────────────────────────────────────────

output "cloudwatch_dashboard_url" {
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${local.name_prefix}"
  description = "CloudWatch dashboard URL"
}

output "sns_alerts_topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "SNS alerts topic ARN"
}
