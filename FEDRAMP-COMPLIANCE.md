# FedRAMP Compliance Guide

This document outlines FedRAMP compliance considerations for the Enhanced EKS Cluster in AWS GovCloud.

## FedRAMP Authorization Status

### ✅ FedRAMP High Authorized Components

**AWS Services:**
- AWS EKS (Elastic Kubernetes Service)
- AWS Secrets Manager
- AWS KMS (Key Management Service)
- AWS GuardDuty
- AWS Security Hub
- AWS CloudWatch
- AWS X-Ray
- AWS VPC
- AWS EBS/EFS/S3
- AWS RDS/DynamoDB
- AWS Bedrock
- AWS ECR

**EKS Add-ons (AWS-managed):**
- kube-proxy
- vpc-cni
- coredns
- aws-ebs-csi-driver
- aws-efs-csi-driver
- aws-mountpoint-s3-csi-driver
- ADOT (AWS Distro for OpenTelemetry)

### ❌ NOT FedRAMP Authorized (Open Source)

**Third-Party Components:**
- External Secrets Operator (CNCF project)
- Istio (CNCF project)
- KEDA (CNCF project)
- Prometheus (CNCF project)
- Kiali (Istio project)
- Metrics Server (Kubernetes SIG)

**Note:** These are open-source projects that run in your VPC but are not themselves FedRAMP authorized services.

---

## Secrets Management: Compliance Trade-offs

### Option 1: External Secrets Operator (Default)

**Status:** ❌ NOT FedRAMP authorized

**Architecture:**
```
AWS Secrets Manager (✅ FedRAMP High)
    ↓ (TLS)
External Secrets Operator (❌ Not FedRAMP)
    ↓
Kubernetes Secrets (✅ KMS encrypted)
    ↓
Application Pods
```

**Pros:**
- ✅ Automatic sync from Secrets Manager to Kubernetes
- ✅ Declarative ExternalSecret resources
- ✅ Supports multiple secret backends
- ✅ Open source (auditable code)
- ✅ Runs in your VPC (no external dependencies)
- ✅ Only orchestrates - doesn't store secrets
- ✅ AWS services (Secrets Manager, KMS) are FedRAMP authorized

**Cons:**
- ❌ External Secrets Operator itself is not FedRAMP authorized
- ❌ May not pass strict FedRAMP audits
- ❌ Requires ATO (Authority to Operate) justification

**When to Use:**
- Development/staging environments
- Organizations with approved open-source policies
- When developer experience is prioritized
- When automatic sync is required

**Enable:**
```hcl
enable_external_secrets = true
enable_secrets_store_csi = false
```

---

### Option 2: Secrets Store CSI Driver (FedRAMP Compliant)

**Status:** ✅ AWS-supported (uses only FedRAMP services)

**Architecture:**
```
AWS Secrets Manager (✅ FedRAMP High)
    ↓ (TLS via Pod Identity)
Secrets Store CSI Driver (✅ Kubernetes SIG)
    ↓
Volume Mount in Pod
    ↓
Application Reads Files
```

**Pros:**
- ✅ Uses only FedRAMP authorized AWS services
- ✅ AWS officially supports this approach
- ✅ No third-party operators required
- ✅ Direct integration with Pod Identity
- ✅ Secrets mounted as files (immutable)
- ✅ Automatic rotation support

**Cons:**
- ❌ Secrets only available as volume mounts (not env vars by default)
- ❌ No automatic sync to Kubernetes Secrets (optional)
- ❌ More complex pod configuration
- ❌ Application must read from files

**When to Use:**
- Production environments requiring strict FedRAMP compliance
- Organizations with strict compliance requirements
- When ATO requires only FedRAMP authorized components
- DoD/Federal agencies

**Enable:**
```hcl
enable_external_secrets = false
enable_secrets_store_csi = true
```

---

### Option 3: Direct AWS SDK (Most Compliant)

**Status:** ✅ 100% FedRAMP authorized

**Architecture:**
```
AWS Secrets Manager (✅ FedRAMP High)
    ↓ (TLS via Pod Identity)
Application Code (AWS SDK)
```

**Pros:**
- ✅ No additional components required
- ✅ 100% FedRAMP authorized
- ✅ Maximum control and flexibility
- ✅ Lowest attack surface

**Cons:**
- ❌ Application code must handle secret retrieval
- ❌ No caching (unless implemented)
- ❌ Increased API calls to Secrets Manager
- ❌ More complex application code

**When to Use:**
- Maximum security requirements
- Simple applications with few secrets
- When you want complete control

**Example (Python):**
```python
import boto3

client = boto3.client('secretsmanager', region_name='us-gov-west-1')
response = client.get_secret_value(SecretId='enhanced-eks-cluster/prod/db-creds')
secret = json.loads(response['SecretString'])
```

---

## Comparison Matrix

| Feature | External Secrets | CSI Driver | Direct SDK |
|---------|-----------------|------------|------------|
| **FedRAMP Authorized** | ❌ No | ✅ Yes | ✅ Yes |
| **Ease of Use** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| **Auto Sync** | ✅ Yes | ⚠️ Optional | ❌ No |
| **Env Vars** | ✅ Yes | ⚠️ Optional | ✅ Yes |
| **Volume Mounts** | ✅ Yes | ✅ Yes | ❌ No |
| **Rotation** | ✅ Auto | ✅ Auto | ⚠️ Manual |
| **API Calls** | Low | Low | High |
| **Complexity** | Low | Medium | High |
| **ATO Risk** | ⚠️ Medium | ✅ Low | ✅ Low |

