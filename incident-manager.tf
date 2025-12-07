# AWS Systems Manager Incident Manager for On-Call Management

# SNS topic for SMS alerts
resource "aws_sns_topic" "oncall_sms" {
  count = var.enable_incident_manager ? 1 : 0
  name  = "${var.cluster_name}-oncall-sms"
}

# SMS subscriptions (add phone numbers in terraform.tfvars)
resource "aws_sns_topic_subscription" "oncall_sms" {
  count     = var.enable_incident_manager ? length(var.oncall_phone_numbers) : 0
  topic_arn = aws_sns_topic.oncall_sms[0].arn
  protocol  = "sms"
  endpoint  = var.oncall_phone_numbers[count.index]
}

# Incident Manager replication set (required for Incident Manager)
resource "aws_ssmincidents_replication_set" "main" {
  count = var.enable_incident_manager ? 1 : 0
  
  region {
    name = var.aws_region
  }
}

# On-call contact
resource "aws_ssmcontacts_contact" "oncall" {
  count = var.enable_incident_manager ? 1 : 0
  alias = "${var.cluster_name}-oncall"
  type  = "PERSONAL"

  depends_on = [aws_ssmincidents_replication_set.main]
}

# Contact channel (SMS)
resource "aws_ssmcontacts_contact_channel" "oncall_sms" {
  count          = var.enable_incident_manager ? length(var.oncall_phone_numbers) : 0
  contact_id     = aws_ssmcontacts_contact.oncall[0].arn
  name           = "SMS-${count.index + 1}"
  type           = "SMS"
  delivery_address {
    simple_address = var.oncall_phone_numbers[count.index]
  }
}

# Engagement plan (how to contact on-call)
resource "aws_ssmcontacts_plan" "oncall" {
  count      = var.enable_incident_manager ? 1 : 0
  contact_id = aws_ssmcontacts_contact.oncall[0].arn

  # Stage 1: Immediate SMS
  stage {
    duration_in_minutes = 0
    
    dynamic "target" {
      for_each = aws_ssmcontacts_contact_channel.oncall_sms
      content {
        contact_channel_id = target.value.arn
      }
    }
  }

  # Stage 2: Escalate after 5 minutes if not acknowledged
  stage {
    duration_in_minutes = 5
    
    dynamic "target" {
      for_each = aws_ssmcontacts_contact_channel.oncall_sms
      content {
        contact_channel_id = target.value.arn
      }
    }
  }
}

# Response plan for critical incidents
resource "aws_ssmincidents_response_plan" "critical" {
  count = var.enable_incident_manager ? 1 : 0
  name  = "${var.cluster_name}-critical"

  incident_template {
    title  = "EKS Critical Alert"
    impact = 1  # Critical
    
    summary = "Critical alert from EKS cluster ${var.cluster_name}"
    
    notification_target {
      sns_topic_arn = aws_sns_topic.oncall_sms[0].arn
    }
  }

  engagement {
    contact_id = aws_ssmcontacts_contact.oncall[0].arn
  }

  depends_on = [aws_ssmincidents_replication_set.main]
}

# Response plan for high severity incidents
resource "aws_ssmincidents_response_plan" "high" {
  count = var.enable_incident_manager ? 1 : 0
  name  = "${var.cluster_name}-high"

  incident_template {
    title  = "EKS High Severity Alert"
    impact = 2  # High
    
    summary = "High severity alert from EKS cluster ${var.cluster_name}"
    
    notification_target {
      sns_topic_arn = aws_sns_topic.oncall_sms[0].arn
    }
  }

  engagement {
    contact_id = aws_ssmcontacts_contact.oncall[0].arn
  }

  depends_on = [aws_ssmincidents_replication_set.main]
}

# EventBridge rule to trigger Incident Manager on GuardDuty critical findings
resource "aws_cloudwatch_event_rule" "guardduty_incident" {
  count       = var.enable_incident_manager && var.enable_guardduty ? 1 : 0
  name        = "${var.cluster_name}-guardduty-incident"
  description = "Trigger Incident Manager on GuardDuty critical findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_incident" {
  count = var.enable_incident_manager && var.enable_guardduty ? 1 : 0
  rule  = aws_cloudwatch_event_rule.guardduty_incident[0].name
  arn   = aws_ssmincidents_response_plan.critical[0].arn
  
  role_arn = aws_iam_role.eventbridge_incident_manager[0].arn
}

# EventBridge rule to trigger Incident Manager on Security Hub critical findings
resource "aws_cloudwatch_event_rule" "securityhub_incident" {
  count       = var.enable_incident_manager && var.enable_security_hub ? 1 : 0
  name        = "${var.cluster_name}-securityhub-incident"
  description = "Trigger Incident Manager on Security Hub critical findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL"]
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "securityhub_incident" {
  count = var.enable_incident_manager && var.enable_security_hub ? 1 : 0
  rule  = aws_cloudwatch_event_rule.securityhub_incident[0].name
  arn   = aws_ssmincidents_response_plan.critical[0].arn
  
  role_arn = aws_iam_role.eventbridge_incident_manager[0].arn
}

# IAM role for EventBridge to start incidents
resource "aws_iam_role" "eventbridge_incident_manager" {
  count = var.enable_incident_manager ? 1 : 0
  name  = "${var.cluster_name}-eventbridge-incident-manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_incident_manager" {
  count = var.enable_incident_manager ? 1 : 0
  name  = "start-incidents"
  role  = aws_iam_role.eventbridge_incident_manager[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm-incidents:StartIncident"
      ]
      Resource = [
        aws_ssmincidents_response_plan.critical[0].arn,
        aws_ssmincidents_response_plan.high[0].arn
      ]
    }]
  })
}

# CloudWatch alarm for pod crash loops (triggers incident)
resource "aws_cloudwatch_metric_alarm" "pod_crash_loop" {
  count               = var.enable_incident_manager ? 1 : 0
  alarm_name          = "${var.cluster_name}-pod-crash-loop"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "pod_number_of_container_restarts"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "Pod is crash looping"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = module.eks.cluster_name
  }

  alarm_actions = [aws_sns_topic.oncall_sms[0].arn]
}

# CloudWatch alarm for node failures (triggers incident)
resource "aws_cloudwatch_metric_alarm" "node_failure" {
  count               = var.enable_incident_manager ? 1 : 0
  alarm_name          = "${var.cluster_name}-node-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "cluster_failed_node_count"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "EKS node has failed"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = module.eks.cluster_name
  }

  alarm_actions = [aws_sns_topic.oncall_sms[0].arn]
}
