# AWS Systems Manager Incident Manager Setup

Complete guide for on-call management with SMS alerts.

## Overview

**AWS Systems Manager Incident Manager** provides:
- On-call contact management
- SMS/email alerting
- Escalation policies
- Incident tracking and timeline
- Integration with GuardDuty, Security Hub, CloudWatch

**Cost:**
- $3.50/month per on-call contact
- SMS: $0.00645 per message (US)
- Example: 2 contacts + 100 SMS/month = $7.65/month

## Setup

### Step 1: Enable in Terraform

Edit `terraform.tfvars`:

```hcl
# Enable Incident Manager
enable_incident_manager = true

# Add on-call phone numbers (E.164 format)
oncall_phone_numbers = [
  "+12025551234",  # Primary on-call
  "+12025555678",  # Secondary on-call
]
```

**Security Note:** Store phone numbers in `terraform.tfvars.secret` (gitignored) or use environment variables:

```bash
export TF_VAR_oncall_phone_numbers='["+12025551234","+12025555678"]'
```

### Step 2: Deploy

```bash
terraform apply
```

This creates:
- SNS topic for SMS alerts
- Incident Manager replication set
- On-call contact with SMS channels
- Engagement plan (immediate + 5-min escalation)
- Response plans (critical and high severity)
- EventBridge rules for GuardDuty/Security Hub
- CloudWatch alarms for pod crashes and node failures

### Step 3: Activate Contact Channels

**Important:** SMS channels require activation via verification code.

```bash
# Get contact ARN
CONTACT_ARN=$(aws ssm-contacts list-contacts \
  --region us-gov-west-1 \
  --query "Contacts[?Alias=='enhanced-eks-cluster-oncall'].ContactArn" \
  --output text)

# List contact channels
aws ssm-contacts list-contact-channels \
  --contact-id $CONTACT_ARN \
  --region us-gov-west-1

# Activate each channel (sends verification code via SMS)
CHANNEL_ARN=$(aws ssm-contacts list-contact-channels \
  --contact-id $CONTACT_ARN \
  --region us-gov-west-1 \
  --query "ContactChannels[0].ContactChannelArn" \
  --output text)

aws ssm-contacts activate-contact-channel \
  --contact-channel-id $CHANNEL_ARN \
  --activation-code <CODE_FROM_SMS> \
  --region us-gov-west-1
```

Repeat for each phone number.

## Testing

### Test 1: Manual Incident

```bash
# Start a test incident
aws ssm-incidents start-incident \
  --response-plan-arn $(terraform output -raw incident_manager_critical_plan_arn) \
  --title "Test Incident - Please Acknowledge" \
  --impact 1 \
  --region us-gov-west-1

# You should receive SMS within seconds
```

### Test 2: GuardDuty Trigger

```bash
# Simulate GuardDuty finding
aws events put-events \
  --entries '[{
    "Source": "aws.guardduty",
    "DetailType": "GuardDuty Finding",
    "Detail": "{\"severity\": 8, \"type\": \"CryptoCurrency:Runtime/BitcoinTool.B\"}"
  }]' \
  --region us-gov-west-1

# SMS alert should arrive automatically
```

### Test 3: CloudWatch Alarm

```bash
# Trigger pod crash alarm (deploy crashing pod)
kubectl run crash-test --image=busybox --restart=Always -- sh -c "exit 1"

# Wait 5-10 minutes for alarm to trigger
# SMS alert will be sent
```

## Incident Response Workflow

### 1. Receive SMS Alert

```
[CRITICAL] EKS Critical Alert
Incident: INC-12345
Cluster: enhanced-eks-cluster
GuardDuty finding: Severity 8
View: https://console.aws.amazon.com/systems-manager/incidents/home?region=us-gov-west-1#/incidents/INC-12345
```

### 2. Acknowledge Incident

**Via AWS Console:**
1. Click link in SMS
2. Click "Engage" to acknowledge
3. View incident timeline

**Via AWS CLI:**
```bash
aws ssm-incidents update-incident-record \
  --arn <INCIDENT_ARN> \
  --status OPEN \
  --region us-gov-west-1
```

### 3. Investigate

```bash
# View incident details
aws ssm-incidents get-incident-record \
  --arn <INCIDENT_ARN> \
  --region us-gov-west-1

# View timeline
aws ssm-incidents list-timeline-events \
  --incident-record-arn <INCIDENT_ARN> \
  --region us-gov-west-1
```

### 4. Remediate

Follow runbooks in [SRE-RUNBOOKS.md](SRE-RUNBOOKS.md) or use Bedrock AI agent for autonomous remediation.

### 5. Resolve Incident

```bash
aws ssm-incidents update-incident-record \
  --arn <INCIDENT_ARN> \
  --status RESOLVED \
  --region us-gov-west-1
```

## Escalation Policy

**Default Engagement Plan:**

