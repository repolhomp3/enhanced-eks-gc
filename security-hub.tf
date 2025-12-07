# AWS Security Hub for CIS Benchmarks and Compliance

# Enable Security Hub
resource "aws_securityhub_account" "main" {
  count = var.enable_security_hub ? 1 : 0
}

# Enable CIS AWS Foundations Benchmark
resource "aws_securityhub_standards_subscription" "cis" {
  count         = var.enable_security_hub ? 1 : 0
  standards_arn = "arn:aws-us-gov:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/1.4.0"

  depends_on = [aws_securityhub_account.main]
}

# Enable AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "fsbp" {
  count         = var.enable_security_hub ? 1 : 0
  standards_arn = "arn:aws-us-gov:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.main]
}

# Enable GuardDuty integration with Security Hub
resource "aws_securityhub_product_subscription" "guardduty" {
  count       = var.enable_security_hub && var.enable_guardduty ? 1 : 0
  product_arn = "arn:aws-us-gov:securityhub:${var.region}::product/aws/guardduty"

  depends_on = [aws_securityhub_account.main]
}

# SNS topic for Security Hub findings
resource "aws_sns_topic" "security_hub_findings" {
  count = var.enable_security_hub ? 1 : 0
  name  = "${var.cluster_name}-security-hub-findings"

  tags = {
    Name = "${var.cluster_name}-security-hub-findings"
  }
}

# EventBridge rule for critical/high Security Hub findings
resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  count       = var.enable_security_hub ? 1 : 0
  name        = "${var.cluster_name}-security-hub-findings"
  description = "Capture critical and high severity Security Hub findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL", "HIGH"]
        }
        Compliance = {
          Status = ["FAILED"]
        }
      }
    }
  })
}

# EventBridge target to send findings to SNS
resource "aws_cloudwatch_event_target" "security_hub_sns" {
  count     = var.enable_security_hub ? 1 : 0
  rule      = aws_cloudwatch_event_rule.security_hub_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_hub_findings[0].arn
}

# SNS topic policy
resource "aws_sns_topic_policy" "security_hub_findings" {
  count  = var.enable_security_hub ? 1 : 0
  arn    = aws_sns_topic.security_hub_findings[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action   = "SNS:Publish"
      Resource = aws_sns_topic.security_hub_findings[0].arn
    }]
  })
}

# CloudWatch Log Group for Security Hub findings
resource "aws_cloudwatch_log_group" "security_hub_findings" {
  count             = var.enable_security_hub ? 1 : 0
  name              = "/aws/securityhub/${var.cluster_name}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.eks_secrets.arn

  tags = {
    Name = "${var.cluster_name}-security-hub-logs"
  }
}

# EventBridge target to send findings to CloudWatch Logs
resource "aws_cloudwatch_event_target" "security_hub_logs" {
  count     = var.enable_security_hub ? 1 : 0
  rule      = aws_cloudwatch_event_rule.security_hub_findings[0].name
  target_id = "SendToCloudWatchLogs"
  arn       = aws_cloudwatch_log_group.security_hub_findings[0].arn
}
