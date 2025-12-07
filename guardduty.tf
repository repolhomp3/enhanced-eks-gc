# GuardDuty for EKS Runtime Security (STIG Compliance)

# Enable GuardDuty (if not already enabled)
resource "aws_guardduty_detector" "main" {
  enable = var.enable_guardduty

  datasources {
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    s3_logs {
      enable = true
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "${var.cluster_name}-guardduty"
  }
}

# SNS topic for GuardDuty alerts
resource "aws_sns_topic" "guardduty_alerts" {
  count = var.enable_guardduty ? 1 : 0
  name  = "${var.cluster_name}-guardduty-alerts"

  tags = {
    Name = "${var.cluster_name}-guardduty-alerts"
  }
}

# EventBridge rule to capture GuardDuty findings
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count       = var.enable_guardduty ? 1 : 0
  name        = "${var.cluster_name}-guardduty-findings"
  description = "Capture GuardDuty findings for EKS cluster"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      resource = {
        eksClusterDetails = {
          name = [var.cluster_name]
        }
      }
    }
  })
}

# EventBridge target to send findings to SNS
resource "aws_cloudwatch_event_target" "guardduty_sns" {
  count     = var.enable_guardduty ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.guardduty_alerts[0].arn
}

# SNS topic policy to allow EventBridge
resource "aws_sns_topic_policy" "guardduty_alerts" {
  count  = var.enable_guardduty ? 1 : 0
  arn    = aws_sns_topic.guardduty_alerts[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action   = "SNS:Publish"
      Resource = aws_sns_topic.guardduty_alerts[0].arn
    }]
  })
}

# CloudWatch Log Group for GuardDuty findings
resource "aws_cloudwatch_log_group" "guardduty_findings" {
  count             = var.enable_guardduty ? 1 : 0
  name              = "/aws/guardduty/${var.cluster_name}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.eks_secrets.arn

  tags = {
    Name = "${var.cluster_name}-guardduty-logs"
  }
}

# EventBridge target to send findings to CloudWatch Logs
resource "aws_cloudwatch_event_target" "guardduty_logs" {
  count     = var.enable_guardduty ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "SendToCloudWatchLogs"
  arn       = aws_cloudwatch_log_group.guardduty_findings[0].arn
}
