# EKS Cluster Outputs
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

# KMS Outputs
output "eks_secrets_kms_key_id" {
  description = "KMS key ID for EKS secrets encryption"
  value       = aws_kms_key.eks_secrets.key_id
}

output "eks_secrets_kms_key_arn" {
  description = "KMS key ARN for EKS secrets encryption"
  value       = aws_kms_key.eks_secrets.arn
}

output "ebs_kms_key_id" {
  description = "KMS key ID for EBS encryption"
  value       = aws_kms_key.ebs.key_id
}

output "ebs_kms_key_arn" {
  description = "KMS key ARN for EBS encryption"
  value       = aws_kms_key.ebs.arn
}

output "secrets_manager_kms_key_id" {
  description = "KMS key ID for Secrets Manager encryption"
  value       = aws_kms_key.secrets_manager.key_id
}

output "secrets_manager_kms_key_arn" {
  description = "KMS key ARN for Secrets Manager encryption"
  value       = aws_kms_key.secrets_manager.arn
}

# GuardDuty Outputs
output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = var.enable_guardduty ? aws_guardduty_detector.eks[0].id : null
}

output "guardduty_sns_topic_arn" {
  description = "SNS topic ARN for GuardDuty alerts"
  value       = var.enable_guardduty ? aws_sns_topic.guardduty_alerts[0].arn : null
}

# Security Hub Outputs
output "security_hub_sns_topic_arn" {
  description = "SNS topic ARN for Security Hub alerts"
  value       = var.enable_security_hub ? aws_sns_topic.security_hub_alerts[0].arn : null
}

# VPC Endpoints Outputs
output "vpc_endpoints" {
  description = "Map of VPC endpoint IDs"
  value       = var.enable_vpc_endpoints ? { for k, v in aws_vpc_endpoint.this : k => v.id } : {}
}

# Secrets Management Outputs
output "external_secrets_operator_enabled" {
  description = "Whether External Secrets Operator is enabled"
  value       = var.enable_external_secrets
}

output "secrets_store_csi_driver_enabled" {
  description = "Whether Secrets Store CSI Driver is enabled"
  value       = var.enable_secrets_store_csi
}

output "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore for External Secrets Operator"
  value       = var.enable_external_secrets ? "aws-secrets-manager" : null
}

# Bedrock Agent Outputs
output "bedrock_agent_enabled" {
  description = "Whether Bedrock AI agent is enabled"
  value       = var.enable_bedrock_agent
}

output "bedrock_agent_s3_bucket" {
  description = "S3 bucket for Bedrock agent schemas and runbooks"
  value       = var.enable_bedrock_agent ? aws_s3_bucket.bedrock_agent[0].id : null
}

output "bedrock_agent_kms_key_arn" {
  description = "KMS key ARN for Bedrock agent data encryption"
  value       = var.enable_bedrock_agent ? aws_kms_key.bedrock_agent[0].arn : null
}

output "mcp_server_lambda_arn" {
  description = "ARN of MCP server Lambda function"
  value       = var.enable_bedrock_agent ? aws_lambda_function.mcp_server[0].arn : null
}

output "bedrock_agent_trigger_lambda_arn" {
  description = "ARN of Bedrock agent trigger Lambda function"
  value       = var.enable_bedrock_agent ? aws_lambda_function.bedrock_agent_trigger[0].arn : null
}

output "bedrock_agent_id_file" {
  description = "File containing Bedrock agent ID (created after terraform apply)"
  value       = var.enable_bedrock_agent ? "bedrock_agent_id.txt" : null
}

# Configure kubectl command
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
