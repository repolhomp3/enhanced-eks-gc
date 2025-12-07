# AWS Chatbot for Microsoft Teams and Slack Integration

# SNS topic for Chatbot notifications
resource "aws_sns_topic" "chatbot_alerts" {
  count = var.enable_chatbot ? 1 : 0
  name  = "${var.cluster_name}-chatbot-alerts"
}

# IAM role for Chatbot
resource "aws_iam_role" "chatbot" {
  count = var.enable_chatbot ? 1 : 0
  name  = "${var.cluster_name}-chatbot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "chatbot.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "chatbot_readonly" {
  count      = var.enable_chatbot ? 1 : 0
  role       = aws_iam_role.chatbot[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "chatbot_cloudwatch" {
  count = var.enable_chatbot ? 1 : 0
  name  = "cloudwatch-logs"
  role  = aws_iam_role.chatbot[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ]
      Resource = "*"
    }]
  })
}

# Microsoft Teams configuration
resource "awscc_chatbot_microsoft_teams_channel_configuration" "teams" {
  count              = var.enable_chatbot && var.chatbot_teams_channel_id != "" ? 1 : 0
  configuration_name = "${var.cluster_name}-teams"
  iam_role_arn       = aws_iam_role.chatbot[0].arn
  team_id            = var.chatbot_teams_team_id
  channel_id         = var.chatbot_teams_channel_id
  team_tenant_id     = var.chatbot_teams_tenant_id

  sns_topic_arns = concat(
    [aws_sns_topic.chatbot_alerts[0].arn],
    var.enable_guardduty ? [aws_sns_topic.guardduty_alerts[0].arn] : [],
    var.enable_security_hub ? [aws_sns_topic.security_hub_alerts[0].arn] : [],
    var.enable_incident_manager ? [aws_sns_topic.oncall_sms[0].arn] : []
  )

  logging_level = "INFO"
}

# Slack configuration
resource "aws_chatbot_slack_channel_configuration" "slack" {
  count              = var.enable_chatbot && var.chatbot_slack_channel_id != "" ? 1 : 0
  configuration_name = "${var.cluster_name}-slack"
  iam_role_arn       = aws_iam_role.chatbot[0].arn
  slack_channel_id   = var.chatbot_slack_channel_id
  slack_team_id      = var.chatbot_slack_workspace_id

  sns_topic_arns = concat(
    [aws_sns_topic.chatbot_alerts[0].arn],
    var.enable_guardduty ? [aws_sns_topic.guardduty_alerts[0].arn] : [],
    var.enable_security_hub ? [aws_sns_topic.security_hub_alerts[0].arn] : [],
    var.enable_incident_manager ? [aws_sns_topic.oncall_sms[0].arn] : []
  )

  logging_level = "INFO"
}

# EventBridge rules to send alerts to Chatbot
resource "aws_cloudwatch_event_rule" "chatbot_guardduty" {
  count       = var.enable_chatbot && var.enable_guardduty ? 1 : 0
  name        = "${var.cluster_name}-chatbot-guardduty"
  description = "Send GuardDuty findings to Chatbot"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "chatbot_guardduty" {
  count = var.enable_chatbot && var.enable_guardduty ? 1 : 0
  rule  = aws_cloudwatch_event_rule.chatbot_guardduty[0].name
  arn   = aws_sns_topic.chatbot_alerts[0].arn
}

resource "aws_cloudwatch_event_rule" "chatbot_securityhub" {
  count       = var.enable_chatbot && var.enable_security_hub ? 1 : 0
  name        = "${var.cluster_name}-chatbot-securityhub"
  description = "Send Security Hub findings to Chatbot"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["HIGH", "CRITICAL"]
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "chatbot_securityhub" {
  count = var.enable_chatbot && var.enable_security_hub ? 1 : 0
  rule  = aws_cloudwatch_event_rule.chatbot_securityhub[0].name
  arn   = aws_sns_topic.chatbot_alerts[0].arn
}

# SNS topic policy to allow EventBridge
resource "aws_sns_topic_policy" "chatbot_alerts" {
  count  = var.enable_chatbot ? 1 : 0
  arn    = aws_sns_topic.chatbot_alerts[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.chatbot_alerts[0].arn
    }]
  })
}
