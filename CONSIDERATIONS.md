# Production Readiness Considerations

This document outlines additional considerations for production deployment beyond the current implementation.

## 🔴 High Priority (Before Production)

### 1. Security Hardening

**✅ KMS Encryption for Secrets (IMPLEMENTED)**
- EKS secrets encryption with customer-managed KMS key
- EBS volume encryption enabled by default
- Secrets Manager encryption with KMS
- FIPS 140-2 validated encryption
- Automatic key rotation enabled
- Toggle: Always enabled

**✅ Secrets Management (IMPLEMENTED)**
- AWS Secrets Manager with KMS encryption
- External Secrets Operator (default - NOT FedRAMP authorized)
- Secrets Store CSI Driver (FedRAMP compliant alternative)
- Pod Identity for secure access
- Toggle: `enable_external_secrets` or `enable_secrets_store_csi`
- See [FEDRAMP-COMPLIANCE.md](FEDRAMP-COMPLIANCE.md) for comparison

**Private EKS Endpoint (Production):**
- Current: Public + Private access enabled (for development)
- Production: Disable public access after TGW VPN setup
- Set `endpoint_public_access = false` in main.tf
- Access via: TGW VPN, Direct Connect, or bastion host
- Alternative: Restrict public access to specific CIDRs
- Status: Deferred until TGW VPN infrastructure ready

**✅ Network Policies (VPC CNI Ready)**
- VPC CNI supports native Kubernetes NetworkPolicy
- No additional CNI required (Calico not needed)
- Define policies when deploying application workloads
- Example default-deny-all policy:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

**✅ EKS Audit Logs (IMPLEMENTED)**
- All control plane logs enabled (api, audit, authenticator, controllerManager, scheduler)
- Sent to CloudWatch Logs
- Required for: STIG compliance, GuardDuty EKS protection
- Retention: 90 days (CloudWatch default)
- Cost: ~$0.50/GB ingested + $0.03/GB stored

**✅ CloudTrail (IMPLEMENTED)**
- All API calls logged (management + data events)
- S3 bucket with 7-year retention (Glacier lifecycle)
- CloudWatch Logs integration (90-day retention)
- KMS encryption for log files
- Log file validation enabled
- API call rate insights enabled
- Toggle: `enable_cloudtrail = true` in terraform.tfvars
- Cost: ~$5-10/month

**✅ VPC Flow Logs (IMPLEMENTED)**
- Dual destination: CloudWatch Logs + S3
- S3 with Parquet format and hourly partitions
- KMS encryption for both destinations
- CloudWatch retention: 30 days
- S3 retention: 90 days
- Toggle: `enable_vpc_flow_logs = true` in terraform.tfvars
- Cost: ~$10-20/month

**✅ GuardDuty for EKS (IMPLEMENTED)**
- Runtime threat detection enabled
- EKS audit logs monitoring
- Malware scanning for EBS volumes
- SNS alerts for critical findings
- Toggle: `enable_guardduty = true` in terraform.tfvars

**✅ AWS Security Hub (IMPLEMENTED)**
- CIS AWS Foundations Benchmark v1.4.0
- AWS Foundational Security Best Practices
- Automated compliance monitoring
- GuardDuty integration
- Toggle: `enable_security_hub = true` in terraform.tfvars

**✅ VPC Endpoints (IMPLEMENTED)**
- 30+ interface endpoints for AWS services
- S3 and DynamoDB gateway endpoints
- Enables NAT-less operation
- Toggle: `enable_vpc_endpoints = false` (disabled by default)
- Cost: ~$50-100/month if enabled

### 2. High Availability

**Multiple NAT Gateways (Production):**
```hcl
# In terraform.tfvars
nat_gateway_count = 3  # One per AZ
```

