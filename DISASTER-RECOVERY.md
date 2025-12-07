# Disaster Recovery Plan

Comprehensive disaster recovery and business continuity procedures for EKS cluster.

## Recovery Objectives

| Metric | Target | Maximum Tolerable |
|--------|--------|-------------------|
| **RTO** (Recovery Time Objective) | 4 hours | 8 hours |
| **RPO** (Recovery Point Objective) | 1 hour | 4 hours |
| **Data Loss** | < 1 hour | < 4 hours |
| **Availability** | 99.9% | 99.5% |

## Disaster Scenarios

### 1. Region Failure (Complete AWS Region Outage)
**Probability**: Very Low  
**Impact**: Critical  
**RTO**: 4 hours  
**RPO**: 1 hour

### 2. AZ Failure (Single Availability Zone Outage)
**Probability**: Low  
**Impact**: Medium  
**RTO**: Auto (EKS Auto Mode)  
**RPO**: 0 (No data loss)

### 3. Control Plane Failure
**Probability**: Very Low  
**Impact**: High  
**RTO**: AWS SLA (99.95%)  
**RPO**: 0

### 4. Data Corruption/Deletion
**Probability**: Low  
**Impact**: High  
**RTO**: 2 hours  
**RPO**: 1 hour

### 5. Ransomware Attack
**Probability**: Medium  
**Impact**: Critical  
**RTO**: 8 hours  
**RPO**: 4 hours

## Backup Strategy

### Infrastructure as Code (Terraform)
**Backup**: Git repository  
**Frequency**: Every commit  
**Retention**: Indefinite  
**Location**: GitHub/GitLab + S3

```bash
# Backup Terraform state
terraform state pull > backup/terraform-$(date +%Y%m%d-%H%M%S).tfstate
aws s3 cp backup/terraform-*.tfstate s3://backup-bucket/terraform-state/
```

### Kubernetes Manifests (Helm Charts)
**Backup**: Git repository  
**Frequency**: Every commit  
**Retention**: Indefinite  
**Location**: GitHub/GitLab

```bash
# Export all Kubernetes resources
kubectl get all --all-namespaces -o yaml > backup/k8s-all-$(date +%Y%m%d).yaml
aws s3 cp backup/k8s-all-*.yaml s3://backup-bucket/k8s-manifests/
```

### Application Data (Persistent Volumes)
**Backup**: EBS Snapshots  
**Frequency**: Daily  
**Retention**: 30 days  
**Location**: Same region + cross-region copy

```bash
# Automated EBS snapshot via AWS Backup
aws backup start-backup-job \
  --backup-vault-name eks-backup-vault \
  --resource-arn arn:aws-us-gov:ec2:us-gov-west-1:*:volume/* \
  --iam-role-arn arn:aws-us-gov:iam::*:role/AWSBackupRole \
  --region us-gov-west-1
```

### Secrets (AWS Secrets Manager)
**Backup**: Automatic replication  
**Frequency**: Real-time  
**Retention**: Version history  
**Location**: us-gov-west-1 + us-gov-east-1

```bash
# Enable secret replication
aws secretsmanager replicate-secret-to-regions \
  --secret-id <secret-name> \
  --add-replica-regions Region=us-gov-east-1,KmsKeyId=<kms-key-id> \
  --region us-gov-west-1
```

### Databases (RDS/DynamoDB)
**Backup**: Automated snapshots  
**Frequency**: Daily + continuous (PITR)  
**Retention**: 35 days  
**Location**: Same region + cross-region copy

```bash
# RDS automated backups (configured in Terraform)
# DynamoDB PITR (configured in Terraform)
# Manual snapshot for DR testing
aws rds create-db-snapshot \
  --db-instance-identifier <db-id> \
  --db-snapshot-identifier dr-test-$(date +%Y%m%d)
```

### Logs & Audit Trails
**Backup**: S3 with versioning  
**Frequency**: Real-time  
**Retention**: 7 years (compliance)  
**Location**: S3 + Glacier

- CloudTrail: S3 bucket with lifecycle policy
- VPC Flow Logs: S3 bucket with lifecycle policy
- EKS Audit Logs: CloudWatch Logs + S3 export
- Application Logs: CloudWatch Logs + S3 export

## Recovery Procedures

### Scenario 1: Region Failure Recovery

