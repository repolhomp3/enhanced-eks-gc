# SRE Assistant Web UI

Web-based chat interface for EKS cluster operations via Amazon Bedrock AI agent.

## Features

- Real-time chat with Bedrock AI agent
- Query pod health, logs, metrics
- Check Kinesis streams, S3 buckets, Glue jobs
- Dark theme optimized for SRE work
- Session persistence
- Example queries for quick access

## Architecture

```
Browser → Flask App (EKS Pod) → Bedrock Agent → MCP Lambda → K8s/AWS APIs
```

## Local Development

```bash
cd web-ui

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export AWS_REGION=us-gov-west-1
export AGENT_ID=your-agent-id
export AGENT_ALIAS_ID=production
export SECRET_KEY=$(python -c 'import os; print(os.urandom(24).hex())')

# Run Flask app
python app/main.py

# Open browser
open http://localhost:8080
```

## Build and Push to ECR

```bash
# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create ECR repository
aws ecr create-repository \
  --repository-name sre-assistant \
  --region us-gov-west-1

# Login to ECR
aws ecr get-login-password --region us-gov-west-1 | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com

# Build image
docker build -t sre-assistant .

# Tag image
docker tag sre-assistant:latest $ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/sre-assistant:latest

# Push to ECR
docker push $ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/sre-assistant:latest
```

## Deploy to EKS

### Option 1: Helm (Recommended)

```bash
# Get values
AGENT_ID=$(cat ../bedrock_agent_id.txt)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
FLASK_SECRET_KEY=$(python -c 'import os; print(os.urandom(24).hex())')

# Deploy with Helm
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

### Option 2: GitLab CI/CD (Automated)

Set GitLab CI/CD variables:
- `AWS_ACCOUNT_ID`
- `EKS_CLUSTER_NAME`
- `POD_IDENTITY_ROLE_ARN`
- `BEDROCK_AGENT_ID`
- `FLASK_SECRET_KEY`
- `ACM_CERTIFICATE_ARN`
- `INGRESS_HOST`

Push to `develop` or `main` branch - automatic deployment!

## Create IAM Role for Pod Identity

```bash
# Create IAM role
aws iam create-role \
  --role-name enhanced-eks-cluster-sre-assistant-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Service": "pods.eks.amazonaws.com"
      },
      "Action": ["sts:AssumeRole", "sts:TagSession"]
    }]
  }' \
  --region us-gov-west-1

# Attach policy
aws iam put-role-policy \
  --role-name enhanced-eks-cluster-sre-assistant-role \
  --policy-name bedrock-invoke \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["bedrock:InvokeAgent"],
      "Resource": "*"
    }]
  }' \
  --region us-gov-west-1

# Create Pod Identity association
aws eks create-pod-identity-association \
  --cluster-name enhanced-eks-cluster \
  --namespace sre-assistant \
  --service-account sre-assistant \
  --role-arn arn:aws-us-gov:iam::$ACCOUNT_ID:role/enhanced-eks-cluster-sre-assistant-role \
  --region us-gov-west-1
```

## Helm Chart Values

Customize `helm/sre-assistant/values.yaml` or use `--set`:

```yaml
replicaCount: 2
image:
  repository: <account-id>.dkr.ecr.us-gov-west-1.amazonaws.com/sre-assistant
  tag: latest
bedrock:
  agentId: <agent-id>
  region: us-gov-west-1
ingress:
  enabled: true
  host: sre-assistant.internal.example.com
  certificateArn: <acm-cert-arn>
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
```

## Access Web UI

### Option 1: Port Forward (Development)

```bash
kubectl port-forward -n sre-assistant svc/sre-assistant 8080:80

# Open browser
open http://localhost:8080
```

### Option 2: Internal ALB (Production)

```bash
# Get ALB DNS name
kubectl get ingress -n sre-assistant sre-assistant -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Access via internal DNS
# https://sre-assistant.internal.example.com
```

### Option 3: VPN/Bastion

```bash
# SSH tunnel through bastion
ssh -L 8080:sre-assistant.sre-assistant.svc.cluster.local:80 bastion-host

# Open browser
open http://localhost:8080
```

## Example Queries

**Pod Health:**
- "Get health of all pods in default namespace"
- "Show me pods that are not running"
- "Check deployment status for api-service"

**Logs:**
- "Probe logs for errors in api-service pod"
- "Show me the last 100 lines of logs from nginx pod"

**Data Pipeline:**
- "How many records were sent to my-kinesis-stream in the last hour?"
- "How many files are in s3://my-bucket/bronze/?"
- "Is the glue-etl-job running successfully?"
- "Check Glue crawler status"

**Cluster Health:**
- "Get cluster health"
- "Show me node resources"
- "Are there any failed nodes?"

## Security

- **Authentication**: Add OAuth/OIDC for production
- **Authorization**: Restrict by IAM role
- **Network**: Deploy behind internal ALB
- **Secrets**: Store in AWS Secrets Manager
- **Audit**: All queries logged to CloudWatch

## Monitoring

```bash
# View application logs
kubectl logs -n sre-assistant -l app=sre-assistant --tail=100 -f

# Check pod status
kubectl get pods -n sre-assistant

# View metrics
kubectl top pods -n sre-assistant
```

## Troubleshooting

### Pod Not Starting

```bash
# Check events
kubectl describe pod -n sre-assistant -l app=sre-assistant

# Check logs
kubectl logs -n sre-assistant -l app=sre-assistant
```

### Bedrock Agent Not Responding

```bash
# Check environment variables
kubectl exec -n sre-assistant -it deployment/sre-assistant -- env | grep AGENT

# Test Bedrock connectivity
kubectl exec -n sre-assistant -it deployment/sre-assistant -- \
  python -c "import boto3; print(boto3.client('bedrock-agent-runtime').list_agents())"
```

### 502 Bad Gateway

```bash
# Check service endpoints
kubectl get endpoints -n sre-assistant

# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(kubectl get ingress -n sre-assistant sre-assistant -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

## Customization

### Add Custom Queries

Edit `app/templates/index.html`:

```html
<button class="example-btn" onclick="sendExample('Your custom query')">Custom</button>
```

### Change Theme

Edit CSS in `app/templates/index.html`:

```css
body { background: #ffffff; color: #000000; }
```

### Add Authentication

```python
from flask import session, redirect, url_for
from functools import wraps

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

@app.route('/api/chat', methods=['POST'])
@login_required
def chat():
    # ...
```

## Cost

- **EKS Pods**: ~$10-20/month (2 replicas, 512Mi each)
- **ALB**: ~$16/month
- **Bedrock Invocations**: $3-15/1M tokens
- **Total**: ~$30-50/month

## Support

- Flask Docs: https://flask.palletsprojects.com/
- Bedrock Agent Runtime API: https://docs.aws.amazon.com/bedrock/latest/APIReference/API_agent-runtime_InvokeAgent.html
- EKS Pod Identity: https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html
