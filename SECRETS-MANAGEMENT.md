# Secrets Management Guide

This guide explains how to use AWS Secrets Manager with External Secrets Operator in your EKS cluster.

## Architecture Options

### Option 1: External Secrets Operator (Default - NOT FedRAMP authorized)

```
AWS Secrets Manager (✅ FedRAMP High)
    ↓
External Secrets Operator (❌ Not FedRAMP)
    ↓
Kubernetes Secrets (✅ KMS Encrypted)
    ↓
Application Pods
```

### Option 2: Secrets Store CSI Driver (FedRAMP Compliant)

```
AWS Secrets Manager (✅ FedRAMP High)
    ↓
Secrets Store CSI Driver (✅ AWS-supported)
    ↓
Volume Mount in Pod
    ↓
Application Reads Files
```

**For strict FedRAMP compliance, use Option 2.** See [FEDRAMP-COMPLIANCE.md](FEDRAMP-COMPLIANCE.md) for details.

## Prerequisites

- External Secrets Operator installed (`enable_external_secrets = true`)
- ClusterSecretStore configured (automatic)
- Pod Identity permissions for External Secrets Operator (automatic)

## Creating Secrets in AWS Secrets Manager

### Option 1: AWS CLI

```bash
# Create a secret
aws secretsmanager create-secret \
  --name enhanced-eks-cluster/production/database-credentials \
  --description "Production database credentials" \
  --secret-string '{"username":"admin","password":"supersecret","host":"db.example.com","port":"5432"}' \
  --kms-key-id $(terraform output -raw secrets_manager_kms_key_id) \
  --region us-gov-west-1

# Update a secret
aws secretsmanager update-secret \
  --secret-id enhanced-eks-cluster/production/database-credentials \
  --secret-string '{"username":"admin","password":"newsecret","host":"db.example.com","port":"5432"}' \
  --region us-gov-west-1

# Enable automatic rotation (for RDS)
aws secretsmanager rotate-secret \
  --secret-id enhanced-eks-cluster/production/database-credentials \
  --rotation-lambda-arn arn:aws-us-gov:lambda:us-gov-west-1:123456789012:function:SecretsManagerRDSRotation \
  --rotation-rules AutomaticallyAfterDays=90 \
  --region us-gov-west-1
```

### Option 2: Terraform

```hcl
resource "aws_secretsmanager_secret" "app_credentials" {
  name                    = "enhanced-eks-cluster/production/app-credentials"
  description             = "Application credentials"
  kms_key_id              = aws_kms_key.secrets_manager.id
  recovery_window_in_days = 30
}

resource "aws_secretsmanager_secret_version" "app_credentials" {
  secret_id = aws_secretsmanager_secret.app_credentials.id
  secret_string = jsonencode({
    api_key    = "your-api-key"
    api_secret = "your-api-secret"
  })
}
```

## Syncing Secrets to Kubernetes

### Create an ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: default
spec:
  refreshInterval: 1h  # Sync every hour
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: database-credentials  # Kubernetes secret name
    creationPolicy: Owner
  data:
  - secretKey: username
    remoteRef:
      key: enhanced-eks-cluster/production/database-credentials
      property: username
  - secretKey: password
    remoteRef:
      key: enhanced-eks-cluster/production/database-credentials
      property: password
  - secretKey: host
    remoteRef:
      key: enhanced-eks-cluster/production/database-credentials
      property: host
  - secretKey: port
    remoteRef:
      key: enhanced-eks-cluster/production/database-credentials
      property: port
```

Apply the ExternalSecret:
```bash
kubectl apply -f external-secret.yaml
```

Verify the Kubernetes secret was created:
```bash
kubectl get secret database-credentials -o yaml
```

### Sync Entire Secret as JSON

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-config
  namespace: default
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: app-config
  dataFrom:
  - extract:
      key: enhanced-eks-cluster/production/app-config
```

## Using Secrets in Pods

### Environment Variables

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: DB_USERNAME
      valueFrom:
        secretKeyRef:
          name: database-credentials
          key: username
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: database-credentials
          key: password
    - name: DB_HOST
      valueFrom:
        secretKeyRef:
          name: database-credentials
          key: host
    - name: DB_PORT
      valueFrom:
        secretKeyRef:
          name: database-credentials
          key: port
```

### Volume Mounts

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app:latest
    volumeMounts:
    - name: secrets
      mountPath: /etc/secrets
      readOnly: true
  volumes:
  - name: secrets
    secret:
      secretName: database-credentials
```

Access secrets as files:
```bash
cat /etc/secrets/username
cat /etc/secrets/password
```

## Secret Naming Convention

Use hierarchical naming for organization:

```
enhanced-eks-cluster/
├── production/
│   ├── database-credentials
│   ├── api-keys
│   └── certificates
├── staging/
│   ├── database-credentials
│   └── api-keys
└── shared/
    └── external-service-credentials
```

## Secret Rotation

### Automatic Rotation (RDS, Redshift, DocumentDB)

