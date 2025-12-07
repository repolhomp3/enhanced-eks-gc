# Deployment Guide

Complete deployment guide for EKS cluster with AI-driven operations.

## Prerequisites

- AWS CLI configured for us-gov-west-1
- Terraform >= 1.0
- kubectl
- Helm >= 3.0
- Docker (for web UI)
- GitLab account (for CI/CD)

## Deployment Steps

### 1. Deploy Infrastructure with Terraform

```bash
# Clone repository
git clone <repository-url>
cd keda-auto

# Initialize Terraform
terraform init

# Review configuration
vi terraform.tfvars

# Deploy
terraform apply
```

**Time:** ~20 minutes

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --region us-gov-west-1 --name enhanced-eks-cluster
kubectl get nodes
```

### 3. Enable AI Operations (Optional)

#### Build Lambda Functions

```bash
cd lambda
./build.sh
cd ..
```

#### Enable in Terraform

```hcl
# terraform.tfvars
enable_bedrock_agent = true
```

```bash
terraform apply
```

#### Create Bedrock Agent

```bash
# See AI-GETTING-STARTED.md for complete steps
AGENT_ID=$(aws bedrock-agent create-agent ...)
echo $AGENT_ID > bedrock_agent_id.txt
```

### 4. Enable Incident Manager (Optional)

```hcl
# terraform.tfvars
enable_incident_manager = true
oncall_phone_numbers = ["+12025551234"]
```

```bash
terraform apply
```

**Activate SMS channels:** See [INCIDENT-MANAGER.md](INCIDENT-MANAGER.md)

### 5. Enable AWS Chatbot (Optional)

```hcl
# terraform.tfvars
enable_chatbot = true
chatbot_teams_team_id = "19:xxx@thread.tacv2"
chatbot_teams_channel_id = "19:xxx@thread.tacv2"
chatbot_teams_tenant_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

```bash
terraform apply
```

**Setup:** See [CHATBOT-SETUP.md](CHATBOT-SETUP.md)

### 6. Deploy Web UI

#### Option A: Helm (Manual)

```bash
cd web-ui

# Build and push image
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr create-repository --repository-name sre-assistant --region us-gov-west-1
aws ecr get-login-password --region us-gov-west-1 | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com
docker build -t sre-assistant .
docker tag sre-assistant:latest $ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/sre-assistant:latest
docker push $ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/sre-assistant:latest

# Deploy with Helm
AGENT_ID=$(cat ../bedrock_agent_id.txt)
FLASK_SECRET_KEY=$(python -c 'import os; print(os.urandom(24).hex())')

helm upgrade --install sre-assistant helm/sre-assistant \
  --namespace sre-assistant \
  --create-namespace \
  --set image.repository=$ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/sre-assistant \
  --set image.tag=latest \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws-us-gov:iam::$ACCOUNT_ID:role/enhanced-eks-cluster-sre-assistant-role \
  --set bedrock.agentId=$AGENT_ID \
  --set secret.secretKey=$FLASK_SECRET_KEY \
  --set ingress.certificateArn=arn:aws-us-gov:acm:us-gov-west-1:$ACCOUNT_ID:certificate/your-cert-id \
  --set ingress.host=sre-assistant.internal.example.com
```

#### Option B: GitLab CI/CD (Automated)

1. **Push code to GitLab**

```bash
git remote add gitlab https://gitlab.com/your-org/enhanced-eks-gc.git
git push gitlab main
```

2. **Configure GitLab CI/CD Variables**

Go to Settings → CI/CD → Variables:

| Variable | Value | Protected | Masked |
|----------|-------|-----------|--------|
| AWS_ACCOUNT_ID | 123456789012 | ✓ | ✗ |
| AWS_ACCESS_KEY_ID | AKIA... | ✓ | ✓ |
| AWS_SECRET_ACCESS_KEY | ... | ✓ | ✓ |
| EKS_CLUSTER_NAME | enhanced-eks-cluster | ✓ | ✗ |
| POD_IDENTITY_ROLE_ARN | arn:aws-us-gov:iam::...  | ✓ | ✗ |
| BEDROCK_AGENT_ID | agent-id | ✓ | ✗ |
| FLASK_SECRET_KEY | random-key | ✓ | ✓ |
| ACM_CERTIFICATE_ARN | arn:aws-us-gov:acm:... | ✓ | ✗ |
| INGRESS_HOST | sre-assistant.internal.example.com | ✓ | ✗ |

3. **Deploy**

- Push to `develop` → Auto-deploy to dev
- Push to `main` → Manual deploy to prod

## Verification

### Check Infrastructure

```bash
# EKS cluster
kubectl get nodes

# Add-ons
kubectl get pods -n kube-system

# Istio
kubectl get pods -n istio-system

# KEDA
kubectl get pods -n keda

# Prometheus
kubectl get pods -n prometheus
```

