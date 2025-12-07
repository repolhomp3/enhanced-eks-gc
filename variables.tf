variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-gov-west-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "enhanced-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-gov-west-1a", "us-gov-west-1b", "us-gov-west-1c"]
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for private connectivity"
  type        = bool
  default     = false
}

variable "enable_guardduty" {
  description = "Enable GuardDuty runtime security"
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Enable Security Hub CIS benchmarks"
  type        = bool
  default     = true
}

variable "enable_external_secrets" {
  description = "Enable External Secrets Operator (NOT FedRAMP authorized)"
  type        = bool
  default     = true
}

variable "enable_secrets_store_csi" {
  description = "Enable Secrets Store CSI Driver (FedRAMP compliant alternative)"
  type        = bool
  default     = false
}

variable "enable_bedrock_agent" {
  description = "Enable Bedrock AI agent for autonomous operations"
  type        = bool
  default     = false
}

variable "pod_identity_namespaces" {
  description = "List of namespaces to configure Pod Identity for"
  type        = list(string)
  default     = ["default"]
}

variable "istio_version" {
  description = "Istio version"
  type        = string
  default     = "1.24.2"
}

variable "keda_version" {
  description = "KEDA version"
  type        = string
  default     = "2.16.1"
}

variable "prometheus_version" {
  description = "Prometheus version"
  type        = string
  default     = "27.4.1"
}

variable "kiali_version" {
  description = "Kiali version"
  type        = string
  default     = "2.3.0"
}

variable "aws_load_balancer_controller_version" {
  description = "AWS Load Balancer Controller version"
  type        = string
  default     = "1.11.0"
}

variable "metrics_server_version" {
  description = "Metrics Server version"
  type        = string
  default     = "3.12.2"
}

variable "enable_incident_manager" {
  description = "Enable AWS Systems Manager Incident Manager for on-call management"
  type        = bool
  default     = false
}

variable "oncall_phone_numbers" {
  description = "List of phone numbers for SMS alerts (E.164 format: +1234567890)"
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "enable_chatbot" {
  description = "Enable AWS Chatbot for Microsoft Teams/Slack integration"
  type        = bool
  default     = false
}

variable "chatbot_teams_team_id" {
  description = "Microsoft Teams Team ID"
  type        = string
  default     = ""
}

variable "chatbot_teams_channel_id" {
  description = "Microsoft Teams Channel ID"
  type        = string
  default     = ""
}

variable "chatbot_teams_tenant_id" {
  description = "Microsoft Teams Tenant ID"
  type        = string
  default     = ""
}

variable "chatbot_slack_workspace_id" {
  description = "Slack Workspace ID"
  type        = string
  default     = ""
}

variable "chatbot_slack_channel_id" {
  description = "Slack Channel ID"
  type        = string
  default     = ""
}

variable "enable_cloudtrail" {
  description = "Enable AWS CloudTrail for API call auditing"
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for network traffic auditing"
  type        = bool
  default     = true
}