**Pod Disruption Budgets:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: critical-app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: critical-app
```

### 3. Resource Management

**Namespace ResourceQuotas:**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: production
spec:
  hard:
    requests.cpu: "100"
    requests.memory: 200Gi
    limits.cpu: "200"
    limits.memory: 400Gi
```

**LimitRanges:**
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
```

### 4. Backup & Disaster Recovery

**✅ Disaster Recovery Plan (IMPLEMENTED)**
- RTO: 4 hours, RPO: 1 hour
- 5 disaster scenarios documented
- Backup strategies for all components
- Monthly/quarterly/annual testing schedule
- See [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md)

**✅ Incident Response Plan (IMPLEMENTED)**
- 5-phase response process (Detection → Recovery → Post-Incident)
- P0-P3 severity classification with response times
- Security and operational incident procedures
- Forensics and evidence collection
- Quarterly testing schedule
- See [INCIDENT-RESPONSE.md](INCIDENT-RESPONSE.md)

**Velero for Cluster Backups (Optional):**
```bash
# Install Velero
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --set configuration.backupStorageLocation.bucket=my-backup-bucket \
  --set configuration.backupStorageLocation.config.region=us-gov-west-1
```

**EBS Snapshot Lifecycle (Optional):**
```hcl
resource "aws_dlm_lifecycle_policy" "ebs_backup" {
  description        = "EBS snapshot lifecycle"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"
  
  policy_details {
    resource_types = ["VOLUME"]
    schedule {
      name = "Daily snapshots"
      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }
      retain_rule {
        count = 7
      }
    }
  }
}
```

---

## 🟡 Medium Priority (Within 30 Days)

### 5. Monitoring & Alerting

**✅ AWS Systems Manager Incident Manager (IMPLEMENTED)**
- On-call rotation with SMS alerts
- Engagement plans with escalation policies
- Response plans for automated runbooks
- CloudWatch alarm integration
- Toggle: `enable_incident_manager = true` in terraform.tfvars
- Cost: $3.50/month per contact + SMS charges
- See [INCIDENT-MANAGER.md](INCIDENT-MANAGER.md)

**✅ AWS Chatbot (IMPLEMENTED)**
- Microsoft Teams and Slack integration
- Real-time alerts (FREE - no per-message cost)
- EventBridge integration
- SNS topic subscriptions
- Toggle: `enable_chatbot = true` in terraform.tfvars
- Cost: FREE
- See [CHATBOT-SETUP.md](CHATBOT-SETUP.md)

**AlertManager Configuration (Optional):**
```yaml
# Add to Prometheus Helm values
alertmanager:
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'cluster']
      receiver: 'pagerduty'
    receivers:
    - name: 'pagerduty'
      pagerduty_configs:
      - service_key: '<key>'
```

**Key Alerts to Configure:**
- Node CPU/Memory > 80%
- Pod CrashLoopBackOff
- PVC usage > 85%
- Certificate expiration < 30 days
- API server latency > 1s
- etcd leader changes

### 6. Cost Management

**Add Cost Allocation Tags:**
```hcl
tags = {
  Environment = "production"
  CostCenter  = "engineering"
  Project     = "enhanced-eks"
  ManagedBy   = "terraform"
}
```

**Install Kubecost:**
```bash
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --set kubecostToken="<token>"
```

### 7. Certificate Management

**✅ Use AWS Certificate Manager (ACM) - FedRAMP Compliant**

ACM is FedRAMP High authorized and recommended for GovCloud:

```bash
# Request certificate via AWS CLI
aws acm request-certificate \
  --domain-name "*.example.com" \
  --subject-alternative-names "example.com" \
  --validation-method DNS \
  --region us-gov-west-1

# Use with ALB Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: arn:aws-us-gov:acm:us-gov-west-1:123456789012:certificate/xxxxx
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
spec:
  ingressClassName: alb
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

**Benefits:**
- ✅ FedRAMP High authorized
- ✅ Automatic renewal
- ✅ Free for AWS resources
- ✅ Integrates with ALB/NLB
- ✅ No cert-manager needed (not FedRAMP authorized)