### Check Security

```bash
# KMS keys
aws kms list-aliases --region us-gov-west-1 | grep enhanced-eks

# GuardDuty
aws guardduty list-detectors --region us-gov-west-1

# Security Hub
aws securityhub describe-hub --region us-gov-west-1
```

### Check AI Operations

```bash
# Lambda functions
aws lambda list-functions --region us-gov-west-1 | grep enhanced-eks

# Bedrock agent
aws bedrock-agent list-agents --region us-gov-west-1

# Test invocation
aws bedrock-agent-runtime invoke-agent \
  --agent-id $AGENT_ID \
  --agent-alias-id production \
  --session-id $(uuidgen) \
  --input-text "Get cluster health" \
  --region us-gov-west-1 \
  /tmp/response.txt
```

### Check Web UI

```bash
# Helm release
helm list -n sre-assistant

# Pods
kubectl get pods -n sre-assistant

# Ingress
kubectl get ingress -n sre-assistant

# Access
kubectl port-forward -n sre-assistant svc/sre-assistant 8080:80
open http://localhost:8080
```

## GitLab CI/CD Pipeline

### Pipeline Stages

```
build → deploy:dev → deploy:prod
```

### Build Stage

- Builds Docker image
- Tags with commit SHA
- Pushes to ECR

### Deploy Stage (Dev)

- Auto-deploys on `develop` branch
- Uses Helm upgrade --install
- 2 replicas
- No autoscaling

### Deploy Stage (Prod)

- Manual trigger on `main` branch
- 3 replicas
- Autoscaling enabled (2-10 pods)
- Requires approval

### Pipeline Variables

Set in GitLab CI/CD settings or `.gitlab-ci.yml`:

```yaml
variables:
  AWS_REGION: us-gov-west-1
  ECR_REGISTRY: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
  IMAGE_NAME: sre-assistant
  HELM_CHART_PATH: helm/sre-assistant
```

### Example Pipeline Run

```bash
# Trigger pipeline
git commit -m "Update web UI"
git push gitlab develop

# View pipeline
# GitLab → CI/CD → Pipelines

# Stages:
# ✓ build (2m 30s)
# ✓ deploy:dev (1m 15s)
```

## Rollback

### Terraform Rollback

```bash
# Revert to previous state
terraform state pull > backup.tfstate
terraform apply -var-file=previous.tfvars
```

### Helm Rollback

```bash
# List releases
helm history sre-assistant -n sre-assistant

# Rollback to previous version
helm rollback sre-assistant -n sre-assistant

# Rollback to specific revision
helm rollback sre-assistant 3 -n sre-assistant
```

### GitLab Rollback

```bash
# Revert commit
git revert <commit-sha>
git push gitlab main

# Or redeploy previous version
helm upgrade sre-assistant helm/sre-assistant \
  --namespace sre-assistant \
  --set image.tag=<previous-sha>
```

## Troubleshooting

### Terraform Issues

```bash
# Refresh state
terraform refresh

# Re-initialize
rm -rf .terraform
terraform init

# Debug
export TF_LOG=DEBUG
terraform apply
```

### Helm Issues

```bash
# Debug installation
helm install sre-assistant helm/sre-assistant --dry-run --debug

# Check values
helm get values sre-assistant -n sre-assistant

# Uninstall and reinstall
helm uninstall sre-assistant -n sre-assistant
helm install sre-assistant helm/sre-assistant
```

### GitLab CI/CD Issues

```bash
# Check runner logs
# GitLab → CI/CD → Pipelines → Job → View logs

# Test locally with gitlab-runner
gitlab-runner exec docker build

# Validate .gitlab-ci.yml
# GitLab → CI/CD → Editor → Validate
```

## Cost Summary

| Component | Monthly Cost |
|-----------|--------------|
| EKS Control Plane | $87.60 |
| NAT Gateway | $98.55 |
| Auto Mode Compute | $500-800 |
| Storage/Observability | $100 |
| Security (GuardDuty, Security Hub) | $40-50 |
| VPC Endpoints (optional) | $50-100 |
| AI Operations (optional) | $50-100 |
| Incident Manager (optional) | $8-15 |
| Chatbot (optional) | FREE |
| Web UI | $30-50 |
| **Total** | **$850-1,300/month** |

## Support

- [ARCHITECTURE.md](ARCHITECTURE.md) - Architecture details
- [AI-GETTING-STARTED.md](AI-GETTING-STARTED.md) - AI setup
- [INCIDENT-MANAGER.md](INCIDENT-MANAGER.md) - On-call setup
- [CHATBOT-SETUP.md](CHATBOT-SETUP.md) - Teams/Slack setup
- [web-ui/README.md](web-ui/README.md) - Web UI details
- [DAY2-OPERATIONS.md](DAY2-OPERATIONS.md) - Operations guide