| Time | Action |
|------|--------|
| 0 min | SMS to all on-call contacts |
| 5 min | SMS again if not acknowledged |

**Customize Escalation:**

Edit `incident-manager.tf`:

```hcl
resource "aws_ssmcontacts_plan" "oncall" {
  # Stage 1: Immediate SMS
  stage {
    duration_in_minutes = 0
    target {
      contact_channel_id = aws_ssmcontacts_contact_channel.oncall_sms[0].arn
    }
  }

  # Stage 2: Escalate to secondary after 5 minutes
  stage {
    duration_in_minutes = 5
    target {
      contact_channel_id = aws_ssmcontacts_contact_channel.oncall_sms[1].arn
    }
  }

  # Stage 3: Escalate to manager after 10 minutes
  stage {
    duration_in_minutes = 10
    target {
      contact_channel_id = aws_ssmcontacts_contact_channel.manager_sms.arn
    }
  }
}
```

## On-Call Rotation

**Create Rotation Schedule:**

```bash
# Create rotation (weekly, starting Monday 9am)
aws ssm-contacts create-rotation \
  --name weekly-oncall \
  --contact-ids $CONTACT_ARN_1 $CONTACT_ARN_2 \
  --recurrence "WEEKLY" \
  --start-time "2024-01-15T09:00:00Z" \
  --time-zone-id "America/New_York" \
  --region us-gov-west-1
```

**View Current On-Call:**

```bash
aws ssm-contacts list-rotations \
  --region us-gov-west-1
```

## Integration with Bedrock AI Agent

When both Incident Manager and Bedrock Agent are enabled:

1. **Alert triggers incident** → SMS sent to on-call
2. **Bedrock agent analyzes** → Gathers context (logs, metrics, events)
3. **Agent recommends action** → Sends to Incident Manager timeline
4. **On-call approves** → Agent executes remediation
5. **Incident resolved** → Timeline updated with actions taken

## Monitoring

### View Recent Incidents

```bash
aws ssm-incidents list-incident-records \
  --max-results 10 \
  --region us-gov-west-1
```

### View Engagement Metrics

```bash
aws ssm-contacts list-engagements \
  --max-results 10 \
  --region us-gov-west-1
```

### CloudWatch Metrics

```bash
# Incident count
aws cloudwatch get-metric-statistics \
  --namespace AWS/SSMIncidents \
  --metric-name IncidentCount \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum \
  --region us-gov-west-1
```

## Cost Optimization

**Reduce SMS Costs:**
1. Use email for non-critical alerts (free)
2. Batch alerts (don't send for every pod restart)
3. Set alarm thresholds appropriately
4. Use Bedrock agent for auto-remediation (fewer alerts)

**Example Monthly Cost:**
- 2 on-call contacts: $7.00
- 50 critical SMS: $0.32
- 100 high severity SMS: $0.65
- **Total: ~$8/month**

## Troubleshooting

### SMS Not Received

```bash
# Check contact channel status
aws ssm-contacts get-contact-channel \
  --contact-channel-id $CHANNEL_ARN \
  --region us-gov-west-1

# Verify activation status
# ActivationStatus should be "ACTIVATED"
```

### Incident Not Created

```bash
# Check EventBridge rule
aws events list-rule-names-by-target \
  --target-arn $(terraform output -raw incident_manager_critical_plan_arn) \
  --region us-gov-west-1

# Check IAM permissions
aws iam get-role-policy \
  --role-name enhanced-eks-cluster-eventbridge-incident-manager \
  --policy-name start-incidents \
  --region us-gov-west-1
```

### Escalation Not Working

```bash
# Verify engagement plan
aws ssm-contacts get-contact \
  --contact-id $CONTACT_ARN \
  --region us-gov-west-1

# Check plan stages
```

## AWS Chatbot Alternative

**If SMS isn't viable**, use **AWS Chatbot** for Slack/Teams integration:

```hcl
resource "aws_chatbot_slack_channel_configuration" "alerts" {
  configuration_name = "eks-alerts"
  iam_role_arn      = aws_iam_role.chatbot.arn
  slack_channel_id  = "C01234567"
  slack_team_id     = "T01234567"
  
  sns_topic_arns = [
    aws_sns_topic.oncall_sms.arn
  ]
}
```

**Benefits:**
- Free (no per-message cost)
- Rich formatting with buttons
- Thread-based incident tracking
- Interactive acknowledgment

**Setup:**
1. Create Slack app: https://console.aws.amazon.com/chatbot/
2. Authorize workspace
3. Get channel ID from Slack
4. Deploy Terraform

**Limitation:** Requires Slack/Teams (not available in all secure environments)

## Support

- AWS Incident Manager Docs: https://docs.aws.amazon.com/incident-manager/
- SMS Pricing: https://aws.amazon.com/sns/sms-pricing/
- On-Call Best Practices: https://aws.amazon.com/blogs/mt/incident-response-aws-systems-manager-incident-manager/
