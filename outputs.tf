output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = local.public_subnet_ids
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}"
}

output "pod_identity_role_arn" {
  description = "Pod Identity IAM Role ARN for default namespace"
  value       = aws_iam_role.default_pod_identity.arn
}

output "vpc_endpoints_enabled" {
  description = "Whether VPC endpoints are enabled"
  value       = var.enable_vpc_endpoints
}

output "vpc_endpoint_interface_ids" {
  description = "Map of interface VPC endpoint IDs"
  value       = var.enable_vpc_endpoints ? { for k, v in aws_vpc_endpoint.interface : k => v.id } : {}
}

output "vpc_endpoint_gateway_ids" {
  description = "Map of gateway VPC endpoint IDs (S3, DynamoDB)"
  value       = var.enable_vpc_endpoints ? { for k, v in aws_vpc_endpoint.gateway : k => v.id } : {}
}

output "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = var.enable_vpc_endpoints ? aws_security_group.vpc_endpoints[0].id : null
}

output "kms_eks_secrets_key_id" {
  description = "KMS key ID for EKS secrets encryption"
  value       = aws_kms_key.eks_secrets.id
}

output "kms_eks_secrets_key_arn" {
  description = "KMS key ARN for EKS secrets encryption"
  value       = aws_kms_key.eks_secrets.arn
}

output "kms_ebs_key_id" {
  description = "KMS key ID for EBS volume encryption"
  value       = aws_kms_key.ebs.id
}

output "kms_ebs_key_arn" {
  description = "KMS key ARN for EBS volume encryption"
  value       = aws_kms_key.ebs.arn
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = var.enable_guardduty ? aws_guardduty_detector.main.id : null
}

output "guardduty_sns_topic_arn" {
  description = "SNS topic ARN for GuardDuty alerts"
  value       = var.enable_guardduty ? aws_sns_topic.guardduty_alerts[0].arn : null
}

output "security_hub_enabled" {
  description = "Whether Security Hub is enabled"
  value       = var.enable_security_hub
}

output "security_hub_sns_topic_arn" {
  description = "SNS topic ARN for Security Hub findings"
  value       = var.enable_security_hub ? aws_sns_topic.security_hub_findings[0].arn : null
}