**Prerequisites:**
- DR region: us-gov-east-1
- Cross-region replication enabled
- Terraform state backed up
- DNS failover configured

**Recovery Steps:**

**1. Activate DR Region (0-30 minutes)**
```bash
# Switch to DR region
export AWS_REGION=us-gov-east-1

# Deploy infrastructure
cd terraform/
terraform init -backend-config="region=us-gov-east-1"
terraform apply -var="aws_region=us-gov-east-1"
```

**2. Restore Data (30-90 minutes)**
```bash
# Restore from cross-region snapshots
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier eks-db-dr \
  --db-snapshot-identifier <snapshot-id> \
  --region us-gov-east-1

# Restore EBS volumes from snapshots
aws ec2 create-volume \
  --snapshot-id <snapshot-id> \
  --availability-zone us-gov-east-1a \
  --region us-gov-east-1
```

**3. Deploy Applications (90-180 minutes)**
```bash
# Configure kubectl for DR cluster
aws eks update-kubeconfig \
  --region us-gov-east-1 \
  --name enhanced-eks-cluster-dr

# Deploy applications via Helm
helm upgrade --install <app> helm/<chart> \
  --namespace <namespace> \
  -f values-dr.yaml

# Verify deployments
kubectl get pods --all-namespaces
kubectl get svc --all-namespaces
```

**4. Update DNS (180-240 minutes)**
```bash
# Update Route 53 health check
aws route53 change-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --change-batch file://dns-failover.json

# Verify DNS propagation
dig +short <domain-name>
```

**5. Verify & Monitor (240+ minutes)**
```bash
# Run smoke tests
./scripts/smoke-tests.sh

# Monitor metrics
watch kubectl top nodes
watch kubectl get pods --all-namespaces
```

### Scenario 2: Data Corruption Recovery

**1. Identify Corruption (0-15 minutes)**
```bash
# Check data integrity
kubectl exec -it <pod> -- /app/verify-data.sh

# Review recent changes
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::S3::Object \
  --start-time $(date -u -d '4 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --region us-gov-west-1
```

**2. Stop Write Operations (15-30 minutes)**
```bash
# Scale down applications
kubectl scale deployment <deployment> --replicas=0

# Enable S3 versioning (if not already)
aws s3api put-bucket-versioning \
  --bucket <bucket-name> \
  --versioning-configuration Status=Enabled
```

**3. Restore from Backup (30-120 minutes)**
```bash
# Restore S3 objects to previous version
aws s3api list-object-versions \
  --bucket <bucket-name> \
  --prefix <prefix> | \
  jq -r '.Versions[] | select(.IsLatest==false) | .VersionId' | \
  head -1 | \
  xargs -I {} aws s3api copy-object \
    --bucket <bucket-name> \
    --copy-source <bucket-name>/<key>?versionId={} \
    --key <key>

# Restore database from snapshot
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier <source-db> \
  --target-db-instance-identifier <target-db> \
  --restore-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S)
```

**4. Verify Data Integrity (120-180 minutes)**
```bash
# Run data validation
kubectl exec -it <pod> -- /app/verify-data.sh

# Compare checksums
aws s3api head-object --bucket <bucket> --key <key> --query ETag
```

**5. Resume Operations (180+ minutes)**
```bash
# Scale up applications
kubectl scale deployment <deployment> --replicas=<original-count>

# Monitor for issues
kubectl logs -f deployment/<deployment>
```

### Scenario 3: Ransomware Recovery

**1. Isolate Infected Systems (0-15 minutes)**
```bash
# Quarantine infected nodes
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --force

# Block network access
kubectl apply -f network-policy-deny-all.yaml

# Revoke all credentials
aws iam delete-access-key --access-key-id <key-id>
```

**2. Assess Damage (15-60 minutes)**
```bash
# Check for encrypted files
kubectl exec -it <pod> -- find /data -name "*.encrypted"

# Review GuardDuty findings
aws guardduty get-findings \
  --detector-id <detector-id> \
  --finding-ids <finding-ids> \
  --region us-gov-west-1

# Check CloudTrail for unauthorized access
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PutObject \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S)
```

**3. Restore from Clean Backup (60-240 minutes)**
```bash
# Restore from pre-infection snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier eks-db-clean \
  --db-snapshot-identifier <clean-snapshot-id>

# Restore S3 from versioning
aws s3 sync s3://<bucket>/ s3://<bucket-clean>/ \
  --source-region us-gov-west-1 \
  --exclude "*.encrypted"

# Redeploy cluster from Terraform
terraform destroy -auto-approve
terraform apply -auto-approve
```

