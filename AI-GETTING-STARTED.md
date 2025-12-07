# Getting Started with AI-Driven EKS Operations

Complete guide to deploying and using Amazon Bedrock AI agents for autonomous EKS cluster management.

## Prerequisites

- AWS CLI configured for us-gov-west-1
- Terraform >= 1.0
- kubectl
- Python 3.12+ (for Lambda development)
- Access to Amazon Bedrock in GovCloud
- **Model access enabled** for Claude 3 Sonnet or Haiku

## Available Models in GovCloud

**✅ Available in us-gov-west-1:**
- `anthropic.claude-3-sonnet-20240229-v1:0` (Claude 3 Sonnet)
- `anthropic.claude-3-haiku-20240307-v1:0` (Claude 3 Haiku)

**❌ Not yet available:**
- Claude 3.5 Sonnet (v1 or v2)
- Claude 3 Opus
- Experimental/fast-follow models

**Recommendation:** Use Claude 3 Sonnet for production workloads.

## Step 1: Deploy Base Infrastructure

```bash
# Clone repository
git clone <repository-url>
cd keda-auto

# Initialize Terraform
terraform init

# Deploy EKS cluster (without AI agent)
terraform apply
```

This deploys:
- EKS 1.34 cluster with Auto Mode
- VPC with 3 AZs
- Istio, KEDA, Prometheus, Kiali
- GuardDuty, Security Hub
- KMS encryption

**Time:** ~20 minutes

## Step 2: Build Lambda Functions

```bash
# Build MCP server and trigger Lambda packages
cd lambda
./build.sh
cd ..
```

This creates:
- `lambda/mcp-server.zip` (Kubernetes + AWS API handler)
- `lambda/bedrock-agent-trigger.zip` (EventBridge handler)

## Step 3: Enable Bedrock Agent

Edit `terraform.tfvars`:

```hcl
# Enable AI-driven operations
enable_bedrock_agent = true
```

Deploy infrastructure:

```bash
terraform apply
```

This creates:
- S3 bucket for MCP schemas
- KMS key for Bedrock data
- MCP server Lambda (in VPC)
- Bedrock agent trigger Lambda
- EventBridge rule for GuardDuty
- IAM roles and permissions

**Time:** ~5 minutes

## Step 4: Create Bedrock Agent

Bedrock Agents require AWS CLI (Terraform provider support is limited):

```bash
# Get outputs
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AGENT_ROLE_ARN=$(terraform output -raw bedrock_agent_role_arn)
S3_BUCKET=$(terraform output -raw bedrock_agent_s3_bucket)
MCP_LAMBDA_ARN=$(terraform output -raw mcp_server_lambda_arn)

# Create agent (using Claude 3 Sonnet - available in GovCloud)
AGENT_ID=$(aws bedrock-agent create-agent \
  --agent-name enhanced-eks-sre-agent \
  --foundation-model anthropic.claude-3-sonnet-20240229-v1:0 \
  --instruction "You are an expert SRE agent managing EKS cluster enhanced-eks-cluster in us-gov-west-1. Execute runbooks, analyze incidents, and remediate issues. Always explain your actions and request approval for destructive operations." \
  --agent-resource-role-arn $AGENT_ROLE_ARN \
  --region us-gov-west-1 \
  --query 'agent.agentId' \
  --output text)

echo "Agent ID: $AGENT_ID"

# Create Kubernetes operations action group
aws bedrock-agent create-agent-action-group \
  --agent-id $AGENT_ID \
  --agent-version DRAFT \
  --action-group-name kubernetes-operations \
  --action-group-executor lambda=$MCP_LAMBDA_ARN \
  --api-schema s3={s3BucketName=$S3_BUCKET,s3ObjectKey=schemas/kubernetes-api.json} \
  --region us-gov-west-1

# Create AWS operations action group
aws bedrock-agent create-agent-action-group \
  --agent-id $AGENT_ID \
  --agent-version DRAFT \
  --action-group-name aws-operations \
  --action-group-executor lambda=$MCP_LAMBDA_ARN \
  --api-schema s3={s3BucketName=$S3_BUCKET,s3ObjectKey=schemas/aws-api.json} \
  --region us-gov-west-1

# Prepare agent (compile and validate)
aws bedrock-agent prepare-agent \
  --agent-id $AGENT_ID \
  --region us-gov-west-1

# Create production alias
ALIAS_ID=$(aws bedrock-agent create-agent-alias \
  --agent-id $AGENT_ID \
  --agent-alias-name production \
  --region us-gov-west-1 \
  --query 'agentAlias.agentAliasId' \
  --output text)

echo "Agent Alias ID: $ALIAS_ID"

# Update trigger Lambda with agent ID
aws lambda update-function-configuration \
  --function-name enhanced-eks-cluster-bedrock-agent-trigger \
  --environment "Variables={AGENT_ID=$AGENT_ID,AGENT_ALIAS_ID=$ALIAS_ID}" \
  --region us-gov-west-1
```