**Note:** cert-manager is NOT FedRAMP authorized. Use ACM for compliance.

### 8. GitOps (Optional)

**ArgoCD vs CI/CD Pipeline Deployments:**

| Feature | ArgoCD | GitHub/GitLab CI/CD |
|---------|--------|---------------------|
| **Deployment Model** | Pull (cluster pulls from Git) | Push (pipeline pushes to cluster) |
| **Cluster Access** | No external access needed | Requires kubectl/API access |
| **Drift Detection** | Automatic | Manual |
| **Rollback** | One-click in UI | Re-run pipeline |
| **Multi-cluster** | Built-in | Complex |
| **FedRAMP Status** | ❌ Not authorized | ✅ GitHub/GitLab authorized |
| **Complexity** | Higher (new tool) | Lower (existing CI/CD) |
| **Audit Trail** | ArgoCD UI + Git | Git + CI/CD logs |

**Recommendation: Use CI/CD Pipeline for GovCloud**

**Why CI/CD is better for your use case:**
- ✅ GitHub/GitLab are FedRAMP authorized
- ✅ ArgoCD is NOT FedRAMP authorized
- ✅ Simpler: Use existing CI/CD infrastructure
- ✅ Fewer components to maintain
- ✅ Standard `helm upgrade` from pipeline
- ✅ Works with private EKS endpoint (via TGW VPN)

**Example GitHub Actions Deployment:**
```yaml
name: Deploy to EKS
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: self-hosted  # In VPC for private endpoint
    steps:
    - uses: actions/checkout@v3
    
    - name: Configure kubectl
      run: |
        aws eks update-kubeconfig \
          --region us-gov-west-1 \
          --name enhanced-eks-cluster
    
    - name: Deploy with Helm
      run: |
        helm upgrade --install my-app ./charts/my-app \
          --namespace production \
          --values values-prod.yaml \
          --wait
```

**When ArgoCD makes sense:**
- Multiple clusters to manage
- Need automatic drift detection
- Team prefers GitOps model
- Can accept non-FedRAMP component

**For GovCloud STIG compliance: Stick with CI/CD pipelines.**

---

## 🟢 Low Priority (Nice to Have)

### 9. Service Mesh Enhancements

**Istio Egress Gateway:**
```yaml
# Control all outbound traffic
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: istio-egressgateway
spec:
  selector:
    istio: egressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - "*"
```

### 10. Advanced Observability

**Distributed Tracing with Jaeger:**
```bash
# Alternative to X-Ray for on-cluster tracing
kubectl apply -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/main/deploy/crds/jaegertracing.io_jaegers_crd.yaml
```

**Grafana Dashboards:**
```bash
helm install grafana grafana/grafana \
  --set persistence.enabled=true \
  --set adminPassword='<password>'
```

### 11. External DNS

**Automatic DNS Record Management:**
```bash
helm install external-dns bitnami/external-dns \
  --set provider=aws \
  --set aws.region=us-gov-west-1 \
  --set txtOwnerId=enhanced-eks-cluster
```

### 12. Image Security

**Enable ECR Image Scanning:**
```hcl
resource "aws_ecr_repository" "app" {
  name                 = "my-app"
  image_tag_mutability = "IMMUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
}
```

**Admission Controller (OPA Gatekeeper):**
```bash
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/deploy/gatekeeper.yaml
```

---

## 📋 Compliance Checklist (GovCloud)

### FedRAMP Requirements:
- [✅] Enable CloudTrail for all API calls (IMPLEMENTED)
- [✅] Enable VPC Flow Logs (IMPLEMENTED)
- [✅] Enable GuardDuty for EKS (IMPLEMENTED)
- [✅] Implement least privilege IAM (Pod Identity implemented)
- [✅] Enable secrets encryption with KMS (IMPLEMENTED)
- [✅] Configure audit logging (EKS control plane logs - IMPLEMENTED)
- [✅] Implement network segmentation (VPC, subnets, security groups)
- [✅] Regular vulnerability scanning (Trivy in CI/CD)
- [✅] Incident response plan (IMPLEMENTED)
- [✅] Disaster recovery testing (IMPLEMENTED)

