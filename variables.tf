variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-gov-west-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "enhanced-eks-cluster"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34"
}

variable "addon_versions" {
  description = "EKS addon versions"
  type        = map(string)
  default = {
    "kube-proxy"                    = "v1.34.0-eksbuild.1"
    "vpc-cni"                       = "v1.19.0-eksbuild.1"
    "coredns"                       = "v1.11.3-eksbuild.2"
    "aws-ebs-csi-driver"            = "v1.37.0-eksbuild.1"
    "aws-efs-csi-driver"            = "v2.1.1-eksbuild.1"
    "aws-mountpoint-s3-csi-driver"  = "v1.10.0-eksbuild.1"
    "adot"                          = "v0.102.1-eksbuild.1"
  }
}

variable "keda_version" {
  description = "KEDA Helm chart version"
  type        = string
  default     = "2.15.1"
}

variable "istio_version" {
  description = "Istio Helm chart version"
  type        = string
  default     = "1.24.0"
}

variable "pod_identity_namespaces" {
  description = "List of namespaces to grant pod identity permissions"
  type        = list(string)
  default     = ["default"]
}

variable "create_vpc" {
  description = "Whether to create a new VPC or use an existing one"
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "ID of existing VPC (required if create_vpc = false)"
  type        = string
  default     = ""
}

variable "existing_private_subnet_ids" {
  description = "List of existing private subnet IDs (required if create_vpc = false)"
  type        = list(string)
  default     = []
}

variable "existing_public_subnet_ids" {
  description = "List of existing public subnet IDs (required if create_vpc = false)"
  type        = list(string)
  default     = []
}

variable "lb_controller_version" {
  description = "AWS Load Balancer Controller Helm chart version"
  type        = string
  default     = "1.8.1"
}

variable "metrics_server_version" {
  description = "Metrics Server Helm chart version"
  type        = string
  default     = "3.12.1"
}

variable "kiali_version" {
  description = "Kiali Helm chart version"
  type        = string
  default     = "1.89.0"
}

variable "prometheus_version" {
  description = "Prometheus Helm chart version"
  type        = string
  default     = "25.27.0"
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for private connectivity (no NAT gateway required)"
  type        = bool
  default     = false
}

variable "existing_private_route_table_ids" {
  description = "List of private route table IDs (required for gateway endpoints when using existing VPC)"
  type        = list(string)
  default     = []
}

variable "enable_guardduty" {
  description = "Enable GuardDuty for EKS runtime security (STIG compliance)"
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Enable AWS Security Hub for CIS benchmarks and compliance monitoring"
  type        = bool
  default     = true
}

variable "enable_external_secrets" {
  description = "Enable External Secrets Operator for AWS Secrets Manager integration"
  type        = bool
  default     = true
}

variable "external_secrets_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "0.9.11"
}

variable "create_example_secret" {
  description = "Create example secret in Secrets Manager for demonstration"
  type        = bool
  default     = false
}

variable "enable_secrets_store_csi" {
  description = "Enable Secrets Store CSI Driver (AWS-supported, FedRAMP compliant alternative)"
  type        = bool
  default     = false
}

variable "secrets_store_csi_version" {
  description = "Secrets Store CSI Driver Helm chart version"
  type        = string
  default     = "1.4.0"
}

variable "secrets_provider_aws_version" {
  description = "AWS Secrets Manager CSI Provider Helm chart version"
  type        = string
  default     = "0.3.4"
}