```bash
# Enable automatic rotation for RDS
aws secretsmanager rotate-secret \
  --secret-id enhanced-eks-cluster/production/rds-credentials \
  --rotation-lambda-arn arn:aws-us-gov:lambda:us-gov-west-1:123456789012:function:SecretsManagerRDSRotation \
  --rotation-rules AutomaticallyAfterDays=90 \
  --region us-gov-west-1
```

### Manual Rotation

1. Update secret in Secrets Manager
2. External Secrets Operator syncs automatically (based on refreshInterval)
3. Restart pods to pick up new values:

```bash
kubectl rollout restart deployment/my-app
```

## Monitoring and Troubleshooting

### Check External Secrets Operator Status

```bash
# Check operator pods
kubectl get pods -n external-secrets

# Check operator logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Check ExternalSecret status
kubectl describe externalsecret database-credentials
```

### Common Issues

**ExternalSecret not syncing:**
```bash
# Check ExternalSecret events
kubectl describe externalsecret database-credentials

# Verify ClusterSecretStore
kubectl get clustersecretstore aws-secrets-manager -o yaml

# Check IAM permissions
aws sts get-caller-identity
```

**Secret not found in Secrets Manager:**
```bash
# List secrets
aws secretsmanager list-secrets --region us-gov-west-1

# Verify secret exists
aws secretsmanager describe-secret \
  --secret-id enhanced-eks-cluster/production/database-credentials \
  --region us-gov-west-1
```

## Security Best Practices

### 1. Use Least Privilege IAM

External Secrets Operator only has access to secrets with prefix `enhanced-eks-cluster/*`:

```json
{
  "Effect": "Allow",
  "Action": [
    "secretsmanager:GetSecretValue",
    "secretsmanager:DescribeSecret"
  ],
  "Resource": "arn:aws-us-gov:secretsmanager:us-gov-west-1:*:secret:enhanced-eks-cluster/*"
}
```

### 2. Enable KMS Encryption

All secrets are encrypted with customer-managed KMS key (FIPS 140-2):
```bash
terraform output secrets_manager_kms_key_arn
```

### 3. Enable CloudTrail Logging

Monitor secret access:
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=enhanced-eks-cluster/production/database-credentials \
  --region us-gov-west-1
```

### 4. Set Appropriate Refresh Intervals

- **High-security secrets**: 5-15 minutes
- **Standard secrets**: 1 hour
- **Static configuration**: 24 hours

### 5. Use Recovery Windows

All secrets have 30-day recovery window to prevent accidental deletion.

## STIG Compliance

External Secrets Operator helps meet these STIG requirements:

- ✅ **V-242415**: Secrets stored in approved secret management system (Secrets Manager)
- ✅ **V-242416**: Secrets encrypted at rest (KMS FIPS 140-2)
- ✅ **V-242417**: Secrets encrypted in transit (TLS to Secrets Manager)
- ✅ **V-242418**: Least privilege access to secrets (IAM + Pod Identity)
- ✅ **V-242419**: Secret access audited (CloudTrail)
- ✅ **V-242420**: Secrets rotated regularly (90-day rotation)

## Cost Estimate

**AWS Secrets Manager Pricing (GovCloud):**
- Secret storage: $0.40/secret/month
- API calls: $0.05 per 10,000 calls

**Example:**
- 10 secrets: $4/month
- 100K API calls/month: $0.50/month
- **Total: ~$4.50/month**

External Secrets Operator caches secrets, minimizing API calls.

## Example: Complete Workflow

### 1. Create secret in Secrets Manager

```bash
aws secretsmanager create-secret \
  --name enhanced-eks-cluster/production/app-api-key \
  --secret-string '{"api_key":"sk-1234567890abcdef"}' \
  --kms-key-id $(terraform output -raw secrets_manager_kms_key_id) \
  --region us-gov-west-1
```

### 2. Create ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-api-key
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: app-api-key
  data:
  - secretKey: api_key
    remoteRef:
      key: enhanced-eks-cluster/production/app-api-key
      property: api_key
```

```bash
kubectl apply -f external-secret.yaml
```

### 3. Use in Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: my-app:latest
        env:
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: app-api-key
              key: api_key
```

```bash
kubectl apply -f deployment.yaml
```

### 4. Verify

```bash
# Check ExternalSecret
kubectl get externalsecret app-api-key

# Check Kubernetes secret
kubectl get secret app-api-key

# Check pod has secret
kubectl exec -it my-app-xxx -- env | grep API_KEY
```

## FedRAMP Compliance

**⚠️ WARNING:** External Secrets Operator is NOT FedRAMP authorized.

For strict FedRAMP compliance:
1. Use Secrets Store CSI Driver instead (`enable_secrets_store_csi = true`)
2. Or use direct AWS SDK calls from application code
3. See [FEDRAMP-COMPLIANCE.md](FEDRAMP-COMPLIANCE.md) for detailed comparison

## Additional Resources

- [FedRAMP Compliance Guide](FEDRAMP-COMPLIANCE.md)
- [External Secrets Operator Documentation](https://external-secrets.io/)
- [Secrets Store CSI Driver Documentation](https://secrets-store-csi-driver.sigs.k8s.io/)
- [AWS Secrets Manager User Guide](https://docs.aws.amazon.com/secretsmanager/)
- [EKS Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
