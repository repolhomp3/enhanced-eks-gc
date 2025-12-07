# AWS Chatbot Setup Guide

Complete guide for Microsoft Teams and Slack integration with AWS Chatbot.

## Overview

**AWS Chatbot** provides:
- Real-time alerts in Teams/Slack
- Interactive buttons for acknowledgment
- Rich formatting with code blocks
- Thread-based conversations
- **FREE** (no per-message cost, only SNS charges)

## Microsoft Teams Setup (Priority)

### Step 1: Configure AWS Chatbot in Console

1. Go to AWS Chatbot console: https://console.aws.amazon.com/chatbot/
2. Click "Configure new client"
3. Select "Microsoft Teams"
4. Click "Configure"
5. Sign in with Microsoft 365 admin account
6. Authorize AWS Chatbot app
7. Select your Team and Channel

### Step 2: Get Teams IDs

After authorization, AWS Chatbot will display:
- **Team ID**: `19:xxx@thread.tacv2`
- **Channel ID**: `19:xxx@thread.tacv2`
- **Tenant ID**: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

Copy these values.

### Step 3: Update Terraform

Edit `terraform.tfvars`:

```hcl
# Enable Chatbot
enable_chatbot = true

# Microsoft Teams configuration
chatbot_teams_team_id     = "19:xxx@thread.tacv2"
chatbot_teams_channel_id  = "19:xxx@thread.tacv2"
chatbot_teams_tenant_id   = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Step 4: Deploy

```bash
terraform apply
```

### Step 5: Test

```bash
# Trigger test alert
aws sns publish \
  --topic-arn $(terraform output -raw chatbot_sns_topic_arn) \
  --subject "Test Alert" \
  --message "This is a test message from AWS Chatbot" \
  --region us-gov-west-1
```

You should see the message in your Teams channel within seconds.

## Slack Setup (Alternative)

### Step 1: Configure AWS Chatbot in Console

1. Go to AWS Chatbot console: https://console.aws.amazon.com/chatbot/
2. Click "Configure new client"
3. Select "Slack"
4. Click "Configure"
5. Sign in to Slack workspace
6. Authorize AWS Chatbot app
7. Select your channel

### Step 2: Get Slack IDs

**Workspace ID:**
1. Go to Slack workspace settings
2. URL will be: `https://app.slack.com/client/T01234567/...`
3. `T01234567` is your Workspace ID

**Channel ID:**
1. Right-click on channel name
2. Select "View channel details"
3. Scroll to bottom
4. Channel ID: `C01234567`

### Step 3: Update Terraform

Edit `terraform.tfvars`:

```hcl
# Enable Chatbot
enable_chatbot = true

# Slack configuration
chatbot_slack_workspace_id = "T01234567"
chatbot_slack_channel_id   = "C01234567"
```

### Step 4: Deploy

```bash
terraform apply
```

### Step 5: Test

```bash
# Trigger test alert
aws sns publish \
  --topic-arn $(terraform output -raw chatbot_sns_topic_arn) \
  --subject "Test Alert" \
  --message "This is a test message from AWS Chatbot" \
  --region us-gov-west-1
```

## Alert Examples

### GuardDuty Finding

```
🚨 GuardDuty Finding - CRITICAL

Severity: 8.0
Type: CryptoCurrency:Runtime/BitcoinTool.B
Resource: i-1234567890abcdef0
Region: us-gov-west-1

Description: EC2 instance is communicating with a known cryptocurrency mining pool.

[View in Console] [Acknowledge] [Remediate]
```

### Security Hub Finding

```
⚠️ Security Hub Finding - HIGH

Standard: CIS AWS Foundations Benchmark v1.4.0
Control: 2.1.1 - Ensure S3 bucket has encryption enabled
Resource: arn:aws-us-gov:s3:::my-bucket
Compliance Status: FAILED

[View Details] [Suppress] [Remediate]
```

### Pod Crash Loop