---

## Usage Examples

### External Secrets Operator

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-creds
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-creds
  data:
  - secretKey: password
    remoteRef:
      key: enhanced-eks-cluster/prod/db-creds
      property: password
---
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
  - name: app
    image: my-app
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-creds
          key: password
```

### Secrets Store CSI Driver

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-secrets
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "enhanced-eks-cluster/prod/db-creds"
        objectType: "secretsmanager"
        jmesPath:
          - path: password
            objectAlias: db-password
---
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  serviceAccountName: default
  containers:
  - name: app
    image: my-app
    volumeMounts:
    - name: secrets
      mountPath: /mnt/secrets
      readOnly: true
    env:
    - name: DB_PASSWORD
      value: /mnt/secrets/db-password
  volumes:
  - name: secrets
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: aws-secrets
```

Application reads from file:
```python
with open('/mnt/secrets/db-password', 'r') as f:
    db_password = f.read().strip()
```

---

## Recommendation by Environment

### Development/Staging
**Use:** External Secrets Operator
- Faster development
- Better developer experience
- Easier debugging

### Production (Moderate Compliance)
**Use:** External Secrets Operator with ATO justification
- Document that only AWS services store/encrypt secrets
- External Secrets Operator only orchestrates
- Open source code is auditable
- Runs in your VPC

### Production (Strict FedRAMP)
**Use:** Secrets Store CSI Driver
- AWS-supported approach
- Only FedRAMP authorized components
- Easier ATO approval

### Production (Maximum Security)
**Use:** Direct AWS SDK
- No additional components
- Complete control
- Lowest attack surface

---

## ATO Justification for External Secrets Operator

If using External Secrets Operator in a FedRAMP environment, document:

1. **Secrets Storage:** All secrets stored in AWS Secrets Manager (FedRAMP High)
2. **Encryption:** All secrets encrypted with AWS KMS (FedRAMP High, FIPS 140-2)
3. **Transit:** All communication over TLS
4. **Access Control:** IAM Pod Identity (FedRAMP High)
5. **Audit:** CloudTrail logs all secret access (FedRAMP High)
6. **Operator Role:** Only orchestrates - never stores secrets
7. **Network:** Runs in private VPC subnets
8. **Code:** Open source, auditable on GitHub
9. **Updates:** Regular security patches applied

---

## Other Non-FedRAMP Components

### Istio Service Mesh
**Status:** ❌ Not FedRAMP authorized
**Mitigation:** 
- Provides mTLS (required for STIG)
- Open source, auditable
- Widely used in government
- Consider AWS App Mesh (FedRAMP High) as alternative

### KEDA Autoscaling
**Status:** ❌ Not FedRAMP authorized
**Mitigation:**
- Only scales pods, doesn't handle data
- Open source, auditable
- Can be disabled if not needed

### Prometheus
**Status:** ❌ Not FedRAMP authorized
**Mitigation:**
- Use AWS CloudWatch (FedRAMP High) instead
- Or use AWS Managed Prometheus (FedRAMP High)

---

## FedRAMP Compliance Checklist

### Infrastructure Layer
- [✅] EKS cluster (FedRAMP High)
- [✅] VPC with private subnets
- [✅] KMS encryption (FIPS 140-2)
- [✅] GuardDuty enabled
- [✅] Security Hub enabled
- [✅] CloudTrail logging
- [✅] VPC Flow Logs (optional)

### Secrets Management
- [✅] AWS Secrets Manager (FedRAMP High)
- [⚠️] External Secrets Operator (requires ATO justification)
- [✅] Secrets Store CSI Driver (FedRAMP compliant alternative)

### Monitoring & Logging
- [✅] CloudWatch Logs (FedRAMP High)
- [✅] AWS X-Ray (FedRAMP High)
- [⚠️] Prometheus (not FedRAMP - use CloudWatch)

### Service Mesh
- [⚠️] Istio (not FedRAMP - required for STIG mTLS)
- [✅] Alternative: AWS App Mesh (FedRAMP High)

---

## Switching Between Options

### From External Secrets to CSI Driver

1. Disable External Secrets Operator:
```hcl
enable_external_secrets = false
enable_secrets_store_csi = true
```

2. Apply Terraform:
```bash
terraform apply
```

3. Update pod manifests to use CSI volumes
4. Redeploy applications

### From CSI Driver to External Secrets

1. Enable External Secrets Operator:
```hcl
enable_external_secrets = true
enable_secrets_store_csi = false
```

2. Apply Terraform:
```bash
terraform apply
```

3. Create ExternalSecret resources
4. Update pod manifests to use Kubernetes secrets
5. Redeploy applications

---

## Additional Resources

- [AWS FedRAMP Compliance](https://aws.amazon.com/compliance/fedramp/)
- [EKS Best Practices - Security](https://aws.github.io/aws-eks-best-practices/security/docs/)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
- [External Secrets Operator](https://external-secrets.io/)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