### STIG Compliance:
- [✅] CIS Kubernetes Benchmark (Security Hub automated)
- [ ] Pod Security Standards (restricted)
- [✅] Disable anonymous auth (EKS default)
- [✅] Enable RBAC (EKS default)
- [ ] Secure kubelet configuration
- [ ] Regular security updates

### Implemented Security Controls:
- [✅] V-242378: Kubernetes secrets encrypted at rest (KMS)
- [✅] V-242379: FIPS 140-2 validated encryption (KMS)
- [✅] V-242442: Audit logging enabled (GuardDuty)
- [✅] V-242443: Security-relevant events logged (GuardDuty + CloudWatch)
- [✅] V-242461: Intrusion detection enabled (GuardDuty)
- [✅] V-242462: Continuous monitoring (GuardDuty + Security Hub)

---

## 🎯 Recommended Implementation Order

### Week 1:
1. Enable KMS encryption for secrets
2. Configure EKS audit logs
3. Add ResourceQuotas and LimitRanges
4. Deploy PodDisruptionBudgets

### Week 2:
5. Implement network policies
6. Set up Velero backups
7. Configure AlertManager
8. Add cost allocation tags

### Week 3:
9. Install cert-manager
10. Deploy ArgoCD
11. Configure external-dns
12. Set up Grafana dashboards

### Week 4:
13. Implement OPA Gatekeeper policies
14. Enable ECR image scanning
15. Configure GuardDuty
16. Disaster recovery testing

---

## 💰 Cost Impact of Additions

| Feature | Monthly Cost (GovCloud) | Status | Priority |
|---------|------------------------|--------|----------|
| KMS Keys (3) | +$3 | ✅ Implemented | High |
| GuardDuty | +$30-50 | ✅ Implemented | High |
| Security Hub | +$10-15 | ✅ Implemented | High |
| CloudTrail | +$5-10 | ✅ Implemented | High |
| VPC Flow Logs | +$10-20 | ✅ Implemented | High |
| VPC Endpoints (if enabled) | +$50-100 | ✅ Optional | High |
| Incident Manager (if enabled) | +$8-15 | ✅ Optional | High |
| Chatbot (if enabled) | FREE | ✅ Optional | High |
| Bedrock AI (if enabled) | +$50-100 | ✅ Optional | Medium |
| 3 NAT Gateways (HA) | +$197 | ❌ Not implemented | High |
| Velero (S3 storage) | +$5-10 | ❌ Not implemented | High |
| Kubecost | Free tier | ❌ Not implemented | Medium |
| Grafana (EBS) | +$10 | ❌ Not implemented | Low |
| **Current Additional** | **~$58-98/month** | | |
| **With All Optional** | **~$166-298/month** | | |
| **With All Additions** | **~$378-505/month** | | |

---

## 🔒 Security Best Practices Summary

1. **Never commit secrets** to Git (use Secrets Manager/Parameter Store)
2. **Rotate credentials** regularly (90 days max)
3. **Use least privilege** IAM policies
4. **Enable MFA** for all human access
5. **Scan images** before deployment
6. **Update regularly** (Kubernetes, add-ons, Helm charts)
7. **Monitor audit logs** for suspicious activity
8. **Test backups** monthly
9. **Document runbooks** for incidents
10. **Conduct security reviews** quarterly

---

## 📚 Additional Resources

- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [Kubernetes Security Checklist](https://kubernetes.io/docs/concepts/security/security-checklist/)
- [AWS GovCloud Compliance](https://aws.amazon.com/compliance/services-in-scope/)
