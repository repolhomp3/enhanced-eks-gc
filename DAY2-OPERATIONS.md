# Day 2 Operations Guide

This document outlines daily operations, monitoring, troubleshooting, and maintenance procedures for the Enhanced EKS Cluster in AWS GovCloud.

## Table of Contents

1. [Infrastructure Overview](#infrastructure-overview)
2. [Daily Operations](#daily-operations)
3. [Monitoring & Alerting](#monitoring--alerting)
4. [Common Tasks](#common-tasks)
5. [Troubleshooting](#troubleshooting)
6. [Maintenance Windows](#maintenance-windows)
7. [Incident Response](#incident-response)
8. [Capacity Planning](#capacity-planning)

---

## Infrastructure Overview

### What This Cluster Does

**Primary Functions:**
- Hosts containerized applications with Auto Mode scaling
- Provides service mesh (Istio) for mTLS and traffic management
- Event-driven autoscaling (KEDA) for workload optimization
- AI/ML workload support via Bedrock integration
- Data processing with S3, RDS, DynamoDB access
- Observability via Prometheus, X-Ray, CloudWatch

**Key Components:**
- **EKS Control Plane**: AWS-managed Kubernetes API (v1.34)
- **Auto Mode Nodes**: Automatically provisioned across 3 AZs
- **Istio Service Mesh**: mTLS, traffic routing, observability
- **KEDA**: Event-driven autoscaling (SQS, Kinesis, etc.)
- **Prometheus**: Metrics collection and alerting
- **AWS Services**: Bedrock, S3, RDS, DynamoDB, Secrets Manager

### SRE Responsibilities

**Daily:**
- Monitor cluster health dashboards
- Review GuardDuty/Security Hub findings
- Check pod/node resource utilization
- Verify backup completion

**Weekly:**
- Review cost reports (Kubecost/AWS Cost Explorer)
- Analyze performance trends
- Update runbooks based on incidents
- Security patch assessment

**Monthly:**
- Capacity planning review
- Disaster recovery testing
- Security compliance audit
- Update EKS/addon versions

---

## Daily Operations

### Morning Health Check (15 minutes)

**1. Cluster Status**
```bash
# Check cluster health
aws eks describe-cluster --name enhanced-eks-cluster --region us-gov-west-1 --query 'cluster.status'

# Check nodes
kubectl get nodes
kubectl top nodes

# Check system pods
kubectl get pods -n kube-system
kubectl get pods -n istio-system
kubectl get pods -n keda
```

**2. Application Health**
```bash
# Check all namespaces
kubectl get pods --all-namespaces | grep -v Running

# Check failed pods
kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded

# Check pod restarts
kubectl get pods --all-namespaces --sort-by='.status.containerStatuses[0].restartCount' | tail -20
```

**3. Security Alerts**
```bash
# GuardDuty findings (last 24 hours)
aws guardduty list-findings \
  --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text --region us-gov-west-1) \
  --finding-criteria '{"Criterion":{"updatedAt":{"Gte":'$(date -u -d '24 hours ago' +%s)'000}}}' \
  --region us-gov-west-1

# Security Hub critical findings
aws securityhub get-findings \
  --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}],"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' \
  --region us-gov-west-1 \
  --max-items 10
```

**4. Resource Utilization**
```bash
# Check PVC usage
kubectl get pvc --all-namespaces

# Check resource quotas
kubectl get resourcequota --all-namespaces

# Check Auto Mode scaling
kubectl get nodes -o wide
```

### Access Patterns

**Via TGW VPN (Production):**
```bash
# Connect to VPN first
# Then configure kubectl
aws eks update-kubeconfig --region us-gov-west-1 --name enhanced-eks-cluster

# Verify access
kubectl cluster-info
```

**Via Bastion Host:**
```bash
# SSH to bastion in VPC
ssh -i key.pem ec2-user@bastion-ip

# Configure kubectl on bastion
aws eks update-kubeconfig --region us-gov-west-1 --name enhanced-eks-cluster
```

**Via AWS Systems Manager:**
```bash
# Start session (no SSH keys needed)
aws ssm start-session --target i-xxxxx --region us-gov-west-1
```

---

## Monitoring & Alerting

### Key Dashboards

**1. Kiali Service Mesh (Port-forward required)**
```bash
kubectl port-forward -n istio-system svc/kiali-server 20001:20001
# Open: http://localhost:20001
```

**2. Prometheus Metrics**
```bash
kubectl port-forward -n prometheus svc/prometheus-server 9090:80
# Open: http://localhost:9090
```

**3. AWS CloudWatch**
- EKS Control Plane Logs: `/aws/eks/enhanced-eks-cluster/cluster`
- GuardDuty Findings: `/aws/guardduty/enhanced-eks-cluster`
- Security Hub Findings: `/aws/securityhub/enhanced-eks-cluster`

**4. AWS X-Ray**
- Service Map: Shows distributed tracing topology
- Traces: Request-level performance analysis

### Alert Channels

**SNS Topics:**
- GuardDuty Alerts: `enhanced-eks-cluster-guardduty-alerts`
- Security Hub Alerts: `enhanced-eks-cluster-security-hub-findings`

**Subscribe to Alerts:**
```bash
# GuardDuty
aws sns subscribe \
  --topic-arn $(terraform output -raw guardduty_sns_topic_arn) \
  --protocol email \
  --notification-endpoint sre-team@example.com \
  --region us-gov-west-1

# Security Hub
aws sns subscribe \
  --topic-arn $(terraform output -raw security_hub_sns_topic_arn) \
  --protocol email \
  --notification-endpoint sre-team@example.com \
  --region us-gov-west-1
```

### Critical Alerts

**Immediate Response Required:**
- GuardDuty CRITICAL findings (malware, crypto mining)
- Pod CrashLoopBackOff in production namespace
- Node NotReady status
- PVC > 90% full
- API server latency > 2s

**Response Within 1 Hour:**
- GuardDuty HIGH findings
- Security Hub compliance failures
- Pod restarts > 5 in 10 minutes
- Memory/CPU > 85% sustained

---

## Common Tasks

### Deploy New Application

```bash
# 1. Create namespace
kubectl create namespace my-app

# 2. Enable Istio sidecar injection
kubectl label namespace my-app istio-injection=enabled

# 3. Create secrets in Secrets Manager
aws secretsmanager create-secret \
  --name enhanced-eks-cluster/my-app/db-creds \
  --secret-string '{"username":"admin","password":"secret"}' \
  --kms-key-id $(terraform output -raw secrets_manager_kms_key_id) \
  --region us-gov-west-1

# 4. Create ExternalSecret (if using External Secrets Operator)
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-creds
  namespace: my-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-creds
  data:
  - secretKey: username
    remoteRef:
      key: enhanced-eks-cluster/my-app/db-creds
      property: username
  - secretKey: password
    remoteRef:
      key: enhanced-eks-cluster/my-app/db-creds
      property: password
EOF

# 5. Deploy application
helm upgrade --install my-app ./charts/my-app \
  --namespace my-app \
  --values values-prod.yaml \
  --wait

# 6. Verify deployment
kubectl get pods -n my-app
kubectl logs -n my-app -l app=my-app --tail=50
```

### Scale Application

```bash
# Manual scaling
kubectl scale deployment my-app -n my-app --replicas=5

# Check HPA status
kubectl get hpa -n my-app

# Check KEDA ScaledObject
kubectl get scaledobject -n my-app
```

### Update Application

```bash
# Rolling update
helm upgrade my-app ./charts/my-app \
  --namespace my-app \
  --values values-prod.yaml \
  --wait

# Watch rollout
kubectl rollout status deployment/my-app -n my-app

# Rollback if needed
helm rollback my-app -n my-app
```

### Rotate Secrets

```bash
# 1. Update secret in Secrets Manager
aws secretsmanager update-secret \
  --secret-id enhanced-eks-cluster/my-app/db-creds \
  --secret-string '{"username":"admin","password":"new-secret"}' \
  --region us-gov-west-1

# 2. External Secrets Operator syncs automatically (1 hour default)
# Force immediate sync:
kubectl annotate externalsecret db-creds -n my-app \
  force-sync=$(date +%s) --overwrite

# 3. Restart pods to pick up new secret
kubectl rollout restart deployment/my-app -n my-app
```

### Add New Node Pool (Auto Mode handles this automatically)

Auto Mode automatically provisions nodes based on pod requirements. No manual intervention needed.

```bash
# Check Auto Mode status
kubectl get nodes -o wide

# View node pool distribution
kubectl get nodes -o custom-columns=NAME:.metadata.name,POOL:.metadata.labels.eks\\.amazonaws\\.com/nodepool
```

---

## Troubleshooting

### Pod Won't Start

**Symptoms:** Pod stuck in Pending, CrashLoopBackOff, or ImagePullBackOff

**Diagnosis:**
```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Check logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous container
```

**Common Causes:**
1. **Insufficient resources**: Auto Mode will provision nodes (wait 2-3 minutes)
2. **Image pull errors**: Check ECR permissions, image exists
3. **Secret not found**: Verify ExternalSecret synced
4. **Init container failed**: Check init container logs

**Resolution:**
```bash
# Force pod recreation
kubectl delete pod <pod-name> -n <namespace>

# Check Auto Mode provisioning
kubectl get nodes --watch

# Verify secrets
kubectl get secret <secret-name> -n <namespace>
```

### High Memory/CPU Usage

**Symptoms:** Nodes or pods consuming > 85% resources

**Diagnosis:**
```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n <namespace>

# Check resource requests/limits
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Limits\|Requests"
```

**Resolution:**
```bash
# Scale horizontally (if HPA not configured)
kubectl scale deployment <deployment> -n <namespace> --replicas=<count>

# Update resource limits
kubectl set resources deployment <deployment> -n <namespace> \
  --limits=cpu=1000m,memory=1Gi \
  --requests=cpu=500m,memory=512Mi

# Check Auto Mode adding nodes
kubectl get nodes --watch
```

### Istio Sidecar Issues

**Symptoms:** Pod has no sidecar, mTLS failures, traffic not routed

**Diagnosis:**
```bash
# Check if namespace has injection enabled
kubectl get namespace <namespace> -o jsonpath='{.metadata.labels.istio-injection}'

# Check sidecar status
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].name}'

# Check Istio proxy logs
kubectl logs <pod-name> -n <namespace> -c istio-proxy
```

**Resolution:**
```bash
# Enable injection on namespace
kubectl label namespace <namespace> istio-injection=enabled

# Restart pods to inject sidecar
kubectl rollout restart deployment/<deployment> -n <namespace>

# Verify injection
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].name}'
```

### KEDA Autoscaling Not Working

**Symptoms:** Pods not scaling based on events

**Diagnosis:**
```bash
# Check ScaledObject
kubectl get scaledobject -n <namespace>
kubectl describe scaledobject <name> -n <namespace>

# Check KEDA operator logs
kubectl logs -n keda -l app=keda-operator

# Check metrics
kubectl get hpa -n <namespace>
```

**Resolution:**
```bash
# Verify ScaledObject configuration
kubectl get scaledobject <name> -n <namespace> -o yaml

# Check trigger source (SQS, Kinesis, etc.)
aws sqs get-queue-attributes --queue-url <url> --attribute-names ApproximateNumberOfMessages

# Restart KEDA operator if needed
kubectl rollout restart deployment/keda-operator -n keda
```

### GuardDuty Alert: Crypto Mining Detected

**Symptoms:** GuardDuty finding for crypto mining activity

**Immediate Actions:**
```bash
# 1. Identify affected pod/node
aws guardduty get-findings \
  --detector-id <detector-id> \
  --finding-ids <finding-id> \
  --region us-gov-west-1

# 2. Isolate pod (remove from service)
kubectl label pod <pod-name> -n <namespace> quarantine=true
kubectl scale deployment <deployment> -n <namespace> --replicas=0

# 3. Capture forensics
kubectl logs <pod-name> -n <namespace> > /tmp/pod-logs.txt
kubectl describe pod <pod-name> -n <namespace> > /tmp/pod-describe.txt

# 4. Delete compromised pod
kubectl delete pod <pod-name> -n <namespace>

# 5. Investigate image
aws ecr describe-images --repository-name <repo> --region us-gov-west-1
aws ecr start-image-scan --repository-name <repo> --image-id imageTag=<tag> --region us-gov-west-1
```

### Node NotReady

**Symptoms:** Node shows NotReady status

**Diagnosis:**
```bash
# Check node status
kubectl describe node <node-name>

# Check node logs (via SSM)
aws ssm start-session --target <instance-id> --region us-gov-west-1
# Then: journalctl -u kubelet -n 100
```

**Resolution:**
```bash
# Drain node
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Auto Mode will replace node automatically
# Or manually terminate instance (Auto Mode provisions new one)
aws ec2 terminate-instances --instance-ids <instance-id> --region us-gov-west-1

# Verify new node
kubectl get nodes --watch
```

---

## Maintenance Windows

### Monthly EKS Version Upgrade

**Preparation (Week 1):**
```bash
# Check current version
kubectl version --short

# Review release notes
# https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html

# Test in staging environment
```

**Execution (Week 2 - Maintenance Window):**
```bash
# 1. Backup cluster state
# (Velero backup if configured)

# 2. Update control plane
aws eks update-cluster-version \
  --name enhanced-eks-cluster \
  --kubernetes-version 1.35 \
  --region us-gov-west-1

# 3. Wait for update (15-30 minutes)
aws eks describe-cluster --name enhanced-eks-cluster --region us-gov-west-1 --query 'cluster.status'

# 4. Update add-ons
aws eks update-addon --cluster-name enhanced-eks-cluster --addon-name kube-proxy --addon-version <version> --region us-gov-west-1
aws eks update-addon --cluster-name enhanced-eks-cluster --addon-name vpc-cni --addon-version <version> --region us-gov-west-1
aws eks update-addon --cluster-name enhanced-eks-cluster --addon-name coredns --addon-version <version> --region us-gov-west-1

# 5. Auto Mode handles node updates automatically
# Nodes will be replaced with new version over time

# 6. Verify
kubectl get nodes
kubectl version --short
```

### Weekly Security Patching

**Automated by Auto Mode:**
- Auto Mode automatically patches nodes
- Nodes are replaced with latest AMI
- No manual intervention required

**Verify:**
```bash
# Check node AMI versions
kubectl get nodes -o custom-columns=NAME:.metadata.name,AMI:.status.nodeInfo.osImage
```

---

## Incident Response

### Severity Levels

**P0 - Critical (15 min response):**
- Cluster API server down
- Multiple nodes NotReady
- Production application completely down
- Active security breach (GuardDuty CRITICAL)

**P1 - High (1 hour response):**
- Single node NotReady
- Application degraded performance
- GuardDuty HIGH findings
- PVC full causing pod failures

**P2 - Medium (4 hour response):**
- Non-critical pod failures
- Performance degradation
- Security Hub compliance failures

**P3 - Low (Next business day):**
- Documentation updates
- Non-urgent optimization
- Informational alerts

### Incident Response Workflow

**1. Detection**
- Alert received (SNS, PagerDuty, monitoring)
- User report
- Automated health check failure

**2. Triage (5 minutes)**
```bash
# Quick health check
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running
kubectl top nodes

# Check recent events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | head -20

# Check GuardDuty/Security Hub
aws guardduty list-findings --detector-id <id> --region us-gov-west-1
```

**3. Investigation**
- Review logs (CloudWatch, kubectl logs)
- Check metrics (Prometheus, CloudWatch)
- Review recent changes (Git, Terraform)

**4. Mitigation**
- Apply immediate fix
- Scale resources if needed
- Isolate affected components

**5. Resolution**
- Verify fix
- Monitor for recurrence
- Update runbooks

**6. Post-Mortem**
- Document incident
- Identify root cause
- Implement preventive measures

---

## Capacity Planning

### Monthly Review

**Metrics to Track:**
```bash
# Node utilization trend
kubectl top nodes

# Pod count trend
kubectl get pods --all-namespaces --no-headers | wc -l

# PVC usage trend
kubectl get pvc --all-namespaces -o json | jq '.items[] | {name:.metadata.name, namespace:.metadata.namespace, capacity:.spec.resources.requests.storage}'

# Cost trend
# Review AWS Cost Explorer or Kubecost dashboard
```

**Capacity Thresholds:**
- Nodes: Auto Mode handles automatically
- Storage: Alert at 85%, expand at 90%
- Costs: Alert if > 10% over budget

### Scaling Recommendations

**Horizontal Scaling (Preferred):**
- Add more pod replicas
- KEDA handles event-driven scaling
- Auto Mode provisions nodes automatically

**Vertical Scaling:**
- Increase pod resource requests/limits
- Auto Mode selects appropriate instance types

**Storage Scaling:**
```bash
# Expand PVC (if storage class supports it)
kubectl patch pvc <pvc-name> -n <namespace> -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

---

## AI-Driven Automation

This infrastructure is designed for AI-driven operations via Amazon Bedrock and MCP (Model Context Protocol).

**See [SRE-RUNBOOKS.md](SRE-RUNBOOKS.md) for:**
- Automated runbooks executable by AI agents
- MCP server integration patterns
- Bedrock-powered incident response
- Self-healing workflows

**See [AI-PLAYBOOKS.md](AI-PLAYBOOKS.md) for:**
- Agentic workflow definitions
- Decision trees for automated remediation
- Integration with Bedrock Claude models
- MCP client/server architecture

---

## Quick Reference

### Essential Commands

```bash
# Cluster access
aws eks update-kubeconfig --region us-gov-west-1 --name enhanced-eks-cluster

# Health check
kubectl get nodes && kubectl get pods --all-namespaces | grep -v Running

# Logs
kubectl logs -f <pod> -n <namespace>
kubectl logs <pod> -n <namespace> -c istio-proxy  # Sidecar logs

# Exec into pod
kubectl exec -it <pod> -n <namespace> -- /bin/bash

# Port forward
kubectl port-forward -n <namespace> svc/<service> <local-port>:<remote-port>

# Describe resources
kubectl describe pod <pod> -n <namespace>
kubectl describe node <node>

# Events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Resource usage
kubectl top nodes
kubectl top pods -n <namespace>
```

### Important ARNs/IDs

```bash
# Get from Terraform outputs
terraform output guardduty_detector_id
terraform output guardduty_sns_topic_arn
terraform output security_hub_sns_topic_arn
terraform output kms_eks_secrets_key_arn
terraform output pod_identity_role_arn
```

### Support Contacts

- **AWS Support**: Enterprise support case
- **Security Team**: security@example.com
- **Platform Team**: platform@example.com
- **On-Call SRE**: PagerDuty escalation

---

## Additional Resources

- [ARCHITECTURE.md](ARCHITECTURE.md) - Infrastructure architecture
- [CONSIDERATIONS.md](CONSIDERATIONS.md) - Production readiness
- [FEDRAMP-COMPLIANCE.md](FEDRAMP-COMPLIANCE.md) - Compliance guide
- [SECRETS-MANAGEMENT.md](SECRETS-MANAGEMENT.md) - Secrets guide
- [SRE-RUNBOOKS.md](SRE-RUNBOOKS.md) - Automated runbooks
- [AI-PLAYBOOKS.md](AI-PLAYBOOKS.md) - AI-driven workflows