**Time:** ~2 minutes

## Step 5: Test AI Agent

### Test 1: Manual Invocation

```bash
# Invoke agent directly
aws bedrock-agent-runtime invoke-agent \
  --agent-id $AGENT_ID \
  --agent-alias-id $ALIAS_ID \
  --session-id $(uuidgen) \
  --input-text "Check the health of all pods in the default namespace" \
  --region us-gov-west-1 \
  /tmp/agent-response.txt

# View response
cat /tmp/agent-response.txt
```

### Test 2: GuardDuty Trigger

```bash
# Simulate GuardDuty finding (test event)
aws events put-events \
  --entries '[{
    "Source": "aws.guardduty",
    "DetailType": "GuardDuty Finding",
    "Detail": "{\"severity\": 8, \"type\": \"CryptoCurrency:Runtime/BitcoinTool.B\", \"resource\": {\"instanceDetails\": {\"instanceId\": \"i-test123\"}}}"
  }]' \
  --region us-gov-west-1

# Check trigger Lambda logs
aws logs tail /aws/lambda/enhanced-eks-cluster-bedrock-agent-trigger --follow
```

### Test 3: Pod Crash Scenario

```bash
# Deploy test pod that crashes
kubectl run crash-test --image=busybox --restart=Never -- sh -c "exit 1"

# Wait for agent to detect and analyze
sleep 60

# Check agent actions
aws logs tail /aws/lambda/enhanced-eks-cluster-mcp-server --follow
```

## Step 6: Configure Monitoring

### CloudWatch Dashboard

```bash
# Create dashboard for AI operations
aws cloudwatch put-dashboard \
  --dashboard-name EKS-AI-Operations \
  --dashboard-body file://dashboards/ai-operations.json \
  --region us-gov-west-1
```

### SNS Alerts

```bash
# Subscribe to agent notifications
aws sns subscribe \
  --topic-arn $(terraform output -raw guardduty_sns_topic_arn) \
  --protocol email \
  --notification-endpoint your-email@example.com \
  --region us-gov-west-1
```

## Step 7: Enable Auto-Remediation

By default, the agent requires approval for destructive actions. To enable auto-remediation:

Edit agent instruction to include:

```
Auto-approve the following actions:
- Pod restarts (< 5 per hour)
- Memory limit increases (< 2x current)
- Horizontal scaling (within min/max bounds)
- Certificate rotation (expiring < 7 days)

Always require approval for:
- Node termination
- Deployment rollback
- RBAC changes
- Security group modifications
```

Update agent:

```bash
aws bedrock-agent update-agent \
  --agent-id $AGENT_ID \
  --agent-name enhanced-eks-sre-agent \
  --foundation-model anthropic.claude-3-sonnet-20240229-v1:0 \
  --instruction "$(cat agent-instruction.txt)" \
  --region us-gov-west-1

aws bedrock-agent prepare-agent \
  --agent-id $AGENT_ID \
  --region us-gov-west-1
```

