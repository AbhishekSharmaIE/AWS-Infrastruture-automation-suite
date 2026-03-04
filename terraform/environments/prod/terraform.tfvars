project_name = "myproject"
environment  = "prod"
team_name    = "platform"
cost_center  = "engineering"
alarm_email  = "prod-ops@example.com"
domain_name  = "api.myproject.com"

primary_region   = "us-east-1"
secondary_region = "eu-west-1"

# VPC
primary_vpc_cidr         = "10.0.0.0/16"
primary_private_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
primary_public_subnets   = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
primary_database_subnets = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]

secondary_vpc_cidr         = "10.1.0.0/16"
secondary_private_subnets  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
secondary_public_subnets   = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
secondary_database_subnets = ["10.1.201.0/24", "10.1.202.0/24", "10.1.203.0/24"]

# EKS - large for production
kubernetes_version           = "1.29"
eks_on_demand_instance_types = ["m6i.2xlarge", "m6i.4xlarge"]
eks_spot_instance_types      = ["m5.2xlarge", "m5.4xlarge", "m5a.2xlarge", "m6i.2xlarge"]
eks_min_size                 = 3
eks_max_size                 = 50
eks_desired_size             = 6

# Aurora - production-grade
aurora_engine_version = "15.4"
aurora_instance_class = "db.r7g.2xlarge"
aurora_reader_class   = "db.r7g.xlarge"
aurora_max_replicas   = 10
database_name         = "appdb"

# Redis - large multi-AZ
redis_node_type = "cache.r7g.2xlarge"