```
🔴 CloudWatch Alarm - ALARM

Alarm: enhanced-eks-cluster-pod-crash-loop
Metric: pod_number_of_container_restarts
Threshold: > 5
Current Value: 12

Pod api-service-abc123 is crash looping in namespace default.

[View Logs] [Describe Pod] [Rollback]
```

## Interactive Commands

AWS Chatbot supports interactive commands in Teams/Slack:

```
@aws cloudwatch describe-alarms --state ALARM
@aws eks describe-cluster --name enhanced-eks-cluster
@aws guardduty list-findings --detector-id abc123
@aws logs tail /aws/lambda/enhanced-eks-cluster-mcp-server --follow
```

## Customization

### Alert Formatting

Edit SNS message format in EventBridge rules:

```hcl
resource "aws_cloudwatch_event_target" "chatbot_guardduty" {
  rule = aws_cloudwatch_event_rule.chatbot_guardduty.name
  arn  = aws_sns_topic.chatbot_alerts.arn
  
  input_transformer {
    input_paths = {
      severity = "$.detail.severity"
      type     = "$.detail.type"
      resource = "$.detail.resource.instanceDetails.instanceId"
    }
    
    input_template = <<EOF
{
  "severity": "<severity>",
  "type": "<type>",
  "resource": "<resource>",
  "message": "GuardDuty finding detected"
}
EOF
  }
}
```

### Notification Filters

Control which alerts go to Chatbot:

```hcl
# Only send HIGH and CRITICAL findings
event_pattern = jsonencode({
  source      = ["aws.guardduty"]
  detail-type = ["GuardDuty Finding"]
  detail = {
    severity = [{ numeric = [">=", 7] }]  # 7-10 = HIGH/CRITICAL
  }
})
```

## Permissions

AWS Chatbot has ReadOnly access by default. To enable interactive commands:

```hcl
resource "aws_iam_role_policy_attachment" "chatbot_admin" {
  role       = aws_iam_role.chatbot.name
  policy_arn = "arn:aws-us-gov:iam::aws:policy/AdministratorAccess"
}
```

**Warning:** Only grant necessary permissions. For production, use least-privilege policies.

## Troubleshooting

### Messages Not Appearing

```bash
# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw chatbot_sns_topic_arn) \
  --region us-gov-west-1

# Check Chatbot configuration
aws chatbot describe-slack-channel-configurations \
  --region us-gov-west-1
```

### Teams Authorization Failed

1. Ensure you're signed in as Microsoft 365 admin
2. Check Teams app permissions in Azure AD
3. Re-authorize AWS Chatbot app

### Slack Authorization Failed

1. Ensure you're workspace admin
2. Check Slack app permissions
3. Re-authorize AWS Chatbot app

## Cost

**AWS Chatbot is FREE**

You only pay for:
- SNS messages: $0.50 per 1M requests
- CloudWatch Logs: $0.50/GB ingested

**Example Monthly Cost:**
- 1,000 alerts: $0.0005
- 100MB logs: $0.05
- **Total: ~$0.05/month**

Compare to SMS: 1,000 SMS = $6.45

## Integration with Incident Manager

When both Chatbot and Incident Manager are enabled:

1. **Critical alert** → Incident Manager creates incident
2. **Incident created** → SNS notification
3. **SNS** → Chatbot posts to Teams/Slack
4. **SRE acknowledges** in Teams/Slack
5. **Chatbot** → Updates Incident Manager

## Best Practices

1. **Separate channels** for different severity levels
2. **Use threads** for related alerts
3. **Enable notifications** for critical channels only
4. **Set up on-call rotation** in Teams/Slack
5. **Document runbooks** in channel description
6. **Use buttons** for common actions

## Support

- AWS Chatbot Docs: https://docs.aws.amazon.com/chatbot/
- Microsoft Teams Integration: https://docs.aws.amazon.com/chatbot/latest/adminguide/teams-setup.html
- Slack Integration: https://docs.aws.amazon.com/chatbot/latest/adminguide/slack-setup.html