## Common Operations

### View Agent Sessions

```bash
# List recent sessions
aws bedrock-agent-runtime list-agent-sessions \
  --agent-id $AGENT_ID \
  --agent-alias-id $ALIAS_ID \
  --region us-gov-west-1
```

### View Agent Actions

```bash
# View MCP server logs (agent actions)
aws logs filter-log-events \
  --log-group-name /aws/lambda/enhanced-eks-cluster-mcp-server \
  --start-time $(date -u -d '1 hour ago' +%s)000 \
  --filter-pattern '{ $.action = "kubectl" }' \
  --region us-gov-west-1
```

### Disable Agent

```bash
# Temporarily disable
aws bedrock-agent update-agent \
  --agent-id $AGENT_ID \
  --agent-status DISABLED \
  --region us-gov-west-1

# Re-enable
aws bedrock-agent update-agent \
  --agent-id $AGENT_ID \
  --agent-status ENABLED \
  --region us-gov-west-1
```

### Delete Agent

```bash
# Delete agent (cleanup)
aws bedrock-agent delete-agent-alias \
  --agent-id $AGENT_ID \
  --agent-alias-id $ALIAS_ID \
  --region us-gov-west-1

aws bedrock-agent delete-agent \
  --agent-id $AGENT_ID \
  --region us-gov-west-1

# Disable in Terraform
# Set enable_bedrock_agent = false in terraform.tfvars
terraform apply
```

## Cost Optimization

**Monthly Costs (Estimated):**
- Bedrock Claude Sonnet: $3/1M input tokens, $15/1M output tokens
- Lambda (MCP server): ~$10-20/month
- Lambda (trigger): ~$1-5/month
- S3 storage: <$1/month
- EventBridge: <$1/month

**Total: ~$50-100/month** (depends on invocation frequency)

**Optimization Tips:**
- Use agent only for critical alerts (severity >= 7)
- Set session timeout to 5 minutes
- Cache common queries in Lambda
- Use reserved concurrency for Lambda

## Troubleshooting

### Agent Not Responding

```bash
# Check agent status
aws bedrock-agent get-agent \
  --agent-id $AGENT_ID \
  --region us-gov-west-1

# Check Lambda logs
aws logs tail /aws/lambda/enhanced-eks-cluster-mcp-server --follow
```

### Lambda Timeout

```bash
# Increase timeout
aws lambda update-function-configuration \
  --function-name enhanced-eks-cluster-mcp-server \
  --timeout 120 \
  --region us-gov-west-1
```

### Permission Errors

```bash
# Verify IAM roles
aws iam get-role --role-name enhanced-eks-cluster-mcp-server-lambda-role
aws iam get-role --role-name enhanced-eks-cluster-bedrock-agent-role

# Test Lambda permissions
aws lambda invoke \
  --function-name enhanced-eks-cluster-mcp-server \
  --payload '{"actionGroup":"kubernetes-operations","apiPath":"/kubectl/get","parameters":[{"name":"resource","value":"pods"}]}' \
  /tmp/test-response.json
```

## Next Steps

- Review [SRE-RUNBOOKS.md](SRE-RUNBOOKS.md) for automated runbooks
- Review [AI-PLAYBOOKS.md](AI-PLAYBOOKS.md) for agentic workflows
- Configure custom runbooks in S3 bucket
- Set up Slack/PagerDuty integration
- Enable predictive scaling workflows
- Configure chaos engineering experiments

## Security Considerations

- Agent has full cluster access (ClusterRole)
- All actions logged to CloudWatch
- Approval required for destructive operations
- KMS encryption for all data at rest
- VPC isolation for Lambda functions
- Pod Identity for AWS API access

## Support

For issues or questions:
- Check CloudWatch Logs: `/aws/lambda/enhanced-eks-cluster-*`
- Review Bedrock agent traces in AWS Console
- See [DAY2-OPERATIONS.md](DAY2-OPERATIONS.md) for operational procedures