**4. Harden Security (240-360 minutes)**
```bash
# Rotate all secrets
aws secretsmanager rotate-secret --secret-id <secret-name>

# Update security groups
aws ec2 revoke-security-group-ingress --group-id <sg-id> --ip-permissions <rules>

# Apply restrictive RBAC
kubectl apply -f rbac-restrictive.yaml

# Enable MFA for all users
aws iam enable-mfa-device --user-name <user> --serial-number <mfa-arn> --authentication-code1 <code1> --authentication-code2 <code2>
```

**5. Forensics & Reporting (360+ minutes)**
```bash
# Preserve evidence
aws ec2 create-snapshot --volume-id <volume-id> --description "Ransomware forensics"

# Generate incident report
# See INCIDENT-RESPONSE.md

# Notify authorities (if required)
# FBI IC3: https://www.ic3.gov/
```

## DR Testing Schedule

### Monthly Tests
- **Backup Verification**: Restore random backup to test environment
- **Runbook Review**: Update procedures based on changes
- **Monitoring Check**: Verify all alerts are working

### Quarterly Tests
- **Partial Failover**: Test single component recovery
- **Data Restore**: Full database restore to test environment
- **Team Training**: Tabletop exercise with on-call team

### Annual Tests
- **Full DR Drill**: Complete region failover
- **Executive Involvement**: Include leadership in drill
- **Third-Party Audit**: External validation of DR capabilities
- **Update RTO/RPO**: Reassess based on business needs

## DR Testing Checklist

**Pre-Test:**
- [ ] Schedule maintenance window
- [ ] Notify stakeholders
- [ ] Backup current state
- [ ] Prepare rollback plan
- [ ] Assign roles to team members

**During Test:**
- [ ] Document start time
- [ ] Follow runbook exactly
- [ ] Record all commands executed
- [ ] Note any deviations
- [ ] Track time for each step
- [ ] Capture screenshots/logs

**Post-Test:**
- [ ] Verify all services restored
- [ ] Run smoke tests
- [ ] Compare RTO/RPO to targets
- [ ] Document lessons learned
- [ ] Update runbooks
- [ ] Schedule follow-up improvements

## Automation

**Automated Backups:**
```hcl
# AWS Backup plan (add to Terraform)
resource "aws_backup_plan" "eks" {
  name = "eks-backup-plan"
  
  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.eks.name
    schedule          = "cron(0 2 * * ? *)"
    
    lifecycle {
      delete_after = 30
    }
    
    copy_action {
      destination_vault_arn = aws_backup_vault.eks_dr.arn
      
      lifecycle {
        delete_after = 30
      }
    }
  }
}
```

**Automated DR Failover:**
```bash
# Lambda function for automated failover (triggered by CloudWatch alarm)
# See lambda/dr-failover/ for implementation
```

## Cost Considerations

**DR Infrastructure:**
- Standby cluster: $0 (deploy on-demand)
- Cross-region snapshots: ~$50/month
- S3 replication: ~$20/month
- Secrets Manager replication: ~$5/month
- **Total**: ~$75/month

**DR Test Costs:**
- Monthly test: ~$10
- Quarterly test: ~$50
- Annual test: ~$200
- **Total**: ~$400/year

## Compliance

**FedRAMP Requirements:**
- Backup frequency: Daily minimum ✓
- Backup retention: 90 days minimum ✓
- DR testing: Annual minimum ✓
- RTO documentation: Required ✓
- RPO documentation: Required ✓

**STIG Requirements:**
- Encrypted backups: Required ✓
- Off-site backups: Required ✓
- Backup verification: Required ✓
- DR plan documentation: Required ✓

## Contact Information

- **DR Coordinator**: dr-team@example.com
- **AWS Support**: 1-800-xxx-xxxx (Enterprise)
- **Backup Admin**: backup-admin@example.com
- **Security Team**: security@example.com

## Related Documentation

- [INCIDENT-RESPONSE.md](INCIDENT-RESPONSE.md) - Incident response procedures
- [DAY2-OPERATIONS.md](DAY2-OPERATIONS.md) - Daily operations
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
