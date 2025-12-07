# Enhanced EKS Cluster Configuration
# Customize these values for your deployment

# ============================================================================
# Region & Cluster
# ============================================================================
region         = "us-gov-west-1"
cluster_name   = "enhanced-eks-cluster"
kubernetes_version = "1.34"

# ============================================================================
# VPC Configuration
# ============================================================================
# Set create_vpc = false to use an existing VPC
create_vpc = true
vpc_cidr   = "10.0.0.0/16"

# If using existing VPC (create_vpc = false), provide these:
# existing_vpc_id = "vpc-xxxxx"
# existing_private_subnet_ids = ["subnet-xxxxx", "subnet-yyyyy", "subnet-zzzzz"]
# existing_public_subnet_ids  = ["subnet-aaaaa", "subnet-bbbbb", "subnet-ccccc"]

# ============================================================================
# EKS Add-on Versions
# ============================================================================
addon_versions = {
  "kube-proxy"                    = "v1.34.0-eksbuild.1"
  "vpc-cni"                       = "v1.19.0-eksbuild.1"
  "coredns"                       = "v1.11.3-eksbuild.2"
  "aws-ebs-csi-driver"            = "v1.37.0-eksbuild.1"
  "aws-efs-csi-driver"            = "v2.1.1-eksbuild.1"
  "aws-mountpoint-s3-csi-driver"  = "v1.10.0-eksbuild.1"
  "adot"                          = "v0.102.1-eksbuild.1"
}

# ============================================================================
# Helm Chart Versions
# ============================================================================
istio_version          = "1.24.0"
keda_version           = "2.15.1"
kiali_version          = "1.89.0"
prometheus_version     = "25.27.0"
lb_controller_version  = "1.8.1"
metrics_server_version = "3.12.1"

# ============================================================================
# Pod Identity Configuration
# ============================================================================
# List of namespaces that will have Pod Identity permissions
# (Bedrock, S3, RDS, DynamoDB, Secrets Manager, SQS, SNS, CloudWatch, ECR, X-Ray)
pod_identity_namespaces = ["default"]

# Add more namespaces as needed:
# pod_identity_namespaces = ["default", "production", "staging", "dev"]

# ============================================================================
# VPC Endpoints (Private Connectivity)
# ============================================================================
# Enable VPC endpoints to operate without NAT gateway
# Includes: S3, DynamoDB, ECR, EC2, RDS, Lambda, Bedrock, Kinesis, and more
enable_vpc_endpoints = false

# If using existing VPC with endpoints, provide route table IDs:
# existing_private_route_table_ids = ["rtb-xxxxx", "rtb-yyyyy", "rtb-zzzzz"]

# ============================================================================
# GuardDuty Runtime Security (STIG Compliance)
# ============================================================================
# Enable GuardDuty for EKS threat detection
# Detects: privilege escalation, container escapes, crypto mining, malware
enable_guardduty = true

# ============================================================================
# AWS Security Hub (CIS Benchmarks & Compliance)
# ============================================================================
# Enable Security Hub for automated CIS benchmarks and compliance monitoring
# Includes: CIS AWS Foundations Benchmark v1.4.0, AWS Foundational Security Best Practices
enable_security_hub = true

# ============================================================================
# Secrets Management (External Secrets Operator)
# ============================================================================
# Enable External Secrets Operator to sync secrets from AWS Secrets Manager
# WARNING: External Secrets Operator is NOT FedRAMP authorized
# For strict FedRAMP compliance, use enable_secrets_store_csi instead
enable_external_secrets = true
external_secrets_version = "0.9.11"

# Enable Secrets Store CSI Driver (AWS-supported, FedRAMP compliant alternative)
# Use this for strict FedRAMP compliance instead of External Secrets Operator
enable_secrets_store_csi = false
secrets_store_csi_version = "1.4.0"
secrets_provider_aws_version = "0.3.4"

# Create example secret for demonstration (disable in production)
create_example_secret = false

# ============================================================================
# AI-Driven Operations (Bedrock Agent)
# ============================================================================
# Enable Amazon Bedrock AI agent for autonomous EKS operations
# Includes: MCP server, Lambda functions, EventBridge triggers
# Cost: ~$50-100/month depending on usage
enable_bedrock_agent = false
